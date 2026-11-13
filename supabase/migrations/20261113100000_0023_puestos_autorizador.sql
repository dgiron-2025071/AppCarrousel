-- =============================================================================
-- Carrousel — Núcleo backend
-- MT-02 / Archivo 23: puestos y autorizador jerárquico de horas extras
-- Fecha: 2026-11-13
--
-- Crea:
--   1. public.puestos                 — catálogo de puestos por empresa.
--   2. public.perfiles.puesto_id      — puesto vigente del perfil (claim).
--   3. public.centros_costo.jefe_id   — administrador responsable del centro.
--   4. private.jefe_de_centro()       — sube por `ruta` hasta el primer jefe.
--   5. private.es_autorizador()       — TRUE si el JWT es el jefe del centro.
--   6. Sincronización del claim        — materializa `puesto_id` desde Auth.
--   7. RLS y grants                    — catálogo por tenant; escribe un admin.
--
-- Modelo:
--   El jefe de un centro es un perfil con rol `admin`, activo y de la misma
--   empresa. Si un centro no tiene jefe propio, el autorizador es el jefe del
--   ancestro más cercano. Esto mantiene la regla de `0019` (solo un admin firma
--   la revisión) y permite que la jerarquía decida *qué* admin debe aprobar.
--
-- Depende de 0002 (centros_costo.ruta), 0004/0014 (perfiles, es_admin),
-- 0016 (unique (empresa_id, id) en perfiles) y 0022 (sync de claims).
--
-- Ejecución local: supabase db reset
-- Nota: el CLI de Supabase aplica cada migración dentro de una transacción.
-- No se incluye BEGIN/COMMIT explícito para evitar transacciones anidadas.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Catálogo de puestos
-- -----------------------------------------------------------------------------
create table public.puestos (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas (id) on delete restrict,
  codigo          extensions.citext not null,
  nombre          extensions.citext not null,
  descripcion     text,
  activo          boolean not null default true,
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now(),
  actualizado_por uuid references auth.users (id) on delete set null,

  constraint puestos_empresa_codigo_key unique (empresa_id, codigo),
  -- Destino de la FK compuesta de perfiles.
  constraint puestos_empresa_id_key unique (empresa_id, id),
  constraint puestos_nombre_valido
    check (length(btrim(nombre::text)) between 1 and 120)
);

comment on table public.puestos is
  'Catálogo de puestos por empresa. Cada perfil referencia su puesto vigente. Sin datos hardcodeados.';
comment on column public.puestos.codigo is
  'Identificador estable dentro de la empresa. Case-insensitive por citext.';

create index puestos_empresa_activo_idx
  on public.puestos (empresa_id, activo);

create trigger puestos_auditoria
before update on public.puestos
for each row execute function private.set_actualizado_en();

-- -----------------------------------------------------------------------------
-- 2. Puesto del perfil
-- -----------------------------------------------------------------------------
alter table public.perfiles
  add column puesto_id uuid;

alter table public.perfiles
  add constraint perfiles_puesto_fk
    foreign key (empresa_id, puesto_id)
    references public.puestos (empresa_id, id)
    on delete restrict;

create index perfiles_empresa_puesto_idx
  on public.perfiles (empresa_id, puesto_id);

comment on column public.perfiles.puesto_id is
  'Puesto vigente del perfil. Se materializa desde app_metadata.puesto_id; el cliente no lo escribe.';

-- -----------------------------------------------------------------------------
-- 3. Jefe responsable del centro
-- -----------------------------------------------------------------------------
-- ON DELETE RESTRICT: el historial y la cadena de autorización no se pueden
-- quedar sin responsable por borrar una cuenta. La baja se hace desactivando.
alter table public.centros_costo
  add column jefe_id uuid;

alter table public.centros_costo
  add constraint centros_costo_jefe_fk
    foreign key (empresa_id, jefe_id)
    references public.perfiles (empresa_id, id)
    on delete restrict;

create index centros_costo_empresa_jefe_idx
  on public.centros_costo (empresa_id, jefe_id);

comment on column public.centros_costo.jefe_id is
  'Administrador responsable del centro. Si es NULL, el autorizador se busca en el ancestro más cercano.';

-- El jefe debe ser un administrador activo de la misma empresa. Se valida en
-- AFTER para conservar el código 23503 de la FK si el perfil ni siquiera existe
-- o pertenece a otra empresa.
create or replace function private.centros_costo_validar_jefe()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.jefe_id is null then
    return new;
  end if;

  if not exists (
    select 1
    from public.perfiles p
    where p.id = new.jefe_id
      and p.empresa_id = new.empresa_id
      and p.rol = 'admin'::public.rol_usuario
      and p.activo
  ) then
    raise exception 'El jefe del centro debe ser un administrador activo de la misma empresa'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

comment on function private.centros_costo_validar_jefe() is
  'Exige que centros_costo.jefe_id sea un admin activo de la misma empresa, incluso con service_role.';

revoke all on function private.centros_costo_validar_jefe() from public;

