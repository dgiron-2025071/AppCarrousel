-- =============================================================================
-- Carrousel — Núcleo backend
-- MT-01 / Archivo 17: revocación inmediata del alcance de administrador
-- Fecha: 2026-11-11
--
-- Problema:
--   `private.es_admin()` cruzaba el JWT con el perfil materializado para el rol
--   y la empresa (0014), pero no para el centro de costo. Si un administrador
--   era movido de subárbol con `service_role`, su perfil cambiaba de inmediato
--   mientras el JWT seguía apuntando al centro anterior. Hasta que la sesión se
--   refrescara, conservaba la lectura y la gestión del subárbol viejo.
--
-- Decisión:
--   `es_admin()` exige además que el centro del perfil coincida con el centro
--   del JWT (`private.current_centro_id()`). Un cambio de alcance surte efecto
--   de inmediato y falla cerrado: el administrador pierde el equipo anterior y
--   solo recupera privilegios cuando su JWT refleja el centro nuevo.
--
--   No se toca `private.centro_en_alcance()` para no añadir una consulta a
--   `perfiles` en cada lectura de parques; el control de administración queda
--   centralizado en `es_admin()`, del que dependen las políticas de gestión y
--   de lectura del equipo.
--
-- Depende de 0013 (empresa activa) y 0014 (es_admin ligado al perfil).
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
        and p.centro_costo_id = private.current_centro_id()
    ),
    false
  );
$$;

comment on function private.es_admin() is
  'TRUE solo si el JWT dice admin Y el perfil materializado sigue siendo admin activo, de la misma empresa y del mismo centro que el JWT. Un cambio de rol, empresa o alcance surte efecto de inmediato. Fail-closed.';

revoke all on function private.es_admin() from public;
grant execute on function private.es_admin() to authenticated, service_role;
