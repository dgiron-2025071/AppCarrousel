-- =============================================================================
-- Carrousel — Núcleo backend
-- MT-01 / Archivo 13: suspensión efectiva de empresas inactivas
-- Fecha: 2026-11-11
--
-- Problema:
--   `public.empresas.activa` existía desde 0002 pero ninguna política ni helper
--   la consultaba. Desactivar una empresa no cortaba el acceso: sus usuarios
--   seguían leyendo centros, parques, jornadas y solicitudes, y un admin podía
--   seguir gestionando el tenant hasta que su JWT expirara.
--
-- Decisión:
--   `private.current_empresa_id()` devuelve NULL si la empresa del JWT está
--   inactiva. Como todas las políticas y helpers derivan el tenant de ese
--   valor, la suspensión es inmediata y fail-closed para lectura y escritura.
--   El perfil propio se conserva visible por su política `id = auth.uid()`,
--   para que la app pueda mostrar la cuenta sin exponer datos del tenant.
--
--   La función pasa a SECURITY DEFINER para consultar `empresas` sin recursión
--   de RLS; no recibe parámetros y solo lee el claim del JWT y la fila de la
--   empresa. `service_role` sigue administrando la reactivación.
--
-- Depende de 0001 (current_empresa_id, safe_uuid) y 0002 (empresas y RLS).
--
-- Ejecución local: supabase db reset
-- Nota: el CLI de Supabase aplica cada migración dentro de una transacción.
-- No se incluye BEGIN/COMMIT explícito para evitar transacciones anidadas.
-- =============================================================================

create or replace function private.current_empresa_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select e.id
  from public.empresas e
  where e.id = private.safe_uuid(
    (auth.jwt() -> 'app_metadata') ->> 'empresa_id'
  )
    and e.activa;
$$;

comment on function private.current_empresa_id() is
  'Empresa activa del JWT (app_metadata.empresa_id). NULL si el claim falta, es inválido o la empresa está inactiva. Fail-closed.';

revoke all on function private.current_empresa_id() from public;
grant execute on function private.current_empresa_id()
  to authenticated, service_role;

comment on column public.empresas.activa is
  'Una empresa inactiva pierde de inmediato el acceso a su tenant: current_empresa_id() devuelve NULL y todas las políticas fallan cerradas. service_role puede reactivarla.';
