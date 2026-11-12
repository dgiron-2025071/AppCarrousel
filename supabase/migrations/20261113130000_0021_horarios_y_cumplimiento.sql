-- =============================================================================
-- Carrousel — Propuesta de integración con la operación actual
-- Archivo 21: horario personalizado y horas extras detectadas por GPS
-- Fecha: 2026-11-11
--
-- Objetivo: que las horas extras salgan del marcaje con geocerca en lugar de
-- escribirse a mano.
--
--   1. empresas.zona_horaria          — define el "día" de cada marcaje.
--   2. public.horarios                — horario por empleado y día de semana,
--                                       editable por su admin.
--   3. public.cumplimiento_jornadas   — compara cada jornada con su horario:
--                                       llegada tarde y minutos extra.
--   4. solicitudes.jornada_id         — la solicitud queda respaldada por la
--                                       jornada GPS que la originó.
--
-- Depende de 0002–0007, 0019 y 0020.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Zona horaria de la empresa
-- -----------------------------------------------------------------------------
alter table public.empresas
  add column zona_horaria text not null default 'America/Guatemala';

comment on column public.empresas.zona_horaria is
  'Zona IANA con la que se calcula el día y la hora local de cada marcaje.';

create or replace function private.empresas_validar_zona()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = new.zona_horaria) then
    raise exception 'Zona horaria desconocida: %', new.zona_horaria
      using errcode = '22023';
  end if;
  return new;
end;
$$;

revoke all on function private.empresas_validar_zona() from public;

create trigger empresas_validar_zona
before insert or update of zona_horaria on public.empresas
for each row execute function private.empresas_validar_zona();

-- -----------------------------------------------------------------------------
-- 2. Horarios
-- -----------------------------------------------------------------------------
-- Un turno nocturno se expresa con salida menor que entrada (22:00 → 06:00).
create table public.horarios (
  id                 uuid primary key default gen_random_uuid(),
  empresa_id         uuid not null default private.current_empresa_id()
                       references public.empresas (id) on delete restrict,
  empleado_id        uuid not null references public.perfiles (id) on delete cascade,
  dia_semana         smallint not null,
  hora_entrada       time not null,
  hora_salida        time not null,
  parque_id          uuid,
  tolerancia_minutos smallint not null default 10,
  creado_en          timestamptz not null default now(),
  actualizado_en     timestamptz not null default now(),
  actualizado_por    uuid references auth.users (id) on delete set null,

  constraint horarios_empleado_dia_key unique (empleado_id, dia_semana),
  constraint horarios_dia_valido check (dia_semana between 1 and 7),
  constraint horarios_horas_distintas check (hora_salida <> hora_entrada),
  constraint horarios_tolerancia_valida check (tolerancia_minutos between 0 and 120),
  constraint horarios_parque_fk
    foreign key (empresa_id, parque_id)
    references public.parques (empresa_id, id)
    on delete set null (parque_id)
);

comment on table public.horarios is
  'Horario personalizado por empleado y día ISO (1 = lunes). Lo edita el admin de su subárbol.';
comment on column public.horarios.parque_id is
  'Parque donde debe marcar ese día. NULL = cualquier parque de su alcance.';
comment on column public.horarios.tolerancia_minutos is
  'Minutos de gracia antes de considerar la llegada tarde.';

create index horarios_empresa_empleado_idx on public.horarios (empresa_id, empleado_id);

create trigger horarios_auditoria
before update on public.horarios
for each row execute function private.set_actualizado_en();

alter table public.horarios enable row level security;

create policy horarios_select_propio_o_equipo
  on public.horarios
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

-- El admin activo edita el horario de su equipo, pero no el suyo: lo define
-- su propio jefe, igual que la aprobación de horas extras.
create policy horarios_escritura_admin
  on public.horarios
  for all
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and (select private.perfil_propio_activo())
    and private.perfil_en_alcance(empleado_id)
    and empleado_id <> (select auth.uid())
  )
  with check (
    empresa_id = (select private.current_empresa_id())
    and (select private.perfil_propio_activo())
    and private.perfil_en_alcance(empleado_id)
    and empleado_id <> (select auth.uid())
    and (parque_id is null or private.parque_en_alcance(parque_id))
  );

comment on policy horarios_select_propio_o_equipo on public.horarios is
  'El empleado ve su horario; un admin activo ve el de su subárbol.';
comment on policy horarios_escritura_admin on public.horarios is
  'Solo un admin activo crea, cambia o borra horarios de su subárbol, nunca el propio.';

revoke all on table public.horarios from anon, authenticated;
grant select, delete on table public.horarios to authenticated;
grant insert (
  empleado_id, dia_semana, hora_entrada, hora_salida, parque_id, tolerancia_minutos
) on table public.horarios to authenticated;
grant update (
  hora_entrada, hora_salida, parque_id, tolerancia_minutos
) on table public.horarios to authenticated;
grant select, insert, update, delete on table public.horarios to service_role;

-- La columna se crea antes que la vista de cumplimiento, que la consulta.
alter table public.solicitudes_horas_extras
  add column jornada_id uuid references public.jornadas (id) on delete set null;

comment on column public.solicitudes_horas_extras.jornada_id is
  'Jornada GPS que respalda la solicitud. Opcional; solo puede ser una jornada propia.';

