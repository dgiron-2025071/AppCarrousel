-- =============================================================================
-- Carrousel — Núcleo backend
-- MT-02 / Archivo 26: centros de costo adicionales por lugar
-- Fecha: 2026-11-13
--
-- Crea:
--   1. public.parques_centros        — CECO disponibles en cada parque/lugar.
--   2. Backfill del CECO principal    — una fila por parque existente.
--   3. Sincronización del principal   — mover el parque mueve su CECO base.
--   4. public.solicitudes_horas_extras.parque_id — lugar donde se apoyó.
--   5. private.parque_en_empresa() / parque_en_alcance().
--   6. Política de alta de solicitudes — el lugar debe pertenecer al tenant y el
--      CECO debe estar habilitado para ese lugar.
--
-- Modelo:
--   Un parque (lugar) tiene un CECO principal, el de `parques.centro_costo_id`,
--   y puede ofrecer CECOs adicionales. El formulario de horas extras elige
--   primero el lugar y luego uno de sus CECOs. La FK compuesta y el trigger
--   impiden guardar un par CECO/lugar inexistente o inactivo. Las solicitudes
--   históricas sin lugar siguen siendo válidas (`parque_id` NULL).
--
-- Depende de 0003 (parques), 0005 (unique (empresa_id, id) en parques),
-- 0006/0018 (solicitudes) y 0002 (centros_costo).
--
-- Ejecución local: supabase db reset
-- Nota: el CLI de Supabase aplica cada migración dentro de una transacción.
-- No se incluye BEGIN/COMMIT explícito para evitar transacciones anidadas.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Helpers de alcance del parque
-- -----------------------------------------------------------------------------
create or replace function private.parque_en_empresa(p_parque_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    exists (
      select 1
      from public.parques p
      where p.id = p_parque_id
        and p.empresa_id = private.current_empresa_id()
    ),
    false
  );
$$;

comment on function private.parque_en_empresa(uuid) is
  'TRUE si el parque pertenece a la empresa del JWT. Fail-closed.';

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
      from public.parques p
      where p.id = p_parque_id
        and p.empresa_id = private.current_empresa_id()
        and private.centro_en_alcance(p.centro_costo_id)
    ),
    false
  );
$$;

comment on function private.parque_en_alcance(uuid) is
  'TRUE si el parque pertenece al subárbol del centro del JWT. Fail-closed.';

revoke all on function private.parque_en_empresa(uuid) from public;
revoke all on function private.parque_en_alcance(uuid) from public;

grant execute on function private.parque_en_empresa(uuid)
  to authenticated, service_role;
grant execute on function private.parque_en_alcance(uuid)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 2. CECO por lugar
-- -----------------------------------------------------------------------------
create table public.parques_centros (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas (id) on delete restrict,
  parque_id       uuid not null,
  centro_costo_id uuid not null,
  principal       boolean not null default false,
  activo          boolean not null default true,
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now(),
  actualizado_por uuid references auth.users (id) on delete set null,

  -- Destino de la FK compuesta de solicitudes_horas_extras.
  constraint parques_centros_parque_centro_key
    unique (empresa_id, parque_id, centro_costo_id),
  constraint parques_centros_parque_fk
    foreign key (empresa_id, parque_id)
    references public.parques (empresa_id, id)
    on delete restrict,
  constraint parques_centros_centro_fk
    foreign key (empresa_id, centro_costo_id)
    references public.centros_costo (empresa_id, id)
    on delete restrict,
  constraint parques_centros_principal_activo
    check (not principal or activo)
);

comment on table public.parques_centros is
  'CECOs habilitados por parque/lugar. El principal replica parques.centro_costo_id; los adicionales permiten cargar horas a otros centros.';
comment on column public.parques_centros.principal is
  'CECO base del parque. Solo lo mueve la sincronización con parques.centro_costo_id.';

create index parques_centros_empresa_centro_idx
  on public.parques_centros (empresa_id, centro_costo_id);

