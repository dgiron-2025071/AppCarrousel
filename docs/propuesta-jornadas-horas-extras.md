# Propuesta: jornadas, horas extras y operación de Carrousel

Propuesta de Fernando ZL para conectar la app con la forma en que hoy se trabaja en Carrousel. Está montada sobre `develop` (hasta el PR #42) y respeta las decisiones de seguridad de MT-01: RLS como última línea, rol y alcance solo en `app_metadata`, historial con `ON DELETE RESTRICT` y la geocerca congelada al entrar.

## De dónde sale

| Fuente | Qué se tomó |
|---|---|
| Formulario Google "Formato de horas Extras (mantenimiento)" | Campos de la solicitud: técnico, fecha, actividad realizada, cantidad de horas, centro de costo y persona que autoriza. |
| `control-jornadas-carrousel` (PHP) | Registro con asignación pendiente, incidencias, ajustes de jornada con motivo, puestos y jefe de área. |
| `caja-chica-carrousel` | Catálogo real de centros de costo (CECO) y su jerarquía. |
| `carrousel-app` | Coordenadas de los parques para las geocercas. |
| Ecosistema Carrousel v1.5.0 | Paleta, franja de marca, modo claro/oscuro y acceso de doble panel. |

## Migraciones (0018–0023)

| # | Qué agrega |
|---|---|
| 0018 | Catálogo de puestos; el puesto llega en `app_metadata.puesto_id`. |
| 0019 | Jefe responsable por centro y "persona que autoriza" calculada desde la jerarquía (ya no se escribe a mano). |
| 0020 | Vista `reporte_horas_extras` con las columnas del formulario (respeta RLS). |
| 0021 | Zona horaria por empresa, horario personalizado por empleado y vista de cumplimiento: tardanza y minutos extra respaldados por la geocerca. La solicitud puede quedar ligada a su jornada GPS. |
| 0022 | Registro propio con código de empresa (pendiente hasta que un admin asigna centro y puesto), incidencias automáticas (llegada tarde, salida temprana, parque distinto, GPS impreciso) y ajustes de jornada con historial. |
| 0023 | Centros de costo adicionales por lugar (por ejemplo, las áreas de la Oficina Central). |

Ninguna redefine funciones de 0012–0017. La única política que se reemplaza es `solicitudes_insert_propia` (0021), para aceptar `jornada_id` propio y cerrado; conserva todas las condiciones anteriores.

## App

- **Empleado:** horario de hoy, horas extra detectadas por GPS con solicitud precargada, formulario de horas extras igual al de Google con "Lugar → Centro de costo".
- **Admin (pestaña Equipo):** indicadores del equipo, registros pendientes, incidencias, jornadas y ajustes, horarios por persona, lugares con geocerca (crear, editar, eliminar o desactivar), catálogo de centros de costo y reporte CSV.
- **Web:** la misma app compila para navegador (`flutter build web`), con menú lateral en pantallas anchas, para no obligar a usar el celular.

## Herramienta para los CECO

`tools/importar-ceco` normaliza el listado de caja chica (057.01, 057-01 y 05701 son el mismo hijo de 057), crea el parque principal cuando solo vienen sus sub-centros y genera SQL idempotente. El listado con datos reales no se versiona.

Hallazgos en los datos de caja chica:

- 78 códigos repetidos con nombres distintos (por ejemplo, 003.01 "Metro Norte Kiddies" y "Kiddies Metronorte").
- Sub-centros sin parque principal (060, 061, 063–066, 068, 069, 074).

## Pruebas

```bash
pnpm --dir tools/db-validation test        # 279 OK
node --test tools/importar-ceco/           # 11 OK
cd apps/mobile && flutter analyze && flutter test   # 53 OK
```

## Para decidir

1. Si la aprobación de horas extras debe quedar solo en manos del autorizador calculado o, como hoy, de cualquier admin del subárbol.
2. Los técnicos de mantenimiento rotan por parques: necesitan alcance en la raíz o en su región para marcar.
3. Coordenadas reales de la Oficina Central y la Bodega.
4. Google en la versión web necesita el redirect del dominio donde se publique.
