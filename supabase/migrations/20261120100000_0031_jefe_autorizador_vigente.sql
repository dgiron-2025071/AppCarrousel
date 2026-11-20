-- =============================================================================
-- MT-02 / Archivo 31: el jefe del centro no queda obsoleto
-- =============================================================================
-- `centros_costo.jefe_id` se valida al asignarlo (0023), pero un administrador
-- puede dejar de serlo después: baja (`activo = false`), degradación a
-- `empleado` o cambio de empresa desde `auth.users` (que resincroniza el
-- perfil). Sin este trigger la columna seguía apuntando a un perfil que ya no
-- puede autorizar y el centro se quedaba sin jefe en caliente.
--
-- La corrección es limpiar la designación, no rechazar el cambio del perfil:
-- `sync_perfil_desde_auth()` debe poder reflejar siempre lo que dice el JWT.
-- La jerarquía sigue resolviendo con el ancestro más cercano.
-- =============================================================================

create or replace function private.limpiar_jefe_de_perfil()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- El perfil sigue siendo un admin activo de la misma empresa: no hay nada
  -- que corregir. El alcance (`centro_costo_id`) no invalida la designación;
  -- `es_admin()` ya exige que el JWT y el perfil coincidan.
  if new.activo
     and new.rol = 'admin'::public.rol_usuario
     and new.empresa_id = old.empresa_id then
    return new;
  end if;

  update public.centros_costo c
     set jefe_id = null
   where c.jefe_id = new.id
     and c.jefe_id is not null;

  return new;
end;
$$;

comment on function private.limpiar_jefe_de_perfil() is
  'Limpia centros_costo.jefe_id cuando el perfil deja de ser admin activo de su empresa. Mantiene la jerarquía de autorización vigente sin bloquear la sincronización de claims.';

revoke all on function private.limpiar_jefe_de_perfil() from public;

drop trigger if exists perfiles_jefe_vigente on public.perfiles;
create trigger perfiles_jefe_vigente
after update of activo, rol, empresa_id
on public.perfiles
for each row execute function private.limpiar_jefe_de_perfil();
