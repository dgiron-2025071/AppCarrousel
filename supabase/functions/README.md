# Edge Functions

## `invitar-usuario`

Crea un usuario en Supabase Auth mediante invitación por correo y escribe en
`app_metadata` el alcance (`empresa_id`, `centro_costo_id`) y el rol
(`empleado` o `admin`). El trigger `on_auth_user_sync_perfil` materializa
`public.perfiles`; el cliente nunca escribe esos claims.

### Reglas de seguridad

- La función se despliega con verificación de JWT activada (`verify_jwt`).
- Además, la función vuelve a validar el usuario con `auth.getUser()`.
- Solo un perfil **activo** con rol `admin` puede invitar.
- Los claims del JWT deben seguir vigentes: `rol = admin`, `empresa_id` y
  `centro_costo_id` iguales al perfil materializado. La función lee el payload
  del token ya validado por la plataforma, no el registro actual de Auth, para
  que un token emitido antes de un cambio de alcance falle cerrado. Si no
  coinciden, responde `403` y pide volver a iniciar sesión, igual que
  `private.es_admin()` en la base (`0017`).
- La empresa del admin debe seguir **activa**. La función usa `service_role`,
  que ignora RLS, así que la suspensión de la empresa (`0013`) se verifica de
  forma explícita antes de enviar la invitación.
- El centro destino debe pertenecer a la empresa del admin y estar en su
  subárbol jerárquico (`ruta` del centro). El `empresa_id` lo determina la
  función a partir del perfil del solicitante, no el cuerpo de la petición.
- Si falla la escritura de `app_metadata` con un error confirmado, el usuario
  recién invitado se borra para no dejar una cuenta sin alcance. Si la llamada
  **agotó el timeout**, no se borra: la escritura pudo haberse aplicado y se
  pide revisión manual (`504`).
- Cada llamada a Auth/PostgREST tiene un plazo de 10 s (`AUTH_TIMEOUT_MS`,
  50–60000 ms, valor por defecto 10000). Un agotamiento responde `504`, nunca
  `401` ni una reversión afirmada. El timeout se propaga como aborto para que
  `postgrest-js` no lo reintente con backoff.
- No se usa `user_metadata` para autorización.

### Cuerpo de la petición

```json
{
  "email": "especialista@empresa.com",
  "nombre_completo": "Nombre Apellido",
  "rol": "empleado",
  "centro_costo_id": "00000000-0000-0000-0000-000000000000"
}
```

### Despliegue

```bash
supabase login
supabase link --project-ref <project-ref>
supabase functions deploy invitar-usuario
supabase secrets set APP_REDIRECT_URL=io.supabase.carrousel://login-callback
```

También se puede desplegar sin CLI local con el workflow manual
`Despliegue de Edge Function` (`.github/workflows/deploy-edge-function.yml`).
Requiere los secrets de repositorio `SUPABASE_ACCESS_TOKEN` y
`SUPABASE_DB_PASSWORD`, y dos inputs al ejecutarlo: `project_ref` y
`redirect_url`. El flujo usa `supabase/setup-cli@v3` con la CLI 3.0.0, enlaza el
proyecto, despliega `invitar-usuario` con verificación de JWT activada y escribe
`APP_REDIRECT_URL`. No versiona tokens ni URLs de un proyecto real.

El redirect debe estar autorizado en `Authentication > URL Configuration`.
La función usa `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` y
`SUPABASE_ANON_KEY`, que Supabase inyecta automáticamente en el entorno de la
función. `AUTH_TIMEOUT_MS` es opcional (10000 por defecto); para cambiarlo en
producción, añádelo con `supabase secrets set AUTH_TIMEOUT_MS=10000`.

### Invocación

Con la sesión de un administrador:

```bash
curl -X POST "https://<project-ref>.supabase.co/functions/v1/invitar-usuario" \
  -H "Authorization: Bearer <access-token-del-admin>" \
  -H "apikey: <anon-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "especialista@empresa.com",
    "nombre_completo": "Nombre Apellido",
    "rol": "empleado",
    "centro_costo_id": "<uuid-del-centro>"
  }'
```

Respuesta `201`:

```json
{
  "id": "<uuid>",
  "email": "especialista@empresa.com",
  "rol": "empleado",
  "empresa_id": "<uuid>",
  "centro_costo_id": "<uuid>",
  "nombre_completo": "Nombre Apellido",
  "invitacion_enviada": true
}
```

### Validación local

Verificación estática:

```bash
npx -y deno check supabase/functions/invitar-usuario/index.ts
npx -y deno lint supabase/functions/invitar-usuario/index.ts
npx -y deno fmt --check supabase/functions/invitar-usuario/index.ts
```

Pruebas de integración (no requieren credenciales ni Docker):

```bash
npx -y deno test -A supabase/functions/tests/invitar_usuario_test.ts
```

El arnés levanta un servidor HTTP que emula los endpoints de Supabase Auth y
PostgREST usados por la función, arranca `invitar-usuario` como subproceso en un
puerto libre (`PORT`) y verifica **47 escenarios**, con una segunda instancia en
`AUTH_TIMEOUT_MS=300` para las pruebas de plazo agotado:

- CORS, método distinto de `POST` y ausencia o invalidez de la sesión.
- Perfil inexistente, inactivo, con rol distinto de `admin` o con error de
  consulta.
- Claims del token degradados o desalineados con el perfil (`rol`, `empresa_id`
  o `centro_costo_id`), token sin forma de JWT o emitido para otro usuario, sin
  enviar la invitación.
- El payload del token manda sobre el registro actual de Auth: un token viejo no
  hereda el alcance nuevo del perfil y un registro desalineado no invalida un
  token correcto.
- Empresa suspendida o inexistente (`403`) y error al consultarla (`500`), sin
  enviar la invitación.
- Validaciones de JSON, correo (sin caracteres de control y normalizado a NFC),
  nombre, rol y UUID del centro.
- Centro de otra empresa, centro fuera del subárbol y error al consultarlo.
- Invitación exitosa de `empleado` y de `admin`, comprobando que
  `empresa_id` sale del perfil del solicitante y no del cuerpo.
- Correo ya registrado (`409`). Si GoTrue crea el usuario pero falla el correo
  (`502`), se recorren todas las páginas de `listUsers` siguiendo `nextPage`,
  con un techo duro de 20 páginas: al agotarlo se falla cerrado en vez de
  afirmar que no había huérfana. Solo se borra la cuenta del mismo correo,
  creada en los últimos 10 minutos y sin `app_metadata.empresa_id`; un usuario
  con claims nunca se toca. Si falla el listado, la paginación o el borrado,
  responde `500` (o `504` si agotó el plazo) con un mensaje distinto y registra
  una alerta, sin afirmar que se limpió nada.
- Error al escribir `app_metadata`: responde `500` y borra el usuario invitado
  (rollback verificado). Si el borrado también falla, responde `500` con un
  mensaje distinto y registra una alerta, sin afirmar que se revirtió.
- Timeouts (`504`): sesión, perfil, invitación, búsqueda de huérfanas, escritura
  de `app_metadata` y reversión. Un timeout al escribir claims **no** borra al
  usuario, porque la escritura pudo haberse aplicado; se pide revisar Auth. El
  arnés verifica que un timeout no se reintenta con backoff (una sola petición).
- Acepta espacios circundantes en `rol` y `centro_costo_id`.

Las consultas de perfil y centro usan `.limit(1)` en lugar de `.maybeSingle()`
para que el contrato con PostgREST sea explícito y no dependa de códigos
`406/PGRST116`.

El workflow manual `.github/workflows/deploy-edge-function.yml` ejecuta primero
`deno check`, `deno lint`, `deno fmt --check` y `deno test -A` en un job
`validar`; el despliegue depende de él (`needs: [validar]`), así que no publica
código que no haya pasado la validación.

El despliegue y la prueba contra un proyecto Supabase real quedan pendientes de
credenciales; no se versionan claves ni tokens.

> `supabase/config.toml` tampoco se versiona: se copia desde
> `supabase/config.toml.example`. Los comandos de la CLI que lo requieren
> (`supabase start`, `supabase functions serve` y `supabase db reset`) necesitan
> ese config local o el del proyecto enlazado. El arnés de base de datos, las
> pruebas Deno y la CI no lo usan.
