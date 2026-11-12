-- =============================================================================
-- Carrousel — Propuesta de integración con la operación actual
-- Archivo 20: reporte de horas extras
-- Fecha: 2026-11-11
--
-- Vista con las columnas del formulario "Formato de horas Extras" que se usa
-- hoy (técnico, fecha, actividad realizada, cantidad de horas, centro de
-- costo y persona que autoriza), más el estado de la aprobación.
--
-- security_invoker: la vista respeta el RLS de quien consulta. El empleado ve
-- sus filas; el admin activo, las de su subárbol. No abre ningún acceso nuevo.
--
-- Depende de 0006, 0018 y 0019.
-- =============================================================================

create view public.reporte_horas_extras
with (security_invoker = true)
as
select
  s.id,
  s.empresa_id,
  s.empleado_id,
  pe.nombre_completo::text                                   as empleado,
  pu.nombre::text                                            as puesto,
  s.inicio,
  s.fin,
  round((extract(epoch from (s.fin - s.inicio)) / 3600.0)::numeric, 2)
                                                             as horas,
  s.justificacion                                            as actividad_realizada,
  c.codigo::text                                             as ceco_codigo,
  c.nombre::text                                             as ceco_nombre,
  s.autorizador_nombre                                       as persona_que_autoriza,
  s.estado,
  rv.nombre_completo::text                                   as revisado_por,
  s.revisado_en,
  s.comentario_admin,
  s.creado_en
from public.solicitudes_horas_extras s
join public.perfiles pe on pe.id = s.empleado_id
left join public.puestos pu on pu.id = pe.puesto_id
join public.centros_costo c on c.id = s.centro_costo_id
left join public.perfiles rv on rv.id = s.revisado_por;

comment on view public.reporte_horas_extras is
  'Horas extras con las columnas del formulario actual. Respeta el RLS de quien consulta (security_invoker).';

revoke all on table public.reporte_horas_extras from anon, authenticated;
grant select on table public.reporte_horas_extras to authenticated;
