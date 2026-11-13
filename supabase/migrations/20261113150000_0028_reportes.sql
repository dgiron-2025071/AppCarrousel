-- =============================================================================
-- Carrousel — Núcleo backend
-- MT-02 / Archivo 28: reportes de horas extras y cumplimiento de jornadas
-- Fecha: 2026-11-13
--
-- Crea:
--   1. public.reporte_horas_extras   — solicitudes con empleado, centro, lugar,
--      horas y revisor.
--   2. public.cumplimiento_jornadas  — jornadas con horario, minutos de
--      diferencia e incidencias.
--
-- Decisión:
--   Ambas son vistas `security_invoker`: la RLS de las tablas base se aplica
--   con el usuario que consulta. No se crea una vista con privilegios elevados
--   que pudiera filtrar datos de otra empresa o de otro subárbol. La app puede
--   exportar el resultado a CSV sin lógica de permisos propia.
--
-- Depende de 0006/0018/0026 (solicitudes y lugar), 0015/0027 (jornadas e
-- incidencias) y 0024 (horarios y zona horaria).
--
-- Ejecución local: supabase db reset
-- Nota: el CLI de Supabase aplica cada migración dentro de una transacción.
-- No se incluye BEGIN/COMMIT explícito para evitar transacciones anidadas.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Reporte de horas extras
-- -----------------------------------------------------------------------------
create view public.reporte_horas_extras
with (security_invoker = true)
as
select
  s.id,
  s.empresa_id,
  s.empleado_id,
  p.nombre_completo                     as empleado,
  p.centro_costo_id                     as empleado_centro_costo_id,
  s.centro_costo_id,
  c.codigo                              as centro_codigo,
  c.nombre                              as centro_nombre,
  s.parque_id,
  pa.nombre                             as parque_nombre,
  s.inicio,
  s.fin,
  round(extract(epoch from (s.fin - s.inicio)) / 3600.0, 2) as horas,
  s.estado,
  s.comentario_admin,
  s.revisado_por,
  r.nombre_completo                     as revisor,
  s.revisado_en,
  s.creado_en
from public.solicitudes_horas_extras s
join public.perfiles p          on p.id = s.empleado_id
join public.centros_costo c     on c.id = s.centro_costo_id
left join public.parques pa     on pa.id = s.parque_id
left join public.perfiles r     on r.id = s.revisado_por;

comment on view public.reporte_horas_extras is
  'Solicitudes de horas extras con empleado, centro, lugar, horas y revisor. Respeta la RLS de las tablas base (security_invoker).';

revoke all on public.reporte_horas_extras from anon, authenticated;
grant select on public.reporte_horas_extras to authenticated;

-- -----------------------------------------------------------------------------
-- 2. Cumplimiento de jornadas
-- -----------------------------------------------------------------------------
create view public.cumplimiento_jornadas
with (security_invoker = true)
as
select
  j.id,
  j.empresa_id,
  j.empleado_id,
  p.nombre_completo                     as empleado,
  j.parque_id,
  pa.nombre                             as parque_nombre,
  e.zona_horaria,
  j.entrada_en,
  j.salida_en,
  (j.salida_en is null)                 as abierta,
  round(
    extract(epoch from (coalesce(j.salida_en, now()) - j.entrada_en)) / 3600.0,
    2
  )                                     as horas,
  h.hora_entrada,
  h.hora_salida,
  h.tolerancia_entrada_min,
  h.tolerancia_salida_min,
  case
    when h.hora_entrada is null then null
    else ((j.entrada_en at time zone e.zona_horaria)::date + h.hora_entrada)
           at time zone e.zona_horaria
  end                                   as entrada_programada,
  case
    when h.hora_salida is null then null
    when h.hora_salida <= h.hora_entrada then
      (((j.entrada_en at time zone e.zona_horaria)::date + h.hora_salida)
        at time zone e.zona_horaria) + interval '1 day'
    else
      ((j.entrada_en at time zone e.zona_horaria)::date + h.hora_salida)
        at time zone e.zona_horaria
  end                                   as salida_programada,
  case
    when h.hora_entrada is null then null
    else greatest(
      0,
      floor(
        extract(epoch from (
          j.entrada_en
          - (((j.entrada_en at time zone e.zona_horaria)::date + h.hora_entrada)
              at time zone e.zona_horaria)
        )) / 60
      )::integer
    )
  end                                   as minutos_tarde,
  case
    when h.hora_salida is null or j.salida_en is null then null
    else greatest(
      0,
      floor(
        extract(epoch from (
          (case
             when h.hora_salida <= h.hora_entrada then
               (((j.entrada_en at time zone e.zona_horaria)::date + h.hora_salida)
                 at time zone e.zona_horaria) + interval '1 day'
             else
               ((j.entrada_en at time zone e.zona_horaria)::date + h.hora_salida)
                 at time zone e.zona_horaria
           end)
          - j.salida_en
        )) / 60
      )::integer
    )
  end                                   as minutos_temprano,
  coalesce(inc.total, 0)                as incidencias_total,
  inc.tipos                             as incidencias
from public.jornadas j
join public.perfiles p      on p.id = j.empleado_id
join public.empresas e      on e.id = j.empresa_id
left join public.parques pa on pa.id = j.parque_id
left join public.horarios h
  on h.empleado_id = j.empleado_id
 and h.activo
 and h.dia_semana =
     extract(isodow from (j.entrada_en at time zone e.zona_horaria))::smallint
left join lateral (
  select
    count(*)::integer                          as total,
    array_agg(i.tipo::text order by i.tipo::text) as tipos
  from public.incidencias_jornada i
  where i.jornada_id = j.id
) inc on true;

comment on view public.cumplimiento_jornadas is
  'Jornadas con horario programado, minutos de llegada tarde/salida temprana e incidencias. Respeta la RLS (security_invoker).';

revoke all on public.cumplimiento_jornadas from anon, authenticated;
grant select on public.cumplimiento_jornadas to authenticated;
