# AppCarrousel

Núcleo técnico de la aplicación corporativa de **Carrousel**. La primera implementación se enfoca en bodegas, pero la arquitectura se diseña desde el día uno para escalar a toda la empresa sin refactorizar el core.

## Stack tecnológico

| Capa | Tecnología | Estado |
|---|---|---|
| Aplicación móvil | Flutter 3.47.9 / Dart 3.13.7, Clean Architecture, Riverpod/Bloc | Entorno instalado; implementación pendiente |
| IDE móvil | Android Studio | Instalado en `C:\Program Files\Android\Android Studio` |
| Backend y base de datos | Supabase / PostgreSQL, RLS, Realtime | En desarrollo (MT-01) |
| Backend serverless | TypeScript sobre Deno (Supabase Edge Functions) | Convención definida; scaffold pendiente |
| Tooling | pnpm 12.16.1, Supabase CLI 3.0.0, Git, GitHub CLI | Instalado |
| Mapas y geolocalización | OpenStreetMap + `flutter_map`, GPS nativo del dispositivo | Pendiente (fase móvil) |
| Distribución Android | APK directo | Pendiente (fase móvil) |

## Principios de arquitectura

- **Backend primero:** el esquema, la integridad referencial y las políticas RLS se definen antes de conectar el cliente.
- **Multiempresa lógico:** la tabla `empresas` existe desde el inicio; los datos de centros de costo y parques se inyectan después, sin hardcodearlos.
- **Jerarquía dinámica:** centros de costo auto-referenciados y parques asociados a un centro, con integridad *cross-tenant* a nivel de base de datos.
- **Seguridad en el servidor:** el rol y el alcance viven en `app_metadata` del JWT. Solo `service_role` puede escribirlos; el cliente nunca decide su rol.
- **RLS como última línea:** `anon` y `authenticated` no reciben privilegios por defecto; cada tabla otorga permisos explícitos.
- **Antifraude geográfico:** en la fase móvil se usarán coordenadas del GPS nativo y mapas sin interacción (`InteractiveFlags.none`).

## Estado del backend — MT-01

Micro-tarea: núcleo organizacional dinámico, identidad/roles y RLS base.

- [x] **0001** Bootstrap: extensiones, schema `private`, enum `rol_usuario`, helpers JWT, trigger de auditoría y endurecimiento de grants.
- [x] **0002** `empresas` + jerarquía de `centros_costo` + RLS.
- [x] **0003** `parques` + RLS.
- [x] **0004** `perfiles` + roles + RLS.
- [ ] **0005** Pruebas pgTAP de aislamiento (recomendado).
- [ ] Validación ejecutada con `supabase db reset` y JWT reales de empleado/admin.

> Estado real: el esquema base (`0001`–`0004`) está completo en código, pero **ninguna migración se ha ejecutado todavía** contra PostgreSQL/Supabase porque el entorno no tiene Docker/WSL2. Toda la validación es estática hasta que exista un entorno de base de datos.

### Aprovisionamiento de roles

El rol no se elige en el cliente. El flujo previsto es:

1. Un administrador autorizado genera una invitación con rol (`empleado` o `admin`) y alcance (`empresa_id`, `centro_costo_id`).
2. Una Edge Function con `service_role` crea el usuario en Supabase Auth y escribe esos valores en `app_metadata`.
3. El trigger de `perfiles` materializa el perfil al crear el usuario o al actualizar `app_metadata`.
4. RLS y los grants por columna impiden que el usuario modifique su rol o su alcance.

## Estado del móvil (preview)

- [x] Scaffold Flutter en `apps/mobile` (Android).
- [x] Pantalla de botones con selector Empleado/Admin y acciones simuladas.
- [x] `flutter analyze` y `flutter build apk --debug` validados.
- [ ] Conexión a Supabase Auth/Realtime.
- [ ] Gestión de estado con Riverpod/Bloc.
- [ ] `flutter_map` + GPS/geocerca.

## Historial de cambios

