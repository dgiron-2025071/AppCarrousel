-- =============================================================================
-- Carrousel — Núcleo backend
-- MT-01 / Archivo 02: empresas y jerarquía dinámica de centros de costo
-- Fecha: 2026-11-05
--
-- Crea:
--   1. public.empresas            — raíz multiempresa lógica.
--   2. public.centros_costo       — jerarquía auto-referenciada por empresa.
--   3. Integridad cross-tenant    — el padre debe pertenecer a la misma empresa.
--   4. Anti-ciclos y profundidad  — ruta materializada + trigger de validación.
--   5. Propagación de ruta        — mover un centro actualiza su subárbol.
--   6. Alcance jerárquico         — helper private.centro_en_alcance().
--   7. RLS y grants explícitos    — lectura del tenant; escritura por subárbol.
--      Las raíces y los movimientos de centros quedan reservados a service_role.
--
-- Depende de 0001: schema private, enum rol_usuario, helpers JWT y auditoría.
--
-- Ejecución local: supabase db reset
-- Nota: el CLI de Supabase aplica cada migración dentro de una transacción.
-- No se incluye BEGIN/COMMIT explícito para evitar transacciones anidadas.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Empresas
-- -----------------------------------------------------------------------------
create table public.empresas (
  id              uuid primary key default gen_random_uuid(),
  codigo          extensions.citext not null,
  nombre          extensions.citext not null,
  nombre_comercial text,
  activa          boolean not null default true,
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now(),
  actualizado_por uuid references auth.users (id) on delete set null,
  constraint empresas_codigo_key unique (codigo)
);

comment on table public.empresas is
  'Empresas del grupo. Raíz del aislamiento multiempresa. La creación solo se hace con service_role.';
comment on column public.empresas.codigo is
  'Identificador estable de negocio (no el uuid). Case-insensitive por citext.';

create trigger empresas_auditoria
before update on public.empresas
for each row execute function private.set_actualizado_en();

-- -----------------------------------------------------------------------------
-- 2. Centros de costo
-- -----------------------------------------------------------------------------
-- ruta = cadena de ancestros (sin incluir el propio centro). Permite validar
-- ciclos y consultar subárboles sin recursión en cada lectura.
create table public.centros_costo (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas (id) on delete restrict,
  padre_id        uuid,
  codigo          extensions.citext not null,
  nombre          extensions.citext not null,
  ruta            uuid[] not null default '{}'::uuid[],
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now(),
  actualizado_por uuid references auth.users (id) on delete set null,

  constraint centros_costo_empresa_codigo_key unique (empresa_id, codigo),
  -- Necesario para la FK compuesta (empresa_id, padre_id).
  constraint centros_costo_empresa_id_key unique (empresa_id, id),
  constraint centros_costo_padre_fk
    foreign key (empresa_id, padre_id)
    references public.centros_costo (empresa_id, id)
    on delete restrict,
  constraint centros_costo_no_auto_padre check (padre_id is distinct from id),
  constraint centros_costo_ruta_profundidad check (cardinality(ruta) <= 31)
);

comment on table public.centros_costo is
  'Jerarquía dinámica de centros de costo por empresa. Sin datos hardcodeados.';
comment on column public.centros_costo.padre_id is
  'Centro padre. NULL para la raíz de la empresa. La FK compuesta impide cruzar de empresa.';
comment on column public.centros_costo.ruta is
  'Ancestros del centro, de raíz a padre. La escribe únicamente el trigger.';

create index centros_costo_empresa_padre_idx
  on public.centros_costo (empresa_id, padre_id);

create index centros_costo_ruta_idx
  on public.centros_costo using gin (ruta);

create trigger centros_costo_auditoria
before update on public.centros_costo
for each row execute function private.set_actualizado_en();

-- -----------------------------------------------------------------------------
-- 3. Cálculo de ruta, validación de ciclos y profundidad
-- -----------------------------------------------------------------------------
-- SECURITY DEFINER: la validación debe ver el padre y el subárbol sin quedar
-- limitada por RLS del usuario que ejecuta la escritura. search_path vacío y
-- referencias calificadas evitan secuestro de objetos.
create or replace function private.centros_costo_set_ruta()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_padre_ruta uuid[];
  v_altura     integer;
