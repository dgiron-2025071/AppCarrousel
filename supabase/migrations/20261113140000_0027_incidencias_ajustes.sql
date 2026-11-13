-- =============================================================================
-- Carrousel — Núcleo backend
-- MT-02 / Archivo 27: incidencias automáticas y ajustes de jornada
-- Fecha: 2026-11-13
--
-- Crea:
--   1. public.tipo_incidencia       — llegada tarde, salida temprana, parque
--      distinto y GPS impreciso.
--   2. public.incidencias_jornada   — incidencias derivadas de cada jornada.
--   3. public.jornadas_ajustes      — historial inmutable de correcciones.
--   4. private.jornadas_calcular_incidencias() — recálculo idempotente.
--   5. public.ajustar_jornada()     — RPC para que un admin corrija los tiempos.
--   6. `jornadas_cerrar` tolerante a ajustes administrativos.
--
-- Modelo:
--   Las incidencias no las escribe el cliente: se recalculan al cerrar la
--   jornada y al corregirla. Una corrección exige motivo, deja el historial
--   anterior y el nuevo en `jornadas_ajustes` y no vuelve a validar la
--   geocerca, porque el admin está corrigiendo tiempos, no marcando presencia.
--
-- Depende de 0005/0015 (jornadas, geocerca congelada), 0009 (sin tope de 24 h),
-- 0024 (horarios, zona horaria y umbral GPS) y 0023/0026 (alcance).
--
-- Ejecución local: supabase db reset
-- Nota: el CLI de Supabase aplica cada migración dentro de una transacción.
-- No se incluye BEGIN/COMMIT explícito para evitar transacciones anidadas.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Tipos y destino de las FK compuestas
-- -----------------------------------------------------------------------------
create type public.tipo_incidencia as enum (
  'llegada_tarde',
  'salida_temprana',
  'parque_distinto',
  'gps_impreciso'
);

comment on type public.tipo_incidencia is
  'Incidencias detectadas al cerrar o ajustar una jornada.';

alter table public.jornadas
  add constraint jornadas_empresa_id_key unique (empresa_id, id);

-- -----------------------------------------------------------------------------
-- 2. Incidencias
-- -----------------------------------------------------------------------------
create table public.incidencias_jornada (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid not null references public.empresas (id) on delete restrict,
  jornada_id  uuid not null,
  empleado_id uuid not null,
  tipo        public.tipo_incidencia not null,
  minutos     integer,
  detalle     text,
  creado_en   timestamptz not null default now(),

  constraint incidencias_jornada_tipo_key unique (jornada_id, tipo),
  constraint incidencias_jornada_fk
    foreign key (empresa_id, jornada_id)
    references public.jornadas (empresa_id, id)
    on delete restrict,
  constraint incidencias_empleado_fk
    foreign key (empresa_id, empleado_id)
    references public.perfiles (empresa_id, id)
    on delete restrict,
  constraint incidencias_minutos_valido
    check (minutos is null or minutos >= 0),
  constraint incidencias_detalle_valido
    check (detalle is null or length(detalle) <= 500)
);

comment on table public.incidencias_jornada is
  'Incidencias derivadas de una jornada. Las escribe el backend al cerrar o ajustar; el cliente solo las lee.';
comment on column public.incidencias_jornada.minutos is
  'Minutos de diferencia en llegada tarde o salida temprana. NULL en las demás incidencias.';

create index incidencias_empresa_empleado_idx
  on public.incidencias_jornada (empresa_id, empleado_id, creado_en desc);

create index incidencias_empresa_tipo_idx
  on public.incidencias_jornada (empresa_id, tipo, creado_en desc);

alter table public.incidencias_jornada enable row level security;

create policy incidencias_select_propia_o_equipo
  on public.incidencias_jornada
  for select
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and (
      empleado_id = (select auth.uid())
      or private.perfil_en_alcance(empleado_id)
    )
  );

comment on policy incidencias_select_propia_o_equipo on public.incidencias_jornada is
  'El empleado ve sus incidencias; el admin ve las de su subárbol.';

revoke all on table public.incidencias_jornada from anon, authenticated;
grant select on table public.incidencias_jornada to authenticated;

