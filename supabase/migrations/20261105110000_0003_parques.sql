-- =============================================================================
-- Empresa Carrousel — Núcleo backend
-- MT-01 / Archivo 03: parques corporativos y geocerca
-- Fecha: 2026-11-05
--
-- Crea:
--   1. public.parques          — parque asociado a un centro de costo.
--   2. Integridad cross-tenant — el centro debe pertenecer a la misma empresa.
--   3. Geocerca                — coordenadas y radio validados en base de datos.
--   4. Alcance jerárquico      — helper private.centro_en_alcance().
--   5. RLS y grants explícitos — lectura por alcance; escritura solo gerente.
--
-- Depende de 0002: public.empresas y public.centros_costo (con unique
-- (empresa_id, id) para la FK compuesta).
--
-- Ejecución local: supabase db reset
-- Nota: el CLI de Supabase aplica cada migración dentro de una transacción.
-- No se incluye BEGIN/COMMIT explícito para evitar transacciones anidadas.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Helper de alcance jerárquico
-- -----------------------------------------------------------------------------
-- Un centro está en alcance si es el centro del JWT o un descendiente suyo.
-- El centro del JWT se identifica por app_metadata.centro_costo_id. Sin claim
-- válido o sin coincidencia de empresa, devuelve FALSE (fail-closed).
--
-- SECURITY INVOKER: la lectura de centros_costo queda sujeta a su propia RLS,
-- que ya limita por empresa. La condición de empresa se repite aquí de forma
-- explícita para no depender solo de la RLS de la tabla consultada.
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

revoke all on function private.centro_en_alcance(uuid) from public;
grant execute on function private.centro_en_alcance(uuid) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 2. Parques
-- -----------------------------------------------------------------------------
create table public.parques (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas (id) on delete restrict,
  centro_costo_id uuid not null,
  codigo          extensions.citext not null,
  nombre          extensions.citext not null,
  direccion       text,
  latitud         double precision not null,
  longitud        double precision not null,
  radio_metros    integer not null default 100,
  activo          boolean not null default true,
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now(),
  actualizado_por uuid references auth.users (id) on delete set null,

  constraint parques_empresa_codigo_key unique (empresa_id, codigo),
  -- FK compuesta: el centro debe existir en la misma empresa. Evita que un
  -- parque quede asociado a un centro de otra empresa.
  constraint parques_centro_fk
    foreign key (empresa_id, centro_costo_id)
    references public.centros_costo (empresa_id, id)
    on delete restrict,
  constraint parques_latitud_valida
    check (latitud between -90 and 90),
  constraint parques_longitud_valida
    check (longitud between -180 and 180),
  constraint parques_radio_valido
    check (radio_metros between 1 and 10000)
);

comment on table public.parques is
  'Parques operativos asociados a un centro de costo. Incluyen geocerca para el marcaje móvil.';
comment on column public.parques.radio_metros is
  'Radio de la geocerca en metros. El GPS del dispositivo se valida contra este valor.';
comment on column public.parques.activo is
  'Un parque inactivo se conserva por historial pero no debería aceptar marcajes.';

create index parques_empresa_centro_idx
  on public.parques (empresa_id, centro_costo_id);

create trigger parques_auditoria
before update on public.parques
for each row execute function private.set_actualizado_en();

-- -----------------------------------------------------------------------------
-- 3. RLS: parques
-- -----------------------------------------------------------------------------
alter table public.parques enable row level security;

create policy parques_select_alcance
  on public.parques
  for select
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and private.centro_en_alcance(centro_costo_id)
  );

create policy parques_insert_gerente
  on public.parques
  for insert
  to authenticated
  with check (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_gerente())
    and private.centro_en_alcance(centro_costo_id)
  );

create policy parques_update_gerente
  on public.parques
  for update
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_gerente())
    and private.centro_en_alcance(centro_costo_id)
  )
  with check (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_gerente())
    and private.centro_en_alcance(centro_costo_id)
  );

create policy parques_delete_gerente
  on public.parques
  for delete
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_gerente())
    and private.centro_en_alcance(centro_costo_id)
  );

comment on policy parques_select_alcance on public.parques is
  'Lectura limitada a los parques del centro del JWT y sus descendientes.';
comment on policy parques_insert_gerente on public.parques is
  'Alta de parques solo por gerente y dentro de su alcance.';
comment on policy parques_update_gerente on public.parques is
  'Edición de parques solo por gerente y dentro de su alcance; no puede moverlos fuera.';
comment on policy parques_delete_gerente on public.parques is
  'Baja de parques solo por gerente y dentro de su alcance.';

-- -----------------------------------------------------------------------------
-- 4. Grants explícitos
-- -----------------------------------------------------------------------------
-- anon no recibe nada. El cliente no escribe timestamps ni actualizado_por.
revoke all on table public.parques from anon, authenticated;

grant select on table public.parques to authenticated;
grant insert (
  empresa_id,
  centro_costo_id,
  codigo,
  nombre,
  direccion,
  latitud,
  longitud,
  radio_metros,
  activo
) on table public.parques to authenticated;
grant update (
  centro_costo_id,
  codigo,
  nombre,
  direccion,
  latitud,
  longitud,
  radio_metros,
  activo
) on table public.parques to authenticated;
grant delete on table public.parques to authenticated;
