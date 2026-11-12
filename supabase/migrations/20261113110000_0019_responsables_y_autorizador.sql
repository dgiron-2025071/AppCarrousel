-- =============================================================================
-- Carrousel — Propuesta de integración con la operación actual
-- Archivo 19: jefe responsable por centro y persona que autoriza
-- Fecha: 2026-11-11
--
-- Hoy el formulario de horas extras pide escribir a mano "Persona que
-- autoriza". Aquí se deriva de la jerarquía, como en control-jornadas (el
-- personal de un área toma automáticamente al jefe configurado):
--
--   1. centros_costo.responsable_id    — jefe del centro (opcional).
--   2. private.autorizador_para()      — jefe más cercano subiendo la jerarquía.
--   3. solicitudes.autorizador_*       — se fija al crear la solicitud.
--   4. public.mi_autorizador()         — el empleado ve quién lo autorizará.
--
-- No cambia quién puede aprobar: sigue siendo cualquier admin activo del
-- subárbol (0006/0007). El autorizador indica a quién le corresponde.
--
-- Depende de 0002, 0004, 0006, 0007 y 0018.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Jefe responsable del centro
-- -----------------------------------------------------------------------------
alter table public.centros_costo
  add column responsable_id uuid references public.perfiles (id) on delete set null;

comment on column public.centros_costo.responsable_id is
  'Jefe del centro. Debe ser admin de la misma empresa asignado al centro o a un ancestro, para que su RLS cubra el subárbol. Lo asigna service_role.';

create index centros_costo_responsable_idx on public.centros_costo (responsable_id);

create or replace function private.centros_costo_validar_responsable()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.responsable_id is null then
    return new;
  end if;

  if not exists (
    select 1
    from public.perfiles p
    where p.id = new.responsable_id
      and p.empresa_id = new.empresa_id
      and p.rol = 'admin'
      and (p.centro_costo_id = new.id or p.centro_costo_id = any (new.ruta))
  ) then
    raise exception 'El responsable debe ser un admin de la empresa asignado al centro o a un ancestro'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

comment on function private.centros_costo_validar_responsable() is
  'Garantiza que el jefe responsable tenga alcance RLS sobre el centro que dirige.';

revoke all on function private.centros_costo_validar_responsable() from public;

-- Se ejecuta después de centros_costo_set_ruta (orden alfabético de triggers
-- BEFORE), así que new.ruta ya está calculada.
create trigger centros_costo_validar_responsable
before insert or update of responsable_id, padre_id on public.centros_costo
for each row execute function private.centros_costo_validar_responsable();

-- -----------------------------------------------------------------------------
-- 2. Autorizador de un empleado
-- -----------------------------------------------------------------------------
-- Recorre desde el centro del empleado hacia la raíz. En cada nivel prefiere el
-- responsable configurado; si no hay, toma un admin activo asignado a ese
-- centro. Nunca devuelve al propio empleado. NULL si nadie lo cubre.
create or replace function private.autorizador_para(p_empleado_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  with emp as (
    select c.id as centro_id, c.ruta
    from public.perfiles p
    join public.centros_costo c on c.id = p.centro_costo_id
    where p.id = p_empleado_id
  ),
  cadena as (
    select e.centro_id, 0 as nivel
    from emp e
    union all
    select r.centro_id, cardinality(e.ruta) - r.pos + 1
    from emp e
    cross join lateral unnest(e.ruta) with ordinality as r(centro_id, pos)
  ),
  candidatos as (
    select cad.nivel, 0 as prioridad, resp.id, resp.nombre_completo
    from cadena cad
    join public.centros_costo c on c.id = cad.centro_id
    join public.perfiles resp on resp.id = c.responsable_id
    where resp.activo
      and resp.rol = 'admin'
      and resp.id <> p_empleado_id
    union all
    select cad.nivel, 1 as prioridad, a.id, a.nombre_completo
    from cadena cad
    join public.perfiles a on a.centro_costo_id = cad.centro_id
    where a.activo
      and a.rol = 'admin'
      and a.id <> p_empleado_id
  )
  select id
  from candidatos
  order by nivel, prioridad, nombre_completo, id
  limit 1;
$$;

comment on function private.autorizador_para(uuid) is
  'Jefe más cercano que autoriza al empleado: responsable del centro o admin activo, subiendo por la jerarquía.';

revoke all on function private.autorizador_para(uuid) from public;

-- -----------------------------------------------------------------------------
-- 3. Autorizador en la solicitud
-- -----------------------------------------------------------------------------
-- Se guarda id y nombre: el nombre queda como evidencia aunque el jefe cambie
-- o se borre su perfil, igual que el texto del formulario actual.
alter table public.solicitudes_horas_extras
  add column autorizador_id uuid references public.perfiles (id) on delete set null,
  add column autorizador_nombre text;

comment on column public.solicitudes_horas_extras.autorizador_id is
  'Jefe al que le corresponde autorizar, calculado al crear la solicitud. El cliente no lo escribe.';
comment on column public.solicitudes_horas_extras.autorizador_nombre is
  'Nombre del autorizador al momento de la solicitud (evidencia histórica).';

create or replace function private.solicitudes_set_autorizador()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.autorizador_id := private.autorizador_para(new.empleado_id);
  new.autorizador_nombre := (
    select p.nombre_completo::text
    from public.perfiles p
    where p.id = new.autorizador_id
  );
  return new;
end;
$$;

comment on function private.solicitudes_set_autorizador() is
  'Fija el autorizador de la solicitud desde la jerarquía; ignora lo que envíe el cliente.';

revoke all on function private.solicitudes_set_autorizador() from public;

create trigger solicitudes_set_autorizador
before insert on public.solicitudes_horas_extras
for each row execute function private.solicitudes_set_autorizador();

-- Solicitudes existentes: se completa el autorizador sin tocar su estado.
update public.solicitudes_horas_extras s
set autorizador_id = private.autorizador_para(s.empleado_id),
    autorizador_nombre = (
      select p.nombre_completo::text
      from public.perfiles p
      where p.id = private.autorizador_para(s.empleado_id)
    )
where s.autorizador_id is null;

-- -----------------------------------------------------------------------------
-- 4. El empleado consulta quién lo autoriza
-- -----------------------------------------------------------------------------
-- RLS no deja al empleado leer otros perfiles; esta función expone solo el
-- nombre y el puesto de su propio autorizador.
create or replace function public.mi_autorizador()
returns table (id uuid, nombre_completo text, puesto text)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.nombre_completo::text, pu.nombre::text
  from public.perfiles p
  left join public.puestos pu on pu.id = p.puesto_id
  where p.id = private.autorizador_para(auth.uid())
    and auth.uid() is not null;
$$;

comment on function public.mi_autorizador() is
  'Nombre y puesto del jefe que autoriza las solicitudes del usuario actual.';

revoke all on function public.mi_autorizador() from public, anon;
grant execute on function public.mi_autorizador() to authenticated;
