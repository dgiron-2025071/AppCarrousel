-- =============================================================================
-- Carrousel — Propuesta de integración con la operación actual
-- Archivo 22: registro de colaboradores, incidencias y ajustes de jornada
-- Fecha: 2026-11-12
--
-- Lleva a Supabase la lógica de control-jornadas-carrousel:
--
--   1. Registro    — la persona crea su cuenta con el código de su empresa y
--                    queda pendiente hasta que un admin le asigna centro,
--                    puesto y rol (como PENDING_ASSIGNMENT).
--   2. Incidencias — se generan solas al marcar: llegada tarde, salida
--                    temprana, parque distinto al programado y GPS impreciso.
--                    El admin las resuelve o descarta con una nota.
--   3. Ajustes     — el admin corrige la entrada o salida de una jornada
--                    cerrada con un motivo; queda el historial.
--
-- La geocerca ya se exige al marcar (0007), así que no hay incidencia por
-- marcar fuera del parque.
--
-- Depende de 0002–0007, 0018 y 0021.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Registro de colaboradores
-- -----------------------------------------------------------------------------
create type public.estado_registro as enum ('pendiente', 'aprobado', 'rechazado');

create table public.registros (
  id            uuid primary key references auth.users (id) on delete cascade,
  empresa_id    uuid not null references public.empresas (id) on delete cascade,
  email         text not null,
  nombre        text not null,
  telefono      text,
  estado        public.estado_registro not null default 'pendiente',
  motivo        text,
  revisado_por  uuid references public.perfiles (id) on delete set null,
  revisado_en   timestamptz,
  creado_en     timestamptz not null default now(),

  constraint registros_nombre_valido check (length(btrim(nombre)) between 3 and 160),
  constraint registros_revision_coherente check (
    (estado = 'pendiente' and revisado_en is null)
    or (estado <> 'pendiente' and revisado_en is not null)
  )
);

comment on table public.registros is
  'Cuentas creadas por la propia persona. Quedan pendientes hasta que un admin de su empresa las asigna.';

create index registros_empresa_estado_idx on public.registros (empresa_id, estado, creado_en desc);

-- Al crear la cuenta en Auth con user_metadata.empresa_codigo y sin
-- app_metadata (registro propio, no invitación), se crea la solicitud.
create or replace function private.registrar_colaborador()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_empresa uuid;
  v_nombre  text;