-- -----------------------------------------------------------------------------
-- 3. Historial de ajustes
-- -----------------------------------------------------------------------------
create table public.jornadas_ajustes (
  id                  uuid primary key default gen_random_uuid(),
  empresa_id          uuid not null references public.empresas (id) on delete restrict,
  jornada_id          uuid not null,
  empleado_id         uuid not null,
  ajustado_por        uuid not null,
  motivo              text not null,
  entrada_en_anterior timestamptz not null,
  salida_en_anterior  timestamptz not null,
  entrada_en_nueva    timestamptz not null,
  salida_en_nueva     timestamptz not null,
  creado_en           timestamptz not null default now(),

  constraint ajustes_jornada_fk
    foreign key (empresa_id, jornada_id)
    references public.jornadas (empresa_id, id)
    on delete restrict,
  constraint ajustes_empleado_fk
    foreign key (empresa_id, empleado_id)
    references public.perfiles (empresa_id, id)
    on delete restrict,
  constraint ajustes_autor_fk
    foreign key (empresa_id, ajustado_por)
    references public.perfiles (empresa_id, id)
    on delete restrict,
  constraint ajustes_motivo_valido
    check (length(btrim(motivo)) between 10 and 2000),
  constraint ajustes_rango_valido
    check (salida_en_nueva > entrada_en_nueva)
);

comment on table public.jornadas_ajustes is
  'Historial inmutable de correcciones de jornada. Cada fila conserva los tiempos anteriores y los nuevos, el motivo y el admin que ajustó.';
comment on column public.jornadas_ajustes.motivo is
  'Motivo obligatorio de la corrección. Queda visible para auditoría y para el empleado.';

create index ajustes_empresa_jornada_idx
  on public.jornadas_ajustes (empresa_id, jornada_id, creado_en desc);

create index ajustes_empresa_empleado_idx
  on public.jornadas_ajustes (empresa_id, empleado_id, creado_en desc);

-- El historial no se edita ni se borra, ni siquiera con service_role. Para
-- corregir una corrección se agrega otra fila.
create or replace function private.jornadas_ajustes_inmutables()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'El historial de ajustes de jornada es inmutable'
    using errcode = '23514';
end;
$$;

comment on function private.jornadas_ajustes_inmutables() is
  'Bloquea UPDATE y DELETE sobre jornadas_ajustes para conservar la auditoría.';

revoke all on function private.jornadas_ajustes_inmutables() from public;

create trigger jornadas_ajustes_inmutables
before update or delete on public.jornadas_ajustes
for each row execute function private.jornadas_ajustes_inmutables();

alter table public.jornadas_ajustes enable row level security;

create policy ajustes_select_propio_o_equipo
  on public.jornadas_ajustes
  for select
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and (
      empleado_id = (select auth.uid())
      or private.perfil_en_alcance(empleado_id)
    )
  );

comment on policy ajustes_select_propio_o_equipo on public.jornadas_ajustes is
  'El empleado ve los ajustes de sus jornadas; el admin ve los de su subárbol. La escritura solo ocurre por RPC.';

revoke all on table public.jornadas_ajustes from anon, authenticated;
grant select on table public.jornadas_ajustes to authenticated;

