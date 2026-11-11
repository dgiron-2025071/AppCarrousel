-- =============================================================================
-- Carrousel — Núcleo backend
-- MT-01 / Archivo 14: revocación inmediata del rol de administrador
-- Fecha: 2026-11-11
--
-- Problema:
--   `private.es_admin()` confiaba únicamente en `app_metadata.rol` del JWT.
--   Al degradar a un administrador, el perfil se actualizaba de inmediato pero
--   su JWT seguía diciendo `admin` hasta que expirara (hasta una hora). En esa
--   ventana podía aprobar solicitudes y gestionar centros, parques y empresa.
--
-- Decisión:
--   `es_admin()` exige las dos condiciones: el JWT sigue diciendo `admin` y el
--   perfil materializado sigue siendo `admin`, está activo y pertenece a la
--   empresa activa del JWT. Una degradación o desactivación surte efecto de
--   inmediato. Una promoción sigue requiriendo un JWT nuevo (fail-closed).
--
--   La función pasa a SECURITY DEFINER para consultar `perfiles` sin recursion
--   de RLS; no recibe parámetros y solo usa `auth.uid()` y el perfil propio.
--
-- Depende de 0001 (es_admin, current_rol), 0004 (perfiles) y 0013
-- (current_empresa_id con empresa activa).
--
-- Ejecución local: supabase db reset
-- Nota: el CLI de Supabase aplica cada migración dentro de una transacción.
-- No se incluye BEGIN/COMMIT explícito para evitar transacciones anidadas.
-- =============================================================================

create or replace function private.es_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    private.current_rol() = 'admin'::public.rol_usuario
    and exists (
      select 1
      from public.perfiles p
      where p.id = auth.uid()
        and p.rol = 'admin'::public.rol_usuario
        and p.activo
        and p.empresa_id = private.current_empresa_id()
    ),
    false
  );
$$;

comment on function private.es_admin() is
  'TRUE solo si el JWT dice admin Y el perfil materializado sigue siendo admin activo de la empresa activa. Una degradación o desactivación surte efecto de inmediato. Fail-closed.';

revoke all on function private.es_admin() from public;
grant execute on function private.es_admin() to authenticated, service_role;