begin
  if coalesce(new.raw_app_meta_data ->> 'empresa_id', '') <> '' then
    return new;
  end if;

  select e.id into v_empresa
  from public.empresas e
  where e.codigo = btrim(new.raw_user_meta_data ->> 'empresa_codigo')
    and e.activa;

  if v_empresa is null then
    return new;
  end if;

  v_nombre := coalesce(
    nullif(btrim(new.raw_user_meta_data ->> 'nombre_completo'), ''),
    split_part(new.email, '@', 1)
  );

  insert into public.registros (id, empresa_id, email, nombre, telefono)
  values (
    new.id, v_empresa, new.email, left(v_nombre, 160),
    nullif(left(btrim(coalesce(new.raw_user_meta_data ->> 'telefono', '')), 30), '')
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

comment on function private.registrar_colaborador() is
  'Crea la solicitud de registro cuando alguien se registra con el código de su empresa.';

revoke all on function private.registrar_colaborador() from public;

create trigger on_auth_user_registro
after insert on auth.users
for each row execute function private.registrar_colaborador();

alter table public.registros enable row level security;

create policy registros_select_propio_o_admin
  on public.registros
  for select
  to authenticated
  using (
    id = (select auth.uid())
    or (
      empresa_id = (select private.current_empresa_id())
      and (select private.es_admin())
      and (select private.perfil_propio_activo())
    )
  );

comment on policy registros_select_propio_o_admin on public.registros is
  'La persona ve su solicitud; los admins activos de la empresa ven las de su empresa.';

revoke all on table public.registros from anon, authenticated;
grant select on table public.registros to authenticated;
grant select, insert, update, delete on table public.registros to service_role;

-- Aprobar escribe app_metadata en auth.users; el trigger de 0004/0018
-- materializa el perfil. Un admin solo asigna centros de su subárbol y solo
-- crea empleados: no puede dar el rol admin desde aquí.
create or replace function public.aprobar_registro(
  p_registro uuid,
  p_centro uuid,
  p_puesto uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_registro public.registros%rowtype;
begin
  if not (private.es_admin() and private.perfil_propio_activo()) then
    raise exception 'Solo un administrador activo aprueba registros' using errcode = '42501';
  end if;

  select * into v_registro
  from public.registros
  where id = p_registro
    and empresa_id = private.current_empresa_id()
  for update;

  if not found then
    raise exception 'Registro no encontrado' using errcode = 'P0002';
  end if;
  if v_registro.estado <> 'pendiente' then
    raise exception 'El registro ya fue revisado' using errcode = '23514';
  end if;
  if not private.centro_en_alcance(p_centro) then
    raise exception 'El centro de costo no está en tu alcance' using errcode = '42501';
  end if;
  if p_puesto is not null and not exists (
    select 1 from public.puestos
    where id = p_puesto and empresa_id = v_registro.empresa_id and activo
  ) then
    raise exception 'Puesto no válido' using errcode = '23503';
  end if;

  update auth.users
  set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || jsonb_strip_nulls(
        jsonb_build_object(
          'empresa_id', v_registro.empresa_id,
          'centro_costo_id', p_centro,
          'rol', 'empleado',
          'puesto_id', p_puesto
        )
      ),
      raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
        || jsonb_build_object('nombre_completo', v_registro.nombre)
  where id = p_registro;

  update public.registros
  set estado = 'aprobado', revisado_por = auth.uid(), revisado_en = now()
  where id = p_registro;
end;
$$;

comment on function public.aprobar_registro(uuid, uuid, uuid) is
  'El admin asigna centro de su subárbol y puesto; la cuenta queda como empleado.';

create or replace function public.rechazar_registro(p_registro uuid, p_motivo text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (private.es_admin() and private.perfil_propio_activo()) then
    raise exception 'Solo un administrador activo rechaza registros' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_motivo, ''))) < 5 then
    raise exception 'Escribe el motivo del rechazo' using errcode = '23514';
  end if;

  update public.registros
  set estado = 'rechazado', motivo = btrim(p_motivo),
      revisado_por = auth.uid(), revisado_en = now()
  where id = p_registro
    and empresa_id = private.current_empresa_id()
    and estado = 'pendiente';

  if not found then
    raise exception 'Registro no encontrado o ya revisado' using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function public.aprobar_registro(uuid, uuid, uuid) from public, anon;
