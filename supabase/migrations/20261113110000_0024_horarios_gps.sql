-- =============================================================================
-- Carrousel — Núcleo backend
-- MT-02 / Archivo 24: horario por empleado, zona horaria y umbral de GPS
-- Fecha: 2026-11-13
--
-- Crea:
--   1. public.empresas.zona_horaria            — zona IANA de la empresa.
--   2. public.empresas.gps_precision_maxima_metros — umbral de GPS impreciso.
--   3. public.horarios                         — horario semanal por empleado.
--   4. private.fecha_local()                   — fecha en la zona de la empresa.
--   5. private.horario_del_dia()               — horario vigente para una fecha.
--   6. RLS y grants                            — el empleado ve el suyo; el admin
--      gestiona su subárbol.
--
-- Modelo:
--   `horarios` define una franja por día ISO (1 = lunes … 7 = domingo). Una
--   salida menor o igual a la entrada representa un turno que cruza medianoche.
--   La zona horaria de la empresa decide qué día local corresponde a un
--   instante; sin ella, las incidencias de llegada/salida serían ambiguas.
--
-- Depende de 0001 (auditoría), 0002 (empresas), 0004/0014 (perfiles) y
-- 0016 (unique (empresa_id, id) en perfiles).
--
-- Ejecución local: supabase db reset
-- Nota: el CLI de Supabase aplica cada migración dentro de una transacción.
-- No se incluye BEGIN/COMMIT explícito para evitar transacciones anidadas.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Configuración de la empresa
-- -----------------------------------------------------------------------------
alter table public.empresas
  add column zona_horaria text not null default 'America/Guatemala',
  add column gps_precision_maxima_metros integer not null default 100;

alter table public.empresas
  add constraint empresas_zona_horaria_valida
    check (length(btrim(zona_horaria)) between 1 and 64),
  add constraint empresas_gps_precision_valida
    check (gps_precision_maxima_metros between 10 and 1000);

comment on column public.empresas.zona_horaria is
  'Zona horaria IANA de la empresa. Se usa para convertir instantes a fechas y horas locales.';
comment on column public.empresas.gps_precision_maxima_metros is
  'Precisión GPS por encima de la cual una marcación se reporta como imprecisa.';

-- La zona debe existir en PostgreSQL. Se valida en AFTER para no depender de
-- una tabla del sistema desde el cliente.
create or replace function private.empresas_validar_zona_horaria()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from pg_catalog.pg_timezone_names z where z.name = new.zona_horaria
  ) then
    raise exception 'Zona horaria inválida: %', new.zona_horaria
      using errcode = '23514';
  end if;

  return new;
end;
$$;

comment on function private.empresas_validar_zona_horaria() is
  'Rechaza zonas horarias que PostgreSQL no reconoce.';

revoke all on function private.empresas_validar_zona_horaria() from public;

create trigger empresas_validar_zona_horaria
after insert or update of zona_horaria on public.empresas
for each row execute function private.empresas_validar_zona_horaria();

grant update (zona_horaria, gps_precision_maxima_metros)
  on table public.empresas to authenticated;

-- -----------------------------------------------------------------------------
-- 2. Horarios
-- -----------------------------------------------------------------------------
create table public.horarios (
  id                       uuid primary key default gen_random_uuid(),
  empresa_id               uuid not null references public.empresas (id) on delete restrict,
  empleado_id              uuid not null,
  dia_semana               smallint not null,
  hora_entrada             time not null,
  hora_salida              time not null,
  tolerancia_entrada_min   integer not null default 10,
  tolerancia_salida_min    integer not null default 10,
  activo                   boolean not null default true,
  creado_en                timestamptz not null default now(),
  actualizado_en           timestamptz not null default now(),
  actualizado_por          uuid references auth.users (id) on delete set null,

  constraint horarios_empleado_dia_key unique (empleado_id, dia_semana),
  constraint horarios_empleado_fk
    foreign key (empresa_id, empleado_id)
    references public.perfiles (empresa_id, id)
    on delete restrict,
  constraint horarios_dia_valido
    check (dia_semana between 1 and 7),
  constraint horarios_franja_distinta
    check (hora_entrada <> hora_salida),
  constraint horarios_tolerancia_entrada_valida
    check (tolerancia_entrada_min between 0 and 240),
  constraint horarios_tolerancia_salida_valida
    check (tolerancia_salida_min between 0 and 240)
);