-- Exactamente un principal por parque (además del backfill y del trigger).
create unique index parques_centros_un_principal
  on public.parques_centros (parque_id)
  where principal;

create index parques_centros_empresa_parque_activo_idx
  on public.parques_centros (empresa_id, parque_id, activo);

create trigger parques_centros_auditoria
before update on public.parques_centros
for each row execute function private.set_actualizado_en();

-- -----------------------------------------------------------------------------
-- 3. Backfill del principal
-- -----------------------------------------------------------------------------
insert into public.parques_centros (
  empresa_id, parque_id, centro_costo_id, principal, activo
)
select p.empresa_id, p.id, p.centro_costo_id, true, true
from public.parques p
on conflict (empresa_id, parque_id, centro_costo_id) do nothing;

-- -----------------------------------------------------------------------------
-- 4. Protección y sincronización del principal
-- -----------------------------------------------------------------------------
-- El principal no se edita ni se borra a mano: se deriva del parque. La
-- sincronización usa una marca local en la transacción para poder moverlo.
create or replace function private.parques_centros_proteger_principal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sync text := coalesce(
    current_setting('carrousel.parques_centros_sync', true), ''
  );
begin
  if v_sync = 'on' then
    return coalesce(new, old);
  end if;

  if tg_op = 'DELETE' then
    if old.principal then
      raise exception 'El CECO principal se gestiona desde el centro del parque'
        using errcode = '23514';
    end if;
    return old;
  end if;

  if tg_op = 'UPDATE' then
    if old.principal
       and (
         not new.principal
         or new.empresa_id is distinct from old.empresa_id
         or new.parque_id is distinct from old.parque_id
         or new.centro_costo_id is distinct from old.centro_costo_id
       ) then
      raise exception 'El CECO principal se gestiona desde el centro del parque'
        using errcode = '23514';
    end if;
    return new;
  end if;

  if new.principal and new.centro_costo_id is distinct from (
    select p.centro_costo_id
    from public.parques p
    where p.id = new.parque_id
      and p.empresa_id = new.empresa_id
  ) then
    raise exception 'El CECO principal debe coincidir con el centro del parque'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

comment on function private.parques_centros_proteger_principal() is
  'Impide editar o borrar el CECO principal a mano. La sincronización con parques usa una marca de sesión.';

revoke all on function private.parques_centros_proteger_principal() from public;

create trigger parques_centros_proteger_principal
before insert or update or delete on public.parques_centros
for each row execute function private.parques_centros_proteger_principal();

create or replace function private.parques_centros_sync_principal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform set_config('carrousel.parques_centros_sync', 'on', true);

  -- Se conserva la fila anterior como CECO adicional inactivo para no romper
  -- solicitudes históricas que la referencian.
  update public.parques_centros pc
     set principal = false,
         activo = false
   where pc.empresa_id = new.empresa_id
     and pc.parque_id = new.id
     and pc.principal
     and pc.centro_costo_id is distinct from new.centro_costo_id;

  insert into public.parques_centros (
    empresa_id, parque_id, centro_costo_id, principal, activo
  )
  values (new.empresa_id, new.id, new.centro_costo_id, true, true)
  on conflict (empresa_id, parque_id, centro_costo_id) do update
    set principal = true,
        activo = true;

  perform set_config('carrousel.parques_centros_sync', 'off', true);

  return null;
end;
$$;

comment on function private.parques_centros_sync_principal() is
  'Mantiene el CECO principal del parque alineado con parques.centro_costo_id sin perder las filas históricas.';

revoke all on function private.parques_centros_sync_principal() from public;

create trigger parques_centros_sync_principal
after insert or update of centro_costo_id, empresa_id on public.parques
for each row execute function private.parques_centros_sync_principal();

-- -----------------------------------------------------------------------------
-- 5. RLS y grants: parques_centros
-- -----------------------------------------------------------------------------
alter table public.parques_centros enable row level security;

create policy parques_centros_select_alcance
  on public.parques_centros
  for select
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and (
      private.parque_en_alcance(parque_id)
      or private.centro_en_alcance(centro_costo_id)
    )
  );