revoke all on function public.rechazar_registro(uuid, text) from public, anon;
grant execute on function public.aprobar_registro(uuid, uuid, uuid) to authenticated;
grant execute on function public.rechazar_registro(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 2. Incidencias
-- -----------------------------------------------------------------------------
create type public.tipo_incidencia as enum (
  'llegada_tarde', 'salida_temprana', 'parque_distinto', 'precision_baja'
);
create type public.severidad_incidencia as enum ('baja', 'media', 'alta');
create type public.estado_incidencia as enum ('abierta', 'resuelta', 'descartada');

create table public.incidencias (
  id            uuid primary key default gen_random_uuid(),
  empresa_id    uuid not null references public.empresas (id) on delete cascade,
  jornada_id    uuid not null references public.jornadas (id) on delete cascade,
  -- RESTRICT como jornadas y solicitudes (0012): la baja se hace desactivando
  -- el perfil y la incidencia queda como historial.
  empleado_id   uuid not null references public.perfiles (id) on delete restrict,
  tipo          public.tipo_incidencia not null,
  severidad     public.severidad_incidencia not null default 'media',
  descripcion   text not null,
  estado        public.estado_incidencia not null default 'abierta',
  resolucion    text,
  resuelto_por  uuid references public.perfiles (id) on delete set null,
  resuelto_en   timestamptz,
  creado_en     timestamptz not null default now(),

  constraint incidencias_jornada_tipo_key unique (jornada_id, tipo),
  constraint incidencias_resolucion_coherente check (
    (estado = 'abierta' and resuelto_en is null and resolucion is null)
    or (estado <> 'abierta' and resuelto_en is not null and length(btrim(resolucion)) >= 5)
  )
);

comment on table public.incidencias is
  'Novedades detectadas al marcar. Las crea la base de datos; el admin del subárbol las cierra.';

create index incidencias_empresa_estado_idx on public.incidencias (empresa_id, estado, creado_en desc);

-- Umbral de precisión: por encima de 50 m el marcaje vale (la geocerca
-- tolera hasta 100 m) pero conviene revisarlo.
create or replace function private.jornadas_detectar_incidencias()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tz        text;
  v_fecha     date;
  v_horario   public.horarios%rowtype;
  v_entrada   timestamptz;
  v_salida    timestamptz;
  v_minutos   int;
begin
  select e.zona_horaria into v_tz from public.empresas e where e.id = new.empresa_id;
  v_fecha := (new.entrada_en at time zone v_tz)::date;

  select * into v_horario
  from public.horarios h
  where h.empleado_id = new.empleado_id
    and h.dia_semana = extract(isodow from v_fecha);

  if tg_op = 'INSERT' then
    if new.entrada_precision_metros > 50 then
      insert into public.incidencias (empresa_id, jornada_id, empleado_id, tipo, severidad, descripcion)
      values (new.empresa_id, new.id, new.empleado_id, 'precision_baja', 'baja',
              format('Entrada con precisión GPS de %s m.', round(new.entrada_precision_metros)))
      on conflict do nothing;
    end if;

    if v_horario.id is not null then
      v_entrada := (v_fecha + v_horario.hora_entrada) at time zone v_tz;
      v_minutos := floor(extract(epoch from (new.entrada_en - v_entrada)) / 60);
      if v_minutos > v_horario.tolerancia_minutos then
        insert into public.incidencias (empresa_id, jornada_id, empleado_id, tipo, severidad, descripcion)
        values (new.empresa_id, new.id, new.empleado_id, 'llegada_tarde',
                case when v_minutos > 60 then 'alta'::public.severidad_incidencia
                     when v_minutos > 20 then 'media'::public.severidad_incidencia
                     else 'baja'::public.severidad_incidencia end,
                format('Llegó %s min tarde (entrada programada %s).', v_minutos,
                       to_char(v_horario.hora_entrada, 'HH24:MI')))
        on conflict do nothing;
      end if;

      if v_horario.parque_id is not null and v_horario.parque_id <> new.parque_id then
        insert into public.incidencias (empresa_id, jornada_id, empleado_id, tipo, severidad, descripcion)
        values (new.empresa_id, new.id, new.empleado_id, 'parque_distinto', 'media',
                'Marcó en un parque distinto al programado para ese día.')
        on conflict do nothing;
      end if;
    end if;
  elsif old.salida_en is null and new.salida_en is not null then
    if coalesce(new.salida_precision_metros, 0) > 50 then
      insert into public.incidencias (empresa_id, jornada_id, empleado_id, tipo, severidad, descripcion)
      values (new.empresa_id, new.id, new.empleado_id, 'precision_baja', 'baja',
              format('Salida con precisión GPS de %s m.', round(new.salida_precision_metros)))
      on conflict do nothing;
    end if;

    if v_horario.id is not null then
      v_salida := (v_fecha + v_horario.hora_salida
        + case when v_horario.hora_salida < v_horario.hora_entrada then interval '1 day' else interval '0' end
      ) at time zone v_tz;
      v_minutos := floor(extract(epoch from (v_salida - new.salida_en)) / 60);
      if v_minutos > v_horario.tolerancia_minutos then
        insert into public.incidencias (empresa_id, jornada_id, empleado_id, tipo, severidad, descripcion)
        values (new.empresa_id, new.id, new.empleado_id, 'salida_temprana',
                case when v_minutos > 60 then 'alta'::public.severidad_incidencia else 'media'::public.severidad_incidencia end,
                format('Salió %s min antes de lo programado (%s).', v_minutos,
                       to_char(v_horario.hora_salida, 'HH24:MI')))
        on conflict do nothing;
      end if;
    end if;
  end if;

  return null;
end;
$$;

comment on function private.jornadas_detectar_incidencias() is
  'Crea incidencias al abrir o cerrar una jornada comparándola con el horario del día.';

revoke all on function private.jornadas_detectar_incidencias() from public;

create trigger jornadas_detectar_incidencias
after insert or update of salida_en on public.jornadas
for each row execute function private.jornadas_detectar_incidencias();

alter table public.incidencias enable row level security;

create policy incidencias_select_propia_o_equipo
  on public.incidencias
  for select
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and (
      empleado_id = (select auth.uid())
      or (
        (select private.perfil_propio_activo())
        and private.perfil_en_alcance(empleado_id)
      )
    )
  );

create policy incidencias_resolver_admin
  on public.incidencias
  for update
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and estado = 'abierta'
    and (select private.perfil_propio_activo())
    and private.perfil_en_alcance(empleado_id)
    and empleado_id <> (select auth.uid())
  )
  with check (
    empresa_id = (select private.current_empresa_id())
    and estado in ('resuelta', 'descartada')
    and resuelto_por = (select auth.uid())
    and private.perfil_en_alcance(empleado_id)
    and empleado_id <> (select auth.uid())
  );

