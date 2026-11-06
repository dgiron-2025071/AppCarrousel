-- =============================================================================
-- Carrousel — Núcleo backend
-- MT-01 / Archivo 03: parques corporativos y geocerca
-- Fecha: 2026-11-05
--
-- Crea:
--   1. public.parques          — parque asociado a un centro de costo.
--   2. Integridad cross-tenant — el centro debe pertenecer a la misma empresa.
--   3. Geocerca                — coordenadas y radio validados en base de datos.
--   4. RLS y grants explícitos — lectura por alcance; escritura solo admin.
--
-- Depende de 0002: public.empresas, public.centros_costo (con unique
-- (empresa_id, id) para la FK compuesta) y el helper
-- private.centro_en_alcance().
--
-- Ejecución local: supabase db reset
-- Nota: el CLI de Supabase aplica cada migración dentro de una transacción.
-- No se incluye BEGIN/COMMIT explícito para evitar transacciones anidadas.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Parques
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
-- 2. RLS: parques
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

create policy parques_insert_admin
  on public.parques
  for insert
  to authenticated
  with check (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_admin())
    and private.centro_en_alcance(centro_costo_id)
  );

create policy parques_update_admin
  on public.parques
  for update
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_admin())
    and private.centro_en_alcance(centro_costo_id)
  )
  with check (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_admin())
    and private.centro_en_alcance(centro_costo_id)
  );

create policy parques_delete_admin
  on public.parques
  for delete
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_admin())
    and private.centro_en_alcance(centro_costo_id)
  );

comment on policy parques_select_alcance on public.parques is
  'Lectura limitada a los parques del centro del JWT y sus descendientes.';
comment on policy parques_insert_admin on public.parques is
  'Alta de parques solo por admin y dentro de su alcance.';
comment on policy parques_update_admin on public.parques is
  'Edición de parques solo por admin y dentro de su alcance; no puede moverlos fuera.';
comment on policy parques_delete_admin on public.parques is
  'Baja de parques solo por admin y dentro de su alcance.';

-- -----------------------------------------------------------------------------
-- 3. Grants explícitos
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
