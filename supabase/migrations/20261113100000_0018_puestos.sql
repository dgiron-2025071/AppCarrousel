-- =============================================================================
-- Carrousel — Propuesta de integración con la operación actual
-- Archivo 18: catálogo de puestos por empresa
-- Fecha: 2026-11-11
--
-- Crea:
--   1. public.puestos          — catálogo de puestos (Técnico, Cajero, ...).
--   2. perfiles.puesto_id      — puesto actual del usuario.
--   3. Sincronización          — el puesto llega en app_metadata.puesto_id,
--                                igual que el rol y el alcance.
--
-- El puesto es informativo (reportes y aprobaciones); no concede permisos.
-- Solo service_role lo asigna, para que nadie cambie su propio puesto.
--
-- Depende de 0002 (empresas) y 0004 (perfiles, sync_perfil_desde_auth).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Puestos
-- -----------------------------------------------------------------------------
create table public.puestos (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas (id) on delete restrict,
  nombre          extensions.citext not null,
  activo          boolean not null default true,
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now(),
  actualizado_por uuid references auth.users (id) on delete set null,

  constraint puestos_empresa_nombre_key unique (empresa_id, nombre),
  -- Destino de la FK compuesta desde perfiles: impide cruzar de empresa.
  constraint puestos_empresa_id_key unique (empresa_id, id),
  constraint puestos_nombre_valido check (length(btrim(nombre::text)) between 2 and 120)
);

comment on table public.puestos is
  'Catálogo de puestos por empresa. Informativo: no concede permisos. Lo administra service_role.';

create trigger puestos_auditoria
before update on public.puestos
for each row execute function private.set_actualizado_en();

alter table public.puestos enable row level security;

create policy puestos_select_tenant
  on public.puestos
  for select
  to authenticated
  using (empresa_id = (select private.current_empresa_id()));

comment on policy puestos_select_tenant on public.puestos is
  'Todo usuario de la empresa puede leer el catálogo de puestos.';

revoke all on table public.puestos from anon, authenticated;
grant select on table public.puestos to authenticated;
grant select, insert, update, delete on table public.puestos to service_role;

-- -----------------------------------------------------------------------------
-- 2. Puesto del perfil
-- -----------------------------------------------------------------------------
alter table public.perfiles
  add column puesto_id uuid,
  add constraint perfiles_puesto_fk
    foreign key (empresa_id, puesto_id)
    references public.puestos (empresa_id, id)
    on delete restrict;

comment on column public.perfiles.puesto_id is
  'Puesto actual. Espejo de app_metadata.puesto_id; el cliente no puede escribirlo.';

create index perfiles_puesto_idx on public.perfiles (puesto_id);

-- -----------------------------------------------------------------------------
-- 3. Sincronización desde app_metadata
-- -----------------------------------------------------------------------------
-- Igual que 0004, más el puesto. Un puesto ausente deja la columna en NULL;
-- un puesto de otra empresa se rechaza por la FK compuesta.
create or replace function private.sync_perfil_desde_auth()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_empresa_id uuid;
  v_centro_id  uuid;
  v_puesto_id  uuid;
  v_rol        public.rol_usuario;
  v_nombre     text;
begin
  v_empresa_id := private.safe_uuid(new.raw_app_meta_data ->> 'empresa_id');
  v_centro_id  := private.safe_uuid(new.raw_app_meta_data ->> 'centro_costo_id');
  v_puesto_id  := private.safe_uuid(new.raw_app_meta_data ->> 'puesto_id');

  v_rol := case new.raw_app_meta_data ->> 'rol'
             when 'empleado' then 'empleado'::public.rol_usuario
             when 'admin'  then 'admin'::public.rol_usuario
             else null
           end;

  if v_empresa_id is null or v_centro_id is null or v_rol is null then
    return new;
  end if;

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
    id, empresa_id, centro_costo_id, rol, nombre_completo, puesto_id
  )
  values (
    new.id, v_empresa_id, v_centro_id, v_rol, v_nombre, v_puesto_id
  )
  on conflict (id) do update
    set empresa_id      = excluded.empresa_id,
        centro_costo_id = excluded.centro_costo_id,
        rol             = excluded.rol,
        nombre_completo = excluded.nombre_completo,
        puesto_id       = excluded.puesto_id;

  return new;
end;
$$;

comment on function private.sync_perfil_desde_auth() is
  'Materializa public.perfiles desde app_metadata (empresa, centro, rol y puesto). Idempotente.';

revoke all on function private.sync_perfil_desde_auth() from public;
