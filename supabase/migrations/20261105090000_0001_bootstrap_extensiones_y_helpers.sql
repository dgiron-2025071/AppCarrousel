-- =============================================================================
-- Empresa Carrousel — Núcleo backend
-- MT-01 / Archivo 01: bootstrap de extensiones, tipos y helpers de seguridad
-- Fecha: 2026-11-05
--
-- Esta migración NO crea tablas de negocio. Prepara la base para las
-- migraciones 0002-0004:
--   1. Extensiones necesarias.
--   2. Schema privado para funciones internas (no expuesto por PostgREST).
--   3. Tipo de dominio para roles de negocio.
--   4. Trigger reutilizable de auditoría.
--   5. Helpers de lectura de claims JWT con conversión segura (fail-closed).
--   6. Endurecimiento de privilegios por defecto.
--
-- Modelo de autorización:
--   El rol y el alcance viven en app_metadata del JWT, que SOLO puede escribir
--   el servidor (Edge Function con service_role) durante el aprovisionamiento
--   por invitación. El cliente nunca puede modificarlos.
--
-- Ejecución local: supabase db reset
-- Nota: el CLI de Supabase aplica cada migración dentro de una transacción.
-- No se incluye BEGIN/COMMIT explícito para evitar transacciones anidadas.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Extensiones
-- -----------------------------------------------------------------------------
create schema if not exists extensions;

-- gen_random_uuid() es nativo desde PostgreSQL 13. pgcrypto se conserva para
-- futuras funciones de hash y tokens de invitación.
create extension if not exists pgcrypto with schema extensions;
create extension if not exists citext   with schema extensions;

-- -----------------------------------------------------------------------------
-- 2. Schema privado
-- -----------------------------------------------------------------------------
create schema if not exists private;

revoke all on schema private from public;
revoke all on schema private from anon;
revoke all on schema private from authenticated;
grant usage on schema private to authenticated, service_role;

comment on schema private is
  'Funciones internas de RLS y utilidades. No expuesto por PostgREST.';

-- -----------------------------------------------------------------------------
-- 3. Tipos de dominio
-- -----------------------------------------------------------------------------
create type public.rol_usuario as enum ('empleado', 'gerente');

comment on type public.rol_usuario is
  'Roles de negocio. La administración se ejerce con service_role, no con un rol de aplicación.';

-- -----------------------------------------------------------------------------
-- 4. Auditoría
-- -----------------------------------------------------------------------------
create or replace function private.set_actualizado_en()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.actualizado_en := now();
  new.actualizado_por := coalesce(auth.uid(), new.actualizado_por);
  return new;
end;
$$;

comment on function private.set_actualizado_en() is
  'Actualiza actualizado_en y actualizado_por. Adjuntar como BEFORE UPDATE a tablas con ambas columnas.';

-- -----------------------------------------------------------------------------
-- 5. Helpers de claims JWT
-- -----------------------------------------------------------------------------
-- Conversión segura: un claim malformado no debe romper la consulta ni
-- convertirse en un privilegio. Devuelve NULL y la política falla cerrada.
create or replace function private.safe_uuid(p_value text)
returns uuid
language plpgsql
immutable
security invoker
set search_path = ''
as $$
begin
  if p_value is null or btrim(p_value) = '' then
    return null;
  end if;

  return p_value::uuid;
exception
  when invalid_text_representation then
    return null;
end;
$$;

comment on function private.safe_uuid(text) is
  'Convierte texto a uuid sin lanzar excepción. Devuelve NULL ante valores inválidos.';

create or replace function private.current_empresa_id()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select private.safe_uuid(
    (auth.jwt() -> 'app_metadata') ->> 'empresa_id'
  );
$$;

comment on function private.current_empresa_id() is
  'Empresa del JWT (app_metadata.empresa_id). NULL si el claim falta o es inválido.';

create or replace function private.current_centro_id()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select private.safe_uuid(
    (auth.jwt() -> 'app_metadata') ->> 'centro_costo_id'
  );
$$;

comment on function private.current_centro_id() is
  'Centro de costo del JWT (app_metadata.centro_costo_id). NULL si falta o es inválido.';

create or replace function private.current_rol()
returns public.rol_usuario
language sql
stable
security invoker
set search_path = ''
as $$
  select case (auth.jwt() -> 'app_metadata') ->> 'rol'
           when 'empleado' then 'empleado'::public.rol_usuario
           when 'gerente'  then 'gerente'::public.rol_usuario
           else null
         end;
$$;

comment on function private.current_rol() is
  'Rol de negocio del JWT (app_metadata.rol). Valores desconocidos devuelven NULL.';

create or replace function private.es_gerente()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(
    private.current_rol() = 'gerente'::public.rol_usuario,
    false
  );
$$;

comment on function private.es_gerente() is
  'TRUE solo si el JWT tiene app_metadata.rol = gerente. Fail-closed.';

-- -----------------------------------------------------------------------------
-- 6. Privilegios de ejecución
-- -----------------------------------------------------------------------------
revoke all on function private.set_actualizado_en()   from public;
revoke all on function private.safe_uuid(text)         from public;
revoke all on function private.current_empresa_id()    from public;
revoke all on function private.current_centro_id()     from public;
revoke all on function private.current_rol()           from public;
revoke all on function private.es_gerente()            from public;

grant execute on function private.set_actualizado_en() to authenticated, service_role;
grant execute on function private.safe_uuid(text)       to authenticated, service_role;
grant execute on function private.current_empresa_id()  to authenticated, service_role;
grant execute on function private.current_centro_id()   to authenticated, service_role;
grant execute on function private.current_rol()         to authenticated, service_role;
grant execute on function private.es_gerente()          to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 7. Endurecimiento de privilegios por defecto
-- -----------------------------------------------------------------------------
-- El schema public no debe permitir creación de objetos a roles de API.
revoke create on schema public from public, anon, authenticated;

-- Los objetos futuros en public nacen cerrados para los roles de API.
-- Cada migración otorga permisos explícitos sobre sus tablas y funciones.
alter default privileges in schema public revoke all on tables    from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke all on functions from public;
