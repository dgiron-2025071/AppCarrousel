-- =============================================================================
-- Carrousel — Núcleo backend
-- MT-01 / Archivo 07: endurecimiento operativo
-- Fecha: 2026-11-09
--
-- Crea/ajusta:
--   1. Cierre de jornada tolerante a un parque desactivado.
--      Un admin puede desactivar un parque mientras un empleado tiene la
--      jornada abierta. Ese empleado debe poder cerrarla para no quedar con
--      una jornada abierta permanente.
--   2. Marcaje restringido al subárbol del empleado.
--      El empleado solo ve los parques de su subárbol; la escritura debe
--      exigir el mismo alcance y no permitir referenciar un parque hermano
--      que ni siquiera puede leer.
--   3. Perfiles inactivos sin escritura.
--      public.perfiles.activo ya existía pero no se aplicaba. Un perfil
--      inactivo no abre jornadas, no crea solicitudes y un admin inactivo no
--      aprueba ni gestiona centros/parques/empresa.
--   4. Precisión GPS no negativa.
--
-- Depende de 0002 (centro_en_alcance), 0003 (parques), 0004 (perfiles) y
-- 0005 (en_geocerca, jornadas).
--
-- Ejecución local: supabase db reset
-- Nota: el CLI de Supabase aplica cada migración dentro de una transacción.
-- No se incluye BEGIN/COMMIT explícito para evitar transacciones anidadas.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Geocerca con control explícito de parque activo
-- -----------------------------------------------------------------------------
-- La entrada exige un parque activo; el cierre no, para no dejar jornadas
-- abiertas si el parque se desactiva durante el turno.
create or replace function private.en_geocerca_parque(
  p_parque_id uuid,
  p_lat double precision,
  p_lon double precision,
  p_precision_metros double precision,
  p_requiere_activo boolean
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select private.distancia_metros(
               p_lat, p_lon, pa.latitud, pa.longitud
             ) <= pa.radio_metros + least(coalesce(p_precision_metros, 0), 100)
      from public.parques pa
      where pa.id = p_parque_id
        and pa.empresa_id = private.current_empresa_id()
        and (not p_requiere_activo or pa.activo)
    ),
    false
  );
$$;

comment on function private.en_geocerca_parque(uuid, double precision, double precision, double precision, boolean) is
  'Valida un punto contra un parque de la empresa del JWT. p_requiere_activo=false permite cerrar una jornada aunque el parque se haya desactivado. Fail-closed.';

-- La firma pública se conserva; solo cambia para delegar en el helper.
create or replace function private.en_geocerca(
  p_parque_id uuid,
  p_lat double precision,
  p_lon double precision,
  p_precision_metros double precision default 0
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.en_geocerca_parque(
    p_parque_id, p_lat, p_lon, p_precision_metros, true
  );
$$;

-- El cierre usa la geocerca sin exigir que el parque siga activo.
create or replace function private.jornadas_cerrar()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    return new;
  end if;

  new.salida_en := coalesce(new.salida_en, clock_timestamp());
  new.salida_dentro_geocerca := private.en_geocerca_parque(
    new.parque_id, new.salida_lat, new.salida_lon,
    new.salida_precision_metros, false
  );

  if new.salida_dentro_geocerca is not true then
    raise exception 'La salida está fuera de la geocerca del parque'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

comment on function private.jornadas_cerrar() is
  'Cierra la jornada, fija salida_en y valida la geocerca de salida. No exige que el parque siga activo.';

-- -----------------------------------------------------------------------------
-- 2. Alcance de parque y perfil propio activo
-- -----------------------------------------------------------------------------
-- Mismo alcance que la política de lectura de parques: el parque debe estar
-- en la empresa y en el subárbol del usuario.
create or replace function private.parque_en_alcance(p_parque_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    exists (
      select 1
      from public.parques pa
      where pa.id = p_parque_id
        and pa.empresa_id = private.current_empresa_id()
        and private.centro_en_alcance(pa.centro_costo_id)
    ),
    false
  );
$$;

comment on function private.parque_en_alcance(uuid) is
  'TRUE si el parque pertenece a la empresa del JWT y a un centro del subárbol del usuario. Fail-closed.';

-- Un perfil desactivado conserva su historial y puede cerrar una jornada
-- abierta, pero no inicia trabajo nuevo.
create or replace function private.perfil_propio_activo()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    exists (
      select 1
      from public.perfiles p
      where p.id = auth.uid()
        and p.activo
    ),
    false
  );
$$;

comment on function private.perfil_propio_activo() is
  'TRUE si el usuario del JWT tiene perfil y está activo. Fail-closed.';

revoke all on function private.en_geocerca_parque(uuid, double precision, double precision, double precision, boolean) from public;
revoke all on function private.parque_en_alcance(uuid) from public;
revoke all on function private.perfil_propio_activo() from public;

