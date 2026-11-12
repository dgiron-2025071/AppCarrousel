-- =============================================================================
-- Carrousel — Propuesta de integración con la operación actual
-- Archivo 23: centros de costo que se pueden cargar en cada lugar
-- Fecha: 2026-11-12
--
-- Los lugares de trabajo son los parques, la Oficina Central y la Bodega
-- (tabla parques, con su geocerca). Al pedir horas extras se elige el lugar
-- y luego UN centro de costo de ese lugar.
--
-- Por defecto un lugar ofrece su propio centro y sus sub-centros (ej. 057
-- Andaria → Kiddies, Cajas Mágicas, Caseta). Esta tabla agrega otros centros
-- que no cuelgan de él, como las áreas de la Oficina Central (Gerencia,
-- Auditoría, Logística…).
--
-- Depende de 0002, 0003 y 0007.
-- =============================================================================

create table public.parques_centros (
  empresa_id      uuid not null references public.empresas (id) on delete cascade,
  parque_id       uuid not null,
  centro_costo_id uuid not null,
  creado_en       timestamptz not null default now(),

  primary key (parque_id, centro_costo_id),
  constraint parques_centros_parque_fk
    foreign key (empresa_id, parque_id)
    references public.parques (empresa_id, id)
    on delete cascade,
  constraint parques_centros_centro_fk
    foreign key (empresa_id, centro_costo_id)
    references public.centros_costo (empresa_id, id)
    on delete cascade
);

comment on table public.parques_centros is
  'Centros de costo adicionales que se pueden cargar en un lugar, además del suyo y sus sub-centros.';

alter table public.parques_centros enable row level security;

create policy parques_centros_select_tenant
  on public.parques_centros
  for select
  to authenticated
  using (empresa_id = (select private.current_empresa_id()));

create policy parques_centros_escritura_admin
  on public.parques_centros
  for all
  to authenticated
  using (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_admin())
    and (select private.perfil_propio_activo())
    and private.parque_en_alcance(parque_id)
  )
  with check (
    empresa_id = (select private.current_empresa_id())
    and (select private.es_admin())
    and (select private.perfil_propio_activo())
    and private.parque_en_alcance(parque_id)
    and private.centro_en_empresa(centro_costo_id)
  );

comment on policy parques_centros_select_tenant on public.parques_centros is
  'Toda la empresa lee qué centros se cargan en cada lugar.';
comment on policy parques_centros_escritura_admin on public.parques_centros is
  'Un admin activo configura los centros de los lugares de su alcance.';

revoke all on table public.parques_centros from anon, authenticated;
grant select, delete on table public.parques_centros to authenticated;
grant insert (empresa_id, parque_id, centro_costo_id) on table public.parques_centros to authenticated;
grant select, insert, update, delete on table public.parques_centros to service_role;
