-- =============================================================================
-- Carrousel — Núcleo backend
-- MT-01 / Archivo 04: perfiles y separación de roles
-- Fecha: 2026-11-05
--
-- Crea:
--   1. public.perfiles                 — espejo de auth.users con alcance y rol.
--   2. Sincronización desde auth.users — materializa los claims de app_metadata.
--   3. Integridad cross-tenant         — empresa y centro deben coincidir.
--   4. RLS de lectura                  — perfil propio; admin ve su subárbol.
--   5. Sin escritura del cliente       — rol y alcance solo los escribe el servidor.
--
-- Modelo de aprovisionamiento:
--   La Edge Function con service_role crea el usuario y escribe en
--   app_metadata: empresa_id, centro_costo_id y rol. El trigger de auth.users
--   materializa el perfil. Un empleado no puede escribir auth.users ni
--   public.perfiles, por lo que no puede autoelevarse a admin.
--
-- Depende de 0001 (rol_usuario, safe_uuid) y 0002 (empresas, centros_costo).
--
-- Ejecución local: supabase db reset
-- Nota: el CLI de Supabase aplica cada migración dentro de una transacción.
-- No se incluye BEGIN/COMMIT explícito para evitar transacciones anidadas.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Perfiles
-- -----------------------------------------------------------------------------
create table public.perfiles (
  id              uuid primary key references auth.users (id) on delete cascade,
  empresa_id      uuid not null references public.empresas (id) on delete restrict,
  centro_costo_id uuid not null,
  rol             public.rol_usuario not null,
  nombre_completo extensions.citext not null,
  activo          boolean not null default true,
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now(),
  actualizado_por uuid references auth.users (id) on delete set null,

  -- FK compuesta: el centro debe pertenecer a la empresa del perfil.
  constraint perfiles_centro_fk
    foreign key (empresa_id, centro_costo_id)
    references public.centros_costo (empresa_id, id)
    on delete restrict
);

comment on table public.perfiles is
  'Perfil de negocio por usuario de Auth. El rol y el alcance provienen de app_metadata y solo los escribe service_role.';
comment on column public.perfiles.rol is
  'Espejo de app_metadata.rol. El cliente no tiene privilegios de escritura sobre esta columna.';
comment on column public.perfiles.centro_costo_id is
  'Centro al que está asignado el usuario. Define su alcance jerárquico en RLS.';

create index perfiles_empresa_centro_idx
  on public.perfiles (empresa_id, centro_costo_id);

create trigger perfiles_auditoria
before update on public.perfiles
for each row execute function private.set_actualizado_en();

-- -----------------------------------------------------------------------------
-- 2. Sincronización desde auth.users
-- -----------------------------------------------------------------------------
-- Se ejecuta con privilegios del dueño de la migración para poder escribir
-- public.perfiles, que no otorga INSERT/UPDATE a los roles de API.
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

  -- Sin claims completos no se materializa el perfil. El usuario existe en
  -- Auth pero RLS lo deja sin acceso hasta que service_role asigne el alcance.
  if v_empresa_id is null or v_centro_id is null or v_rol is null then
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
  'Materializa public.perfiles desde app_metadata. Idempotente: actualiza el perfil si el alcance o el rol cambian.';

revoke all on function private.sync_perfil_desde_auth() from public;

create trigger on_auth_user_sync_perfil
after insert or update of raw_app_meta_data on auth.users
for each row execute function private.sync_perfil_desde_auth();

-- -----------------------------------------------------------------------------
-- 3. RLS: perfiles
-- -----------------------------------------------------------------------------
alter table public.perfiles enable row level security;

create policy perfiles_select_propio_o_equipo
  on public.perfiles
  for select
  to authenticated
  using (
    id = (select auth.uid())
    or (
      empresa_id = (select private.current_empresa_id())
      and (select private.es_admin())
      and private.centro_en_alcance(centro_costo_id)
    )
  );

comment on policy perfiles_select_propio_o_equipo on public.perfiles is
  'Cada usuario ve su perfil; un admin ve además los perfiles de su subárbol.';

-- Sin políticas de INSERT/UPDATE/DELETE para authenticated: el perfil y el rol
-- solo los modifica el trigger (service_role) o una operación administrativa.
-- Esto es lo que impide que un empleado se autoeleve.

-- -----------------------------------------------------------------------------
-- 4. Grants explícitos
-- -----------------------------------------------------------------------------
revoke all on table public.perfiles from anon, authenticated;

grant select on table public.perfiles to authenticated;
-- service_role conserva la administración total, incluida la corrección manual
-- de perfiles desde el backend. No se otorga nada a anon.
grant select, insert, update, delete on table public.perfiles to service_role;