grant execute on function private.en_geocerca_parque(uuid, double precision, double precision, double precision, boolean)
  to authenticated, service_role;
grant execute on function private.parque_en_alcance(uuid)
  to authenticated, service_role;
grant execute on function private.perfil_propio_activo()
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 3. Jornadas: solo parques del subárbol y perfiles activos
-- -----------------------------------------------------------------------------
drop policy jornadas_insert_propia on public.jornadas;

create policy jornadas_insert_propia
  on public.jornadas
  for insert
  to authenticated
  with check (
    empresa_id = (select private.current_empresa_id())
    and empleado_id = (select auth.uid())
    and (select private.perfil_propio_activo())
    and salida_en is null
    and private.parque_en_alcance(parque_id)
    and private.en_geocerca(
      parque_id, entrada_lat, entrada_lon, entrada_precision_metros
    )
  );

comment on policy jornadas_insert_propia on public.jornadas is
  'Solo el propio empleado activo abre una jornada, en un parque de su subárbol y con GPS dentro de la geocerca.';

-- -----------------------------------------------------------------------------
-- 4. Solicitudes: solo perfiles activos
-- -----------------------------------------------------------------------------
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
  );

comment on policy solicitudes_insert_propia on public.solicitudes_horas_extras is
  'Solo el propio especialista activo crea solicitudes pendientes para un centro de su empresa.';

drop policy solicitudes_update_admin on public.solicitudes_horas_extras;

create policy solicitudes_update_admin
  on public.solicitudes_horas_extras
  for update
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_admin())
    and (select private.perfil_propio_activo())
    and private.perfil_en_alcance(empleado_id)
    and empleado_id <> (select auth.uid())
    and estado = 'pendiente'
  )
  with check (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_admin())
    and (select private.perfil_propio_activo())
    and private.perfil_en_alcance(empleado_id)
    and empleado_id <> (select auth.uid())
    and estado in ('aprobada', 'rechazada')
    and revisado_por = (select auth.uid())
    and revisado_en is not null
  );

comment on policy solicitudes_update_admin on public.solicitudes_horas_extras is
  'Solo un admin activo aprueba o rechaza solicitudes pendientes de su subárbol. No puede revisar las propias.';

-- -----------------------------------------------------------------------------
-- 5. Administración: un admin inactivo deja de escribir
-- -----------------------------------------------------------------------------
drop policy empresas_update_admin on public.empresas;

create policy empresas_update_admin
  on public.empresas
  for update
  to authenticated
  using (
    id = (select private.current_empresa_id())
    and (select private.es_admin())
    and (select private.perfil_propio_activo())
  )
  with check (
    id = (select private.current_empresa_id())
    and (select private.es_admin())
    and (select private.perfil_propio_activo())
  );

drop policy centros_costo_insert_admin on public.centros_costo;
drop policy centros_costo_update_admin on public.centros_costo;
drop policy centros_costo_delete_admin on public.centros_costo;

create policy centros_costo_insert_admin
  on public.centros_costo
  for insert
  to authenticated
  with check (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_admin())
    and (select private.perfil_propio_activo())
    and padre_id is not null
    and private.centro_en_alcance(padre_id)
  );

create policy centros_costo_update_admin
  on public.centros_costo
  for update
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_admin())
    and (select private.perfil_propio_activo())
    and private.centro_en_alcance(id)
  )
  with check (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_admin())
    and (select private.perfil_propio_activo())
    and private.centro_en_alcance(id)
  );

create policy centros_costo_delete_admin
  on public.centros_costo
  for delete
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_admin())
    and (select private.perfil_propio_activo())
    and private.centro_en_alcance(id)
  );

drop policy parques_insert_admin on public.parques;
drop policy parques_update_admin on public.parques;
drop policy parques_delete_admin on public.parques;

create policy parques_insert_admin
  on public.parques
  for insert
  to authenticated
  with check (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_admin())
    and (select private.perfil_propio_activo())
    and private.centro_en_alcance(centro_costo_id)
  );

create policy parques_update_admin
  on public.parques
  for update
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_admin())
    and (select private.perfil_propio_activo())
    and private.centro_en_alcance(centro_costo_id)
  )
  with check (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_admin())
    and (select private.perfil_propio_activo())
    and private.centro_en_alcance(centro_costo_id)
  );

create policy parques_delete_admin
  on public.parques
  for delete
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_admin())
    and (select private.perfil_propio_activo())
    and private.centro_en_alcance(centro_costo_id)
  );

-- -----------------------------------------------------------------------------
-- 6. Precisión GPS no negativa
-- -----------------------------------------------------------------------------
alter table public.jornadas
  add constraint jornadas_entrada_precision_valida
    check (entrada_precision_metros >= 0),
  add constraint jornadas_salida_precision_valida
    check (salida_precision_metros is null or salida_precision_metros >= 0);