begin
  if new.padre_id is null then
    new.ruta := '{}'::uuid[];
    return new;
  end if;

  if new.padre_id = new.id then
    raise exception 'Un centro de costo no puede ser su propio padre'
      using errcode = '23514';
  end if;

  -- El padre debe existir y pertenecer a la misma empresa. La FK compuesta ya
  -- lo garantiza, pero se valida aquí para dar un error explícito.
  select c.ruta
    into v_padre_ruta
  from public.centros_costo c
  where c.id = new.padre_id
    and c.empresa_id = new.empresa_id;

  if not found then
    raise exception 'El centro padre no existe en la misma empresa'
      using errcode = '23503';
  end if;

  -- Si el nuevo padre desciende del centro que se mueve, se formaría un ciclo.
  if coalesce(new.id = any (v_padre_ruta), false) then
    raise exception 'Jerarquía cíclica: el centro padre desciende del centro movido'
      using errcode = '23514';
  end if;

  new.ruta := v_padre_ruta || new.padre_id;

  -- La profundidad total (centro + subárbol) no puede exceder 32 niveles.
  with recursive descendientes as (
    select c.id, 1 as nivel
    from public.centros_costo c
    where c.padre_id = new.id
    union all
    select h.id, d.nivel + 1
    from public.centros_costo h
    join descendientes d on h.padre_id = d.id
  )
  select coalesce(max(d.nivel), 0)
    into v_altura
  from descendientes d;

  if cardinality(new.ruta) + 1 + v_altura > 32 then
    raise exception 'Profundidad máxima de jerarquía excedida (32 niveles)'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

comment on function private.centros_costo_set_ruta() is
  'Calcula ruta, rechaza auto-padre, ciclos y profundidad mayor a 32 niveles.';

create trigger centros_costo_set_ruta
before insert or update of empresa_id, padre_id on public.centros_costo
for each row execute function private.centros_costo_set_ruta();

-- -----------------------------------------------------------------------------
-- 4. Propagación de ruta al subárbol
-- -----------------------------------------------------------------------------
create or replace function private.centros_costo_propagar_ruta()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Evita la recursión: la actualización interna del subárbol dispara este
  -- mismo trigger a profundidad 2. Solo la sentencia del usuario (profundidad
  -- 1 dentro de la función) propaga. No se usa WHEN pg_trigger_depth() porque
  -- PostgreSQL evalúa el WHEN antes de incrementar la profundidad.
  if pg_trigger_depth() > 1 then
    return null;
  end if;

  if new.ruta is distinct from old.ruta then
    -- El subárbol se reconstruye desde la nueva ruta del centro movido.
    -- ruta_padre es la ruta que debe llevar cada hijo directo.
    with recursive subarbol as (
      select c.id, new.ruta || new.id as ruta_padre
      from public.centros_costo c
      where c.padre_id = new.id

      union all

      select h.id, s.ruta_padre || s.id
      from public.centros_costo h
      join subarbol s on h.padre_id = s.id
    )
    update public.centros_costo c
       set ruta = s.ruta_padre
      from subarbol s
     where c.id = s.id;
  end if;

  return null;
end;
$$;

comment on function private.centros_costo_propagar_ruta() is
  'Recalcula la ruta de todo el subárbol cuando un centro cambia de padre.';

-- AFTER UPDATE a secas: la columna ruta la escribe el trigger BEFORE, no el SET
-- de la sentencia, así que un "UPDATE OF ruta" nunca se dispararía al mover un
-- centro. La función comprueba si la ruta cambió y corta la recursión por
-- profundidad de trigger.
create trigger centros_costo_propagar_ruta
after update on public.centros_costo
for each row
execute function private.centros_costo_propagar_ruta();