-- -----------------------------------------------------------------------------
-- 3. Cumplimiento de cada jornada
-- -----------------------------------------------------------------------------
-- security_invoker: cada quien ve solo las jornadas que su RLS le permite.
create view public.cumplimiento_jornadas
with (security_invoker = true)
as
with base as (
  select
    j.id,
    j.empresa_id,
    j.empleado_id,
    j.parque_id,
    j.entrada_en,
    j.salida_en,
    j.entrada_dentro_geocerca,
    j.salida_dentro_geocerca,
    e.zona_horaria,
    (j.entrada_en at time zone e.zona_horaria)::date as fecha
  from public.jornadas j
  join public.empresas e on e.id = j.empresa_id
),
programada as (
  select
    b.*,
    h.id as horario_id,
    h.hora_entrada,
    h.hora_salida,
    h.tolerancia_minutos,
    h.parque_id as parque_programado_id,
    (b.fecha + h.hora_entrada) at time zone b.zona_horaria as entrada_programada,
    (b.fecha + h.hora_salida
      + case when h.hora_salida < h.hora_entrada then interval '1 day' else interval '0' end
    ) at time zone b.zona_horaria as salida_programada
  from base b
  left join public.horarios h
    on h.empleado_id = b.empleado_id
   and h.dia_semana = extract(isodow from b.fecha)
)
select
  p.id as jornada_id,
  p.empresa_id,
  p.empleado_id,
  p.parque_id,
  p.fecha,
  p.entrada_en,
  p.salida_en,
  p.entrada_dentro_geocerca,
  p.salida_dentro_geocerca,
  p.horario_id,
  p.hora_entrada,
  p.hora_salida,
  p.entrada_programada,
  p.salida_programada,
  case
    when p.horario_id is null then null
    else greatest(0, floor(extract(epoch from (p.entrada_en - p.entrada_programada)) / 60))::int
  end as minutos_tarde,
  coalesce(
    p.horario_id is not null
      and p.entrada_en > p.entrada_programada + make_interval(mins => p.tolerancia_minutos),
    false
  ) as llego_tarde,
  -- Solo cuenta el tiempo después de la salida programada y con salida dentro
  -- de la geocerca: el GPS respalda que siguió en el parque.
  case
    when p.horario_id is null then null
    when p.salida_en is null or not coalesce(p.salida_dentro_geocerca, false) then 0
    else greatest(0, floor(extract(epoch from (p.salida_en - greatest(p.salida_programada, p.entrada_en))) / 60))::int
  end as minutos_extra,
  (p.parque_programado_id is null or p.parque_programado_id = p.parque_id) as en_parque_programado,
  (
    select s.id
    from public.solicitudes_horas_extras s
    where s.jornada_id = p.id
      and s.estado in ('pendiente', 'aprobada')
    limit 1
  ) as solicitud_id
from programada p;

comment on view public.cumplimiento_jornadas is
  'Cada jornada contra el horario del día: tardanza y minutos extra respaldados por la geocerca. Respeta RLS.';

revoke all on table public.cumplimiento_jornadas from anon, authenticated;
grant select on table public.cumplimiento_jornadas to authenticated;

-- -----------------------------------------------------------------------------
-- 4. Solicitud respaldada por una jornada
-- -----------------------------------------------------------------------------
-- Una jornada respalda a lo sumo una solicitud viva.
create unique index solicitudes_jornada_viva_key
  on public.solicitudes_horas_extras (jornada_id)
  where jornada_id is not null and estado in ('pendiente', 'aprobada');

create or replace function private.jornada_propia(p_jornada_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    exists (
      select 1
      from public.jornadas j
      where j.id = p_jornada_id
        and j.empleado_id = auth.uid()
        and j.salida_en is not null
    ),
    false
  );
$$;

comment on function private.jornada_propia(uuid) is
  'TRUE si la jornada es del usuario del JWT y ya está cerrada. Fail-closed.';

revoke all on function private.jornada_propia(uuid) from public;
grant execute on function private.jornada_propia(uuid) to authenticated, service_role;

drop policy solicitudes_insert_propia on public.solicitudes_horas_extras;

create policy solicitudes_insert_propia
  on public.solicitudes_horas_extras
  for insert
  to authenticated
  with check (
    empresa_id = (select private.current_empresa_id())
    and empleado_id = (select auth.uid())
    and (select private.perfil_propio_activo())
    and estado = 'pendiente'
    and revisado_por is null
    and revisado_en is null
    and comentario_admin is null
    and private.centro_en_empresa(centro_costo_id)
    and (jornada_id is null or private.jornada_propia(jornada_id))
  );

comment on policy solicitudes_insert_propia on public.solicitudes_horas_extras is
  'Solo el propio especialista activo crea solicitudes pendientes para un centro de su empresa, opcionalmente respaldadas por una jornada propia cerrada.';

grant insert (jornada_id) on table public.solicitudes_horas_extras to authenticated;

-- -----------------------------------------------------------------------------
-- 5. Reporte: indica si la solicitud está respaldada por GPS
-- -----------------------------------------------------------------------------
-- CREATE OR REPLACE solo permite agregar columnas al final.
create or replace view public.reporte_horas_extras
with (security_invoker = true)
as
select
  s.id,
  s.empresa_id,
  s.empleado_id,
  pe.nombre_completo::text                                   as empleado,
  pu.nombre::text                                            as puesto,
  s.inicio,
  s.fin,
  round((extract(epoch from (s.fin - s.inicio)) / 3600.0)::numeric, 2)
                                                             as horas,
  s.justificacion                                            as actividad_realizada,
  c.codigo::text                                             as ceco_codigo,
  c.nombre::text                                             as ceco_nombre,
  s.autorizador_nombre                                       as persona_que_autoriza,
  s.estado,
  rv.nombre_completo::text                                   as revisado_por,
  s.revisado_en,
  s.comentario_admin,
  s.creado_en,
  s.jornada_id is not null                                   as respaldo_gps
from public.solicitudes_horas_extras s
join public.perfiles pe on pe.id = s.empleado_id
left join public.puestos pu on pu.id = pe.puesto_id
join public.centros_costo c on c.id = s.centro_costo_id
left join public.perfiles rv on rv.id = s.revisado_por;