-- -----------------------------------------------------------------------------
-- 4. Cálculo de incidencias
-- -----------------------------------------------------------------------------
create or replace function private.jornadas_calcular_incidencias(p_jornada_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_jornada          public.jornadas%rowtype;
  v_zona             text;
  v_gps_max          integer;
  v_parque_centro    uuid;
  v_empleado_centro  uuid;
  v_fecha            date;
  v_horario_id       uuid;
  v_hora_entrada     time;
  v_hora_salida      time;
  v_tol_entrada      integer;
  v_tol_salida       integer;
  v_entrada_prog     timestamptz;
  v_salida_prog      timestamptz;
  v_minutos          integer;
  v_precision        double precision;
begin
  select j.*
    into v_jornada
  from public.jornadas j
  where j.id = p_jornada_id;

  if not found or v_jornada.salida_en is null then
    return;
  end if;

  select e.zona_horaria, e.gps_precision_maxima_metros
    into v_zona, v_gps_max
  from public.empresas e
  where e.id = v_jornada.empresa_id;

  -- Se recalcula desde cero: una corrección puede eliminar o cambiar una
  -- incidencia previa.
  delete from public.incidencias_jornada i
   where i.jornada_id = p_jornada_id;

  v_precision := greatest(
    coalesce(v_jornada.entrada_precision_metros, 0),
    coalesce(v_jornada.salida_precision_metros, 0)
  );

  if v_precision > v_gps_max then
    insert into public.incidencias_jornada (
      empresa_id, jornada_id, empleado_id, tipo, detalle
    )
    values (
      v_jornada.empresa_id,
      v_jornada.id,
      v_jornada.empleado_id,
      'gps_impreciso',
      format('Precisión GPS de %s m; el máximo configurado es %s m',
             round(v_precision), v_gps_max)
    );
  end if;

  select p.centro_costo_id
    into v_parque_centro
  from public.parques p
  where p.id = v_jornada.parque_id;

  select pf.centro_costo_id
    into v_empleado_centro
  from public.perfiles pf
  where pf.id = v_jornada.empleado_id;

  if v_parque_centro is distinct from v_empleado_centro then
    insert into public.incidencias_jornada (
      empresa_id, jornada_id, empleado_id, tipo, detalle
    )
    values (
      v_jornada.empresa_id,
      v_jornada.id,
      v_jornada.empleado_id,
      'parque_distinto',
      'La jornada se registró en un parque de otro centro de costo'
    );
  end if;

  v_fecha := (v_jornada.entrada_en at time zone v_zona)::date;
  select h.horario_id, h.hora_entrada, h.hora_salida,
         h.tolerancia_entrada_min, h.tolerancia_salida_min
    into v_horario_id, v_hora_entrada, v_hora_salida,
         v_tol_entrada, v_tol_salida
  from private.horario_del_dia(v_jornada.empleado_id, v_fecha) h;

  if v_horario_id is not null then
    v_entrada_prog := ((v_fecha + v_hora_entrada) at time zone v_zona);
    v_salida_prog  := ((v_fecha + v_hora_salida) at time zone v_zona);

    if v_hora_salida <= v_hora_entrada then
      v_salida_prog := v_salida_prog + interval '1 day';
    end if;

    if v_jornada.entrada_en
       > v_entrada_prog + make_interval(mins => v_tol_entrada) then
      v_minutos := floor(
        extract(epoch from (v_jornada.entrada_en - v_entrada_prog)) / 60
      )::integer;

      insert into public.incidencias_jornada (
        empresa_id, jornada_id, empleado_id, tipo, minutos, detalle
      )
      values (
        v_jornada.empresa_id,
        v_jornada.id,
        v_jornada.empleado_id,
        'llegada_tarde',
        v_minutos,
        format('Entrada %s min después de la hora programada', v_minutos)
      );
    end if;

    if v_jornada.salida_en
       < v_salida_prog - make_interval(mins => v_tol_salida) then
      v_minutos := floor(
        extract(epoch from (v_salida_prog - v_jornada.salida_en)) / 60
      )::integer;

      insert into public.incidencias_jornada (
        empresa_id, jornada_id, empleado_id, tipo, minutos, detalle
      )
      values (
        v_jornada.empresa_id,
        v_jornada.id,
        v_jornada.empleado_id,
        'salida_temprana',
        v_minutos,
        format('Salida %s min antes de la hora programada', v_minutos)
      );
    end if;
  end if;
end;
$$;

comment on function private.jornadas_calcular_incidencias(uuid) is
  'Recalcula las incidencias de una jornada cerrada: GPS, parque y horario. Idempotente.';

revoke all on function private.jornadas_calcular_incidencias(uuid) from public;

create or replace function private.jornadas_incidencias()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.salida_en is null then
    delete from public.incidencias_jornada i where i.jornada_id = new.id;
    return new;
  end if;

  if tg_op = 'INSERT' then
    perform private.jornadas_calcular_incidencias(new.id);
    return new;
  end if;

  if new.salida_en is distinct from old.salida_en
     or new.entrada_en is distinct from old.entrada_en
     or new.parque_id is distinct from old.parque_id
     or new.entrada_precision_metros is distinct from old.entrada_precision_metros
     or new.salida_precision_metros is distinct from old.salida_precision_metros then
    perform private.jornadas_calcular_incidencias(new.id);
  end if;

  return new;
end;
$$;

comment on function private.jornadas_incidencias() is
  'Dispara el recálculo al cerrar o corregir los datos que producen incidencias.';

revoke all on function private.jornadas_incidencias() from public;

create trigger jornadas_incidencias
after insert or update of entrada_en, salida_en, parque_id,
  entrada_precision_metros, salida_precision_metros
on public.jornadas
for each row execute function private.jornadas_incidencias();

-- -----------------------------------------------------------------------------
-- 5. Cierre tolerante al ajuste administrativo
-- -----------------------------------------------------------------------------
-- `0015` valida la geocerca cuando hay un JWT. Una corrección de tiempos no es
-- un marcaje: el admin no está dentro del parque. La RPC marca la sesión para
-- que el trigger no revalide el GPS.
create or replace function private.jornadas_cerrar()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dentro_actual   boolean;
  v_dentro_entrada  boolean;
begin
  if coalesce(current_setting('carrousel.ajuste_jornada', true), '') = 'on' then
    return new;
  end if;

  if auth.uid() is null then
    return new;
  end if;

  new.salida_en := coalesce(new.salida_en, clock_timestamp());

  v_dentro_actual := private.en_geocerca_parque(
    new.parque_id, new.salida_lat, new.salida_lon,
    new.salida_precision_metros, false
  );

  v_dentro_entrada := private.en_geocerca_snapshot(
    new.salida_lat, new.salida_lon, new.salida_precision_metros,
    new.entrada_parque_lat, new.entrada_parque_lon,
    new.entrada_parque_radio_metros
  );

  new.salida_dentro_geocerca :=
    coalesce(v_dentro_actual, false) or coalesce(v_dentro_entrada, false);

  if new.salida_dentro_geocerca is not true then
    raise exception 'La salida está fuera de la geocerca del parque'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

comment on function private.jornadas_cerrar() is
  'Cierra la jornada validando la geocerca, salvo en un ajuste administrativo marcado por la RPC.';

-- -----------------------------------------------------------------------------
-- 6. RPC de ajuste
-- -----------------------------------------------------------------------------
create or replace function public.ajustar_jornada(
  p_jornada_id uuid,
  p_entrada_en timestamptz,
  p_salida_en timestamptz,
  p_motivo text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_jornada   public.jornadas%rowtype;
  v_motivo    text;
  v_ajuste_id uuid;
  v_empresa   uuid := private.current_empresa_id();
begin
  if auth.uid() is null or not private.es_admin() then
    raise exception 'Solo un administrador activo puede ajustar jornadas'
      using errcode = '42501';
  end if;

  v_motivo := btrim(coalesce(p_motivo, ''));
  if length(v_motivo) not between 10 and 2000 then
    raise exception 'El motivo del ajuste debe tener entre 10 y 2000 caracteres'
      using errcode = '23514';
  end if;

  if p_entrada_en is null or p_salida_en is null or p_salida_en <= p_entrada_en then
    raise exception 'El rango del ajuste debe tener entrada y salida, con salida posterior'
      using errcode = '23514';
  end if;

  select j.*
    into v_jornada
  from public.jornadas j
  where j.id = p_jornada_id
    and j.empresa_id = v_empresa
  for update;

  if not found then
    raise exception 'La jornada no existe en tu empresa'
      using errcode = '23503';
  end if;

  if v_jornada.salida_en is null then
    raise exception 'La jornada debe estar cerrada para poder ajustarse'
      using errcode = '23514';
  end if;

  if not private.perfil_en_alcance(v_jornada.empleado_id) then
    raise exception 'La jornada está fuera de tu alcance'
      using errcode = '42501';
  end if;

  insert into public.jornadas_ajustes (
    empresa_id, jornada_id, empleado_id, ajustado_por, motivo,
    entrada_en_anterior, salida_en_anterior,
    entrada_en_nueva, salida_en_nueva
  )
  values (
    v_jornada.empresa_id, v_jornada.id, v_jornada.empleado_id, auth.uid(),
    v_motivo,
    v_jornada.entrada_en, v_jornada.salida_en,
    p_entrada_en, p_salida_en
  )
  returning id into v_ajuste_id;

  perform set_config('carrousel.ajuste_jornada', 'on', true);

  update public.jornadas j
     set entrada_en = p_entrada_en,
         salida_en = p_salida_en,
         actualizado_por = auth.uid()
   where j.id = v_jornada.id;

  perform set_config('carrousel.ajuste_jornada', 'off', true);

  return v_ajuste_id;
end;
$$;

comment on function public.ajustar_jornada(uuid, timestamptz, timestamptz, text) is
  'Corrige los tiempos de una jornada cerrada, registra el motivo y el historial y recalcula incidencias. No revalida la geocerca.';

revoke all on function public.ajustar_jornada(uuid, timestamptz, timestamptz, text) from public;
grant execute on function public.ajustar_jornada(uuid, timestamptz, timestamptz, text)
  to authenticated;