create trigger centros_costo_validar_jefe
after insert or update of jefe_id, empresa_id
on public.centros_costo
for each row execute function private.centros_costo_validar_jefe();

-- -----------------------------------------------------------------------------
-- 4. Autorizador jerárquico
-- -----------------------------------------------------------------------------
create or replace function private.jefe_de_centro(p_centro_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  with recursive cadena as (
    select c.id, c.padre_id, c.jefe_id, 0 as nivel
    from public.centros_costo c
    where c.id = p_centro_id
      and c.empresa_id = private.current_empresa_id()

    union all

    select p.id, p.padre_id, p.jefe_id, cadena.nivel + 1
    from public.centros_costo p
    join cadena on p.id = cadena.padre_id
    where p.empresa_id = private.current_empresa_id()
  )
  select cadena.jefe_id
  from cadena
  where cadena.jefe_id is not null
  order by cadena.nivel
  limit 1;
$$;

comment on function private.jefe_de_centro(uuid) is
  'Devuelve el jefe del centro o, si no tiene, el del ancestro más cercano. NULL si no hay ninguno. Acotado a la empresa del JWT.';

create or replace function private.es_autorizador(p_centro_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    private.es_admin()
    and private.jefe_de_centro(p_centro_id) = auth.uid(),
    false
  );
$$;

comment on function private.es_autorizador(uuid) is
  'TRUE si el JWT pertenece al admin activo que la jerarquía designa como jefe del centro. Fail-closed.';

revoke all on function private.jefe_de_centro(uuid) from public;
revoke all on function private.es_autorizador(uuid) from public;

grant execute on function private.jefe_de_centro(uuid)
  to authenticated, service_role;
grant execute on function private.es_autorizador(uuid)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 5. Sincronización del claim puesto_id
-- -----------------------------------------------------------------------------
-- Se conserva el comportamiento de 0022: sin claims completos el perfil se
-- desactiva. `puesto_id` es opcional; si viene, debe pertenecer a la empresa.
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
    update public.perfiles
       set activo = false
     where id = new.id
       and activo;

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

  if v_puesto_id is not null and not exists (
    select 1
    from public.puestos pu
    where pu.id = v_puesto_id
      and pu.empresa_id = v_empresa_id
  ) then
    raise exception 'Puesto inválido: % no pertenece a la empresa %',
      v_puesto_id, v_empresa_id
      using errcode = '23503';
  end if;

  v_nombre := coalesce(
    nullif(btrim(new.raw_user_meta_data ->> 'nombre_completo'), ''),
    split_part(new.email, '@', 1),
    new.id::text
  );

  insert into public.perfiles (
    id, empresa_id, centro_costo_id, puesto_id, rol, nombre_completo
  )
  values (
    new.id, v_empresa_id, v_centro_id, v_puesto_id, v_rol, v_nombre
  )
  on conflict (id) do update
    set empresa_id      = excluded.empresa_id,
        centro_costo_id = excluded.centro_costo_id,
        puesto_id       = excluded.puesto_id,
        rol             = excluded.rol,
        nombre_completo = excluded.nombre_completo;

  return new;
end;
$$;

comment on function private.sync_perfil_desde_auth() is
  'Materializa perfiles desde app_metadata, incluido puesto_id. Sin claims completos desactiva un perfil existente; restaurarlos no lo reactiva. Idempotente.';

-- -----------------------------------------------------------------------------
-- 6. RLS: puestos
-- -----------------------------------------------------------------------------
alter table public.puestos enable row level security;

create policy puestos_select_tenant
  on public.puestos
  for select
  to authenticated
  using (empresa_id = (select private.current_empresa_id()));

create policy puestos_insert_admin
  on public.puestos
  for insert
  to authenticated
  with check (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_admin())
  );

create policy puestos_update_admin
  on public.puestos
  for update
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_admin())
  )
  with check (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_admin())
  );

create policy puestos_delete_admin
  on public.puestos
  for delete
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_admin())
  );

comment on policy puestos_select_tenant on public.puestos is
  'Cada usuario ve el catálogo de su empresa.';
comment on policy puestos_insert_admin on public.puestos is
  'Solo un admin activo crea puestos en su empresa.';
comment on policy puestos_update_admin on public.puestos is
  'Solo un admin activo edita puestos de su empresa.';
comment on policy puestos_delete_admin on public.puestos is
  'Solo un admin activo elimina puestos de su empresa.';

-- -----------------------------------------------------------------------------
-- 7. Grants explícitos
-- -----------------------------------------------------------------------------
revoke all on table public.puestos from anon, authenticated;

grant select on table public.puestos to authenticated;
grant insert (empresa_id, codigo, nombre, descripcion, activo)
  on table public.puestos to authenticated;
grant update (codigo, nombre, descripcion, activo)
  on table public.puestos to authenticated;
grant delete on table public.puestos to authenticated;

-- El admin asigna el jefe de un centro; el trigger valida rol y empresa.
-- `empresa_id` no se otorga: no se puede mover el centro de tenant.
grant update (jefe_id) on table public.centros_costo to authenticated;