create policy parques_centros_insert_admin
  on public.parques_centros
  for insert
  to authenticated
  with check (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_admin())
    and private.parque_en_alcance(parque_id)
    and private.centro_en_alcance(centro_costo_id)
  );

create policy parques_centros_update_admin
  on public.parques_centros
  for update
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_admin())
    and private.parque_en_alcance(parque_id)
    and private.centro_en_alcance(centro_costo_id)
  )
  with check (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_admin())
    and private.parque_en_alcance(parque_id)
    and private.centro_en_alcance(centro_costo_id)
  );

create policy parques_centros_delete_admin
  on public.parques_centros
  for delete
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_admin())
    and private.parque_en_alcance(parque_id)
    and private.centro_en_alcance(centro_costo_id)
  );

comment on policy parques_centros_select_alcance on public.parques_centros is
  'Un usuario ve los CECOs de los parques de su subárbol y los CECOs de su subárbol.';
comment on policy parques_centros_insert_admin on public.parques_centros is
  'Solo un admin activo agrega CECOs a un parque de su alcance.';
comment on policy parques_centros_update_admin on public.parques_centros is
  'Solo un admin activo edita los CECOs adicionales de su alcance.';
comment on policy parques_centros_delete_admin on public.parques_centros is
  'Solo un admin activo elimina CECOs adicionales de su alcance.';

revoke all on table public.parques_centros from anon, authenticated;

grant select on table public.parques_centros to authenticated;
grant insert (empresa_id, parque_id, centro_costo_id, principal, activo)
  on table public.parques_centros to authenticated;
grant update (activo) on table public.parques_centros to authenticated;
grant delete on table public.parques_centros to authenticated;

-- -----------------------------------------------------------------------------
-- 6. Lugar en las solicitudes de horas extras
-- -----------------------------------------------------------------------------
alter table public.solicitudes_horas_extras
  add column parque_id uuid;

alter table public.solicitudes_horas_extras
  add constraint solicitudes_parque_empresa_fk
    foreign key (empresa_id, parque_id)
    references public.parques (empresa_id, id)
    on delete restrict,
  add constraint solicitudes_parque_centro_fk
    foreign key (empresa_id, parque_id, centro_costo_id)
    references public.parques_centros (empresa_id, parque_id, centro_costo_id)
    on delete restrict;

create index solicitudes_empresa_parque_idx
  on public.solicitudes_horas_extras (empresa_id, parque_id);

comment on column public.solicitudes_horas_extras.parque_id is
  'Parque/lugar donde se apoyó. NULL en solicitudes históricas. El CECO debe estar habilitado para ese lugar.';

-- La FK compuesta no distingue filas inactivas; el trigger sí.
create or replace function private.solicitudes_validar_lugar()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.parque_id is null then
    return new;
  end if;

  if not exists (
    select 1
    from public.parques_centros pc
    where pc.empresa_id = new.empresa_id
      and pc.parque_id = new.parque_id
      and pc.centro_costo_id = new.centro_costo_id
      and pc.activo
  ) then
    raise exception 'El centro de costo no está habilitado para el lugar seleccionado'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

comment on function private.solicitudes_validar_lugar() is
  'Exige que el par CECO/lugar exista y esté activo. La FK compuesta cubre la integridad; esto cubre la habilitación.';

revoke all on function private.solicitudes_validar_lugar() from public;

create trigger solicitudes_validar_lugar
before insert or update of parque_id, centro_costo_id, empresa_id
on public.solicitudes_horas_extras
for each row execute function private.solicitudes_validar_lugar();

-- Se reemplaza la política de alta para incorporar el lugar. El resto de las
-- condiciones se conserva tal como está en 0006.
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
    and (parque_id is null or private.parque_en_empresa(parque_id))
  );

comment on policy solicitudes_insert_propia on public.solicitudes_horas_extras is
  'Solo el propio especialista activo crea solicitudes pendientes para un CECO y un lugar de su empresa.';

grant insert (parque_id) on table public.solicitudes_horas_extras to authenticated;
