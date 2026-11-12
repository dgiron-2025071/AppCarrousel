-- =============================================================================
-- Carrousel — Núcleo backend
-- MT-01 / Archivo 22: quitar los claims revoca el perfil
-- Fecha: 2026-11-12
--
-- Problema:
--   `sync_perfil_desde_auth` solo materializaba el perfil cuando llegaban los
--   tres claims completos. Si service_role limpiaba `app_metadata` para retirar
--   el alcance de una cuenta, el trigger salía sin tocar `public.perfiles`: el
--   perfil seguía activo y el JWT ya emitido conservaba el rol hasta vencer.
--   La revocación dependía de que el operador recordara desactivar el perfil a
--   mano.
--
-- Decisión:
--   Si una actualización de `auth.users` deja los claims incompletos, el perfil
--   existente se desactiva (`activo = false`). Un usuario nuevo sin claims sigue
--   sin perfil, como antes. Restaurar los claims no reactiva una baja: el alta
--   debe ser explícita (`activo = true`) para que una suspensión no se deshaga
--   por accidente al corregir el alcance. La desactivación conserva el historial
--   porque no borra la fila.
--
-- Depende de 0004 (trigger de sincronización) y 0012 (retención del historial).
--
-- Ejecución local: supabase db reset
-- Nota: el CLI de Supabase aplica cada migración dentro de una transacción.
-- No se incluye BEGIN/COMMIT explícito para evitar transacciones anidadas.
-- =============================================================================

create or replace function private.sync_perfil_desde_auth()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_empresa_id uuid;
  v_centro_id  uuid;
  v_rol        public.rol_usuario;
  v_nombre     text;
begin
  v_empresa_id := private.safe_uuid(new.raw_app_meta_data ->> 'empresa_id');
  v_centro_id  := private.safe_uuid(new.raw_app_meta_data ->> 'centro_costo_id');

  v_rol := case new.raw_app_meta_data ->> 'rol'
             when 'empleado' then 'empleado'::public.rol_usuario
             when 'admin'  then 'admin'::public.rol_usuario
             else null
           end;

  -- Sin claims completos no se materializa el perfil. Si ya existía, se
  -- desactiva: retirar el alcance debe cortar el acceso del token vigente.
  if v_empresa_id is null or v_centro_id is null or v_rol is null then
    update public.perfiles
       set activo = false
     where id = new.id
       and activo;

    return new;
  end if;

  -- El centro debe existir en la empresa indicada. FORCE no está activo, así
  -- que el dueño de la función puede leer ambas tablas sin RLS.
  if not exists (
    select 1
    from public.centros_costo c
    where c.id = v_centro_id
      and c.empresa_id = v_empresa_id
  ) then
    raise exception 'Alcance inválido: el centro % no pertenece a la empresa %',
      v_centro_id, v_empresa_id
      using errcode = '23503';
  end if;

  v_nombre := coalesce(
    nullif(btrim(new.raw_user_meta_data ->> 'nombre_completo'), ''),
    split_part(new.email, '@', 1),
    new.id::text
  );

  insert into public.perfiles (
    id, empresa_id, centro_costo_id, rol, nombre_completo
  )
  values (
    new.id, v_empresa_id, v_centro_id, v_rol, v_nombre
  )
  on conflict (id) do update
    set empresa_id      = excluded.empresa_id,
        centro_costo_id = excluded.centro_costo_id,
        rol             = excluded.rol,
        nombre_completo = excluded.nombre_completo;

  return new;
end;
$$;

comment on function private.sync_perfil_desde_auth() is
  'Materializa public.perfiles desde app_metadata. Sin claims completos desactiva un perfil existente; restaurarlos no lo reactiva. Idempotente.';