comment on policy incidencias_select_propia_o_equipo on public.incidencias is
  'El empleado ve sus incidencias; un admin activo, las de su subárbol.';
comment on policy incidencias_resolver_admin on public.incidencias is
  'Un admin activo cierra incidencias abiertas de su equipo, nunca las propias.';

create or replace function private.incidencias_firmar()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.estado is distinct from old.estado then
    new.resuelto_por := auth.uid();
    new.resuelto_en := now();
  end if;
  return new;
end;
$$;

revoke all on function private.incidencias_firmar() from public;

create trigger incidencias_firmar
before update on public.incidencias
for each row execute function private.incidencias_firmar();

revoke all on table public.incidencias from anon, authenticated;
grant select on table public.incidencias to authenticated;
grant update (estado, resolucion) on table public.incidencias to authenticated;
grant select, insert, update, delete on table public.incidencias to service_role;

-- -----------------------------------------------------------------------------
-- 3. Ajustes de jornada
-- -----------------------------------------------------------------------------
create table public.ajustes_jornada (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas (id) on delete cascade,
  jornada_id       uuid not null references public.jornadas (id) on delete cascade,
  entrada_anterior timestamptz not null,
  salida_anterior  timestamptz not null,
  entrada_nueva    timestamptz not null,
  salida_nueva     timestamptz not null,
  motivo           text not null,
  creado_por       uuid references public.perfiles (id) on delete set null,
  creado_en        timestamptz not null default now(),

  constraint ajustes_motivo_valido check (length(btrim(motivo)) between 10 and 500)
);

comment on table public.ajustes_jornada is
  'Historial de correcciones de jornadas hechas por un admin. No se edita ni se borra.';

create index ajustes_jornada_idx on public.ajustes_jornada (jornada_id, creado_en desc);

alter table public.ajustes_jornada enable row level security;

create policy ajustes_select_propio_o_equipo
  on public.ajustes_jornada
  for select
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and exists (
      select 1 from public.jornadas j
      where j.id = jornada_id
        and (j.empleado_id = (select auth.uid()) or private.perfil_en_alcance(j.empleado_id))
    )
  );

revoke all on table public.ajustes_jornada from anon, authenticated;
grant select on table public.ajustes_jornada to authenticated;
grant select, insert, update, delete on table public.ajustes_jornada to service_role;

-- Solo jornadas cerradas: el trigger de cierre (0007) cerraría una abierta.
create or replace function public.ajustar_jornada(
  p_jornada uuid,
  p_entrada timestamptz,
  p_salida timestamptz,
  p_motivo text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_jornada public.jornadas%rowtype;
begin
  select * into v_jornada
  from public.jornadas
  where id = p_jornada
    and empresa_id = private.current_empresa_id()
  for update;

  if not found
     or not private.perfil_propio_activo()
     or not private.perfil_en_alcance(v_jornada.empleado_id)
     or v_jornada.empleado_id = auth.uid() then
    raise exception 'No puedes ajustar esta jornada' using errcode = '42501';
  end if;
  if v_jornada.salida_en is null then
    raise exception 'Solo se ajustan jornadas cerradas' using errcode = '23514';
  end if;
  if length(btrim(coalesce(p_motivo, ''))) < 10 then
    raise exception 'Explica el motivo del ajuste (mínimo 10 caracteres)' using errcode = '23514';
  end if;

  insert into public.ajustes_jornada (
    empresa_id, jornada_id, entrada_anterior, salida_anterior,
    entrada_nueva, salida_nueva, motivo, creado_por
  ) values (
    v_jornada.empresa_id, v_jornada.id, v_jornada.entrada_en, v_jornada.salida_en,
    p_entrada, p_salida, btrim(p_motivo), auth.uid()
  );

  -- Las restricciones de la tabla validan rango y duración máxima.
  update public.jornadas
  set entrada_en = p_entrada, salida_en = p_salida
  where id = p_jornada;
end;
$$;

comment on function public.ajustar_jornada(uuid, timestamptz, timestamptz, text) is
  'El admin del subárbol corrige una jornada cerrada de su equipo; deja el ajuste como evidencia.';

revoke all on function public.ajustar_jornada(uuid, timestamptz, timestamptz, text) from public, anon;
grant execute on function public.ajustar_jornada(uuid, timestamptz, timestamptz, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 4. Realtime para la bandeja del admin
-- -----------------------------------------------------------------------------
alter table public.incidencias replica identity full;
alter table public.registros replica identity full;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.incidencias, public.registros;
  end if;
end;
$$;