| Fecha | Entrega | Rama | PR | Estado | Validación |
|---|---|---|---|---|---|
| 2026-11-05 | Migración `0001` — bootstrap de extensiones y helpers de seguridad | `dgiron-2025071` | [#2](https://github.com/dgiron-2025071/AppCarrousel/pull/2) | Mergeado a `develop` | Revisión estática; `db reset` pendiente |
| 2026-11-05 | README con stack, estado y bitácora | `dgiron-2025071` | [#3](https://github.com/dgiron-2025071/AppCarrousel/pull/3) | Mergeado a `develop` | — |
| 2026-11-05 | Scaffold Flutter en `apps/mobile` | `dgiron-2025071` | [#4](https://github.com/dgiron-2025071/AppCarrousel/pull/4) | Mergeado a `develop` | `flutter analyze` OK |
| 2026-11-05 | Pantalla de botones (preview) | `dgiron-2025071` | [#5](https://github.com/dgiron-2025071/AppCarrousel/pull/5) | Mergeado a `develop` | `flutter analyze` + `flutter build apk --debug` OK |
| 2026-11-05 | README: estado del móvil y entorno | `dgiron-2025071` | [#6](https://github.com/dgiron-2025071/AppCarrousel/pull/6) | Mergeado a `develop` | — |
| 2026-11-05 | Migración `0002` — empresas y centros de costo | `dgiron-2025071` | [#7](https://github.com/dgiron-2025071/AppCarrousel/pull/7) | Mergeado a `develop` | Revisión estática; `db reset` pendiente |
| 2026-11-05 | README: registrar migración `0002` | `dgiron-2025071` | [#8](https://github.com/dgiron-2025071/AppCarrousel/pull/8) | Mergeado a `develop` | — |
| 2026-11-05 | Migración `0003` — parques y geocerca | `dgiron-2025071` | [#9](https://github.com/dgiron-2025071/AppCarrousel/pull/9) | Mergeado a `develop` | Revisión estática; `db reset` pendiente |
| 2026-11-05 | README: registrar migración `0003` | `dgiron-2025071` | [#10](https://github.com/dgiron-2025071/AppCarrousel/pull/10) | Mergeado a `develop` | — |
| 2026-11-05 | Migración `0004` — perfiles y roles | `dgiron-2025071` | [#11](https://github.com/dgiron-2025071/AppCarrousel/pull/11) | Mergeado a `develop` | Revisión estática; `db reset` pendiente |
| 2026-11-05 | README: registrar migración `0004` y cierre del esquema | `dgiron-2025071` | [#12](https://github.com/dgiron-2025071/AppCarrousel/pull/12) | Mergeado a `develop` | — |

> Nota de proceso: el PR #1 se creó como borrador y GitHub devolvió un error de GraphQL al intentar marcarlo como listo. Se cerró y se recreó como PR #2, que fue mergeado.

## Flujo Git

1. Rama de trabajo: `dgiron-2025071`.
2. Un commit atómico por archivo o entregable.
3. Push a `origin/dgiron-2025071`.
4. Pull Request hacia `develop`.
5. Merge validado a `develop`.
6. Al cerrar la micro-tarea: Pull Request de `develop` hacia `main`.

No se hace push directo a `main`. Cada merge a `develop` debe dejar la rama de trabajo sincronizada antes del siguiente entregable.

## Entorno local

| Herramienta | Versión / estado |
|---|---|
| Flutter | 3.47.9 (stable) |
| Dart | 3.13.7 |
| Android Studio | Instalado |
| Android SDK | 36 (platform 36 rev.2) |
| Android NDK | 28.2.13676358 (canal canary) |
| Emulador | `Medium_Phone_API_37.0` |
| Node.js | 22.22.3 |
| pnpm | 12.16.1 |
| Supabase CLI | 3.0.0 |
| Docker Desktop | Pendiente (requiere WSL2 y elevación) |

### Abrir el proyecto móvil

Abrir en Android Studio la carpeta `apps/mobile` (no la raíz del repo):

```text
File > Open... > C:\AppCarrousel\apps\mobile
```

### Comandos

```bash
# Backend (cuando Docker esté disponible)
supabase start
supabase db reset

# Móvil
cd apps/mobile
flutter pub get
flutter analyze
flutter build apk --debug
flutter run
```

## Siguientes pasos

1. Validar las migraciones `0001`–`0004` en un entorno PostgreSQL/Supabase real.
2. Entregar `0005`: pruebas pgTAP de aislamiento y de no autoelevación.
3. Implementar el flujo de invitación en TypeScript/Deno con `pnpm`.
4. Conectar el preview Flutter a Supabase Auth y añadir Riverpod/Bloc.
5. Integrar `flutter_map` con OpenStreetMap y GPS/geocerca.

## Seguridad

- La clave `service_role` nunca se incluye en la app móvil; solo se usa en Edge Functions o administración.
- `user_metadata` no se usa para autorización; los claims de rol y alcance viven en `app_metadata`.
- Las migraciones se versionan; no se hacen cambios manuales de esquema en el dashboard.
- Las políticas RLS y los grants se revisan antes de cada merge.