-- -----------------------------------------------------------------------------
-- 5. Alcance jerárquico
-- -----------------------------------------------------------------------------
-- Un centro está en alcance si es el centro del JWT o un descendiente suyo.
-- Sin claim válido, sin coincidencia de empresa o sin fila visible: FALSE.
create or replace function private.centro_en_alcance(p_centro_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(
    exists (
      select 1
      from public.centros_costo c
      where c.id = p_centro_id
        and c.empresa_id = private.current_empresa_id()
        and (
          c.id = private.current_centro_id()
          or private.current_centro_id() = any (c.ruta)
        )
    ),
    false
  );
$$;

comment on function private.centro_en_alcance(uuid) is
  'TRUE si el centro es el del JWT o un descendiente suyo dentro de la misma empresa. Fail-closed.';

-- -----------------------------------------------------------------------------
-- 6. Privilegios de las funciones internas
-- -----------------------------------------------------------------------------
revoke all on function private.centros_costo_set_ruta()       from public;
revoke all on function private.centros_costo_propagar_ruta()  from public;
revoke all on function private.centro_en_alcance(uuid)        from public;

grant execute on function private.centro_en_alcance(uuid)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 7. RLS: empresas
-- -----------------------------------------------------------------------------
alter table public.empresas enable row level security;

create policy empresas_select_tenant
  on public.empresas
  for select
  to authenticated
  using (id = (select private.current_empresa_id()));

create policy empresas_update_admin
  on public.empresas
  for update
  to authenticated
  using (
    id = (select private.current_empresa_id())
    and (select private.es_admin())
  )
  with check (
    id = (select private.current_empresa_id())
    and (select private.es_admin())
  );

comment on policy empresas_select_tenant on public.empresas is
  'Cada usuario solo ve su propia empresa. Sin claim válido no hay filas.';
comment on policy empresas_update_admin on public.empresas is
  'Solo un admin puede actualizar datos de su propia empresa.';

-- -----------------------------------------------------------------------------
-- 8. RLS: centros de costo
-- -----------------------------------------------------------------------------
alter table public.centros_costo enable row level security;

-- Lectura: toda la jerarquía de la empresa. Escritura: solo el subárbol del
-- admin. Crear una raíz (padre_id NULL) o mover un centro de padre queda
-- reservado a service_role.
create policy centros_costo_select_tenant
  on public.centros_costo
  for select
  to authenticated
  using (empresa_id = (select private.current_empresa_id()));

create policy centros_costo_insert_admin
  on public.centros_costo
  for insert
  to authenticated
  with check (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_admin())
    and padre_id is not null
    and private.centro_en_alcance(padre_id)
  );

create policy centros_costo_update_admin
  on public.centros_costo
  for update
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_admin())
    and private.centro_en_alcance(id)
  )
  with check (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_admin())
    and private.centro_en_alcance(id)
  );

create policy centros_costo_delete_admin
  on public.centros_costo
  for delete
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_admin())
    and private.centro_en_alcance(id)
  );

comment on policy centros_costo_select_tenant on public.centros_costo is
  'Lectura limitada a los centros de la empresa del JWT.';
comment on policy centros_costo_insert_admin on public.centros_costo is
  'Alta de subcentros solo por admin y dentro de su subárbol. La raíz es administrativa.';
comment on policy centros_costo_update_admin on public.centros_costo is
  'Edición de centros dentro del subárbol del admin. Mover de padre es administrativo.';
comment on policy centros_costo_delete_admin on public.centros_costo is
  'Baja de centros dentro del subárbol del admin.';

-- -----------------------------------------------------------------------------
-- 9. Grants explícitos
-- -----------------------------------------------------------------------------
-- anon no recibe nada. authenticated solo recibe lo mínimo por columna:
-- ruta, timestamps y actualizado_por quedan fuera de toda escritura del cliente.
-- Las columnas usan extensions.citext; los roles de API necesitan poder
-- resolver el tipo al leer y escribir.
grant usage on schema extensions to authenticated, service_role;

revoke all on table public.empresas      from anon, authenticated;
revoke all on table public.centros_costo from anon, authenticated;

grant select on table public.empresas to authenticated;
grant update (nombre, nombre_comercial)
  on table public.empresas to authenticated;

grant select on table public.centros_costo to authenticated;
grant insert (empresa_id, padre_id, codigo, nombre)
  on table public.centros_costo to authenticated;
-- padre_id no se otorga: mover un centro cambia el alcance y es una operación
-- administrativa con service_role. El admin solo renombra o recodifica.
grant update (codigo, nombre)
  on table public.centros_costo to authenticated;
grant delete on table public.centros_costo to authenticated;
