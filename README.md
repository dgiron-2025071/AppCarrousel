# AppCarrousel

Núcleo técnico de la aplicación corporativa de **Empresa Carrousel**. La primera implementación se enfoca en bodegas, pero la arquitectura se diseña desde el día uno para escalar a toda la empresa sin refactorizar el core.

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
- [ ] **0002** `empresas` + jerarquía de `centros_costo` + RLS.
- [ ] **0003** `parques` + RLS.
- [ ] **0004** `perfiles` + roles + RLS.
- [ ] **0005** Pruebas pgTAP de aislamiento (recomendado).
- [ ] Validación ejecutada con `supabase db reset` y JWT reales de empleado/gerente.

### Aprovisionamiento de roles

El rol no se elige en el cliente. El flujo previsto es:

1. Un administrador autorizado genera una invitación con rol (`empleado` o `gerente`) y alcance (`empresa_id`, `centro_costo_id`).
2. Una Edge Function con `service_role` crea el usuario en Supabase Auth y escribe esos valores en `app_metadata`.
3. El trigger de `perfiles` materializa el perfil al primer acceso.
4. RLS y los grants por columna impiden que el usuario modifique su rol o su alcance.

## Historial de cambios

| Fecha | Entrega | Rama | PR | Estado | Validación |
|---|---|---|---|---|---|
| 2026-11-05 | Migración `0001` — bootstrap de extensiones y helpers de seguridad | `dgiron-2025071` | [#2](https://github.com/dgiron-2025071/AppCarrousel/pull/2) | Mergeado a `develop` | Revisión estática; `db reset` pendiente |
| 2026-11-05 | README con stack, estado y bitácora | `dgiron-2025071` | [#3](https://github.com/dgiron-2025071/AppCarrousel/pull/3) | Mergeado a `develop` | — |

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
| Node.js | 22.22.3 |
| pnpm | 12.16.1 |
| Supabase CLI | 3.0.0 |
| Docker Desktop | Pendiente (requiere WSL2 y elevación) |

### Comandos previstos

```bash
# Backend (cuando Docker esté disponible)
supabase init
supabase start
supabase db reset

# Móvil (fase posterior)
flutter pub get
flutter run
```

## Siguientes pasos

1. Validar la migración `0001` en un entorno PostgreSQL/Supabase real.
2. Entregar `0002`: empresas y jerarquía de centros de costo.
3. Entregar `0003`: parques corporativos.
4. Entregar `0004`: perfiles y separación de roles.
5. Implementar el flujo de invitación en TypeScript/Deno con `pnpm`.
6. Crear la pantalla de botones en Flutter para previsualizar los flujos en Android Studio.

## Seguridad

- La clave `service_role` nunca se incluye en la app móvil; solo se usa en Edge Functions o administración.
- `user_metadata` no se usa para autorización; los claims de rol y alcance viven en `app_metadata`.
- Las migraciones se versionan; no se hacen cambios manuales de esquema en el dashboard.
- Las políticas RLS y los grants se revisan antes de cada merge.