comment on table public.horarios is
  'Horario semanal por empleado y día ISO. Una salida menor o igual a la entrada representa un turno nocturno.';
comment on column public.horarios.dia_semana is
  'Día ISO: 1 = lunes … 7 = domingo.';
comment on column public.horarios.hora_entrada is
  'Hora local de entrada según empresas.zona_horaria.';
comment on column public.horarios.hora_salida is
  'Hora local de salida según empresas.zona_horaria. Puede ser anterior a la entrada en turnos nocturnos.';

create index horarios_empresa_empleado_idx
  on public.horarios (empresa_id, empleado_id);

create trigger horarios_auditoria
before update on public.horarios
for each row execute function private.set_actualizado_en();

-- -----------------------------------------------------------------------------
-- 3. Conversión a fecha/hora local y horario vigente
-- -----------------------------------------------------------------------------
create or replace function private.fecha_local(
  p_empresa_id uuid,
  p_instante timestamptz
)
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select (p_instante at time zone e.zona_horaria)::date
  from public.empresas e
  where e.id = p_empresa_id;
$$;

comment on function private.fecha_local(uuid, timestamptz) is
  'Fecha local de un instante según la zona horaria de la empresa.';

create or replace function private.horario_del_dia(
  p_empleado_id uuid,
  p_fecha date
)
returns table (
  horario_id uuid,
  hora_entrada time,
  hora_salida time,
  tolerancia_entrada_min integer,
  tolerancia_salida_min integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    h.id,
    h.hora_entrada,
    h.hora_salida,
    h.tolerancia_entrada_min,
    h.tolerancia_salida_min
  from public.horarios h
  where h.empleado_id = p_empleado_id
    and h.activo
    and h.dia_semana = extract(isodow from p_fecha)::smallint
  limit 1;
$$;

comment on function private.horario_del_dia(uuid, date) is
  'Horario activo del empleado para una fecha local. Devuelve vacío si no tiene horario.';

revoke all on function private.fecha_local(uuid, timestamptz) from public;
revoke all on function private.horario_del_dia(uuid, date) from public;

grant execute on function private.fecha_local(uuid, timestamptz)
  to authenticated, service_role;
grant execute on function private.horario_del_dia(uuid, date)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 4. RLS: horarios
-- -----------------------------------------------------------------------------
alter table public.horarios enable row level security;

create policy horarios_select_propio_o_equipo
  on public.horarios
  for select
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and (
      empleado_id = (select auth.uid())
      or private.perfil_en_alcance(empleado_id)
    )
  );

create policy horarios_insert_admin
  on public.horarios
  for insert
  to authenticated
  with check (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_admin())
    and private.perfil_en_alcance(empleado_id)
  );

create policy horarios_update_admin
  on public.horarios
  for update
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_admin())
    and private.perfil_en_alcance(empleado_id)
  )
  with check (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_admin())
    and private.perfil_en_alcance(empleado_id)
  );

create policy horarios_delete_admin
  on public.horarios
  for delete
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_admin())
    and private.perfil_en_alcance(empleado_id)
  );

comment on policy horarios_select_propio_o_equipo on public.horarios is
  'El empleado ve su horario; el admin ve el de su subárbol.';
comment on policy horarios_insert_admin on public.horarios is
  'Solo un admin activo crea horarios para perfiles de su subárbol.';
comment on policy horarios_update_admin on public.horarios is
  'Solo un admin activo edita horarios de su subárbol.';
comment on policy horarios_delete_admin on public.horarios is
  'Solo un admin activo elimina horarios de su subárbol.';

-- -----------------------------------------------------------------------------
-- 5. Grants explícitos
-- -----------------------------------------------------------------------------
revoke all on table public.horarios from anon, authenticated;

grant select on table public.horarios to authenticated;
grant insert (
  empresa_id,
  empleado_id,
  dia_semana,
  hora_entrada,
  hora_salida,
  tolerancia_entrada_min,
  tolerancia_salida_min,
  activo
) on table public.horarios to authenticated;
grant update (
  dia_semana,
  hora_entrada,
  hora_salida,
  tolerancia_entrada_min,
  tolerancia_salida_min,
  activo
) on table public.horarios to authenticated;
grant delete on table public.horarios to authenticated;
