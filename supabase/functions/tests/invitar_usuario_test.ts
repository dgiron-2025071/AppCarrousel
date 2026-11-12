// =============================================================================
// Carrousel — Pruebas de integración de la Edge Function `invitar-usuario`
//
// Levanta un servidor HTTP que emula los endpoints de Supabase Auth y PostgREST
// que usa la función, arranca `invitar-usuario` como subproceso y verifica el
// contrato completo: CORS, método, sesión, validaciones, alcance jerárquico,
// invitación, escritura de claims y rollback.
//
// Ejecución:
//   npx -y deno test -A supabase/functions/tests/invitar_usuario_test.ts
//
// No se necesitan credenciales reales ni Docker: el servidor falso responde en
// 127.0.0.1 y la función se ejecuta con `--no-check` para no repetir el type
// check en cada corrida (se valida aparte con `deno check`).
// =============================================================================

const ADMIN_ID = "11111111-1111-4111-8111-111111111111";
const OTRO_ID = "99999999-9999-4999-8999-999999999999";
const EMPRESA_ID = "22222222-2222-4222-8222-222222222222";
const EMPRESA_OTRA = "33333333-3333-4333-8333-333333333333";
const CENTRO_ADMIN = "44444444-4444-4444-8444-444444444444";
const CENTRO_HIJO = "55555555-5555-4555-8555-555555555555";
const CENTRO_FUERA = "66666666-6666-4666-8666-666666666666";
const INVITADO_ID = "77777777-7777-4777-8777-777777777777";
const REDIRECT = "io.supabase.carrousel://login-callback";

interface PerfilFalso {
  empresa_id: string;
  centro_costo_id: string;
  rol: string;
  activo: boolean;
}

interface CentroFalso {
  id: string;
  empresa_id: string;
  ruta: string[];
}

interface EmpresaFalso {
  activa: boolean;
}

interface ErrorFalso {
  status: number;
  message: string;
}

interface PeticionRegistrada {
  method: string;
  pathname: string;
  search: string;
  body: string;
}

interface EstadoFalso {
  sesionValida: boolean;
  appMetadata: Record<string, unknown>;
  appMetadataUsuario: Record<string, unknown>;
  perfil: PerfilFalso | null;
  perfilError: boolean;
  empresa: EmpresaFalso | null;
  empresaError: boolean;
  centro: CentroFalso | null;
  centroError: boolean;
  invitacionError: ErrorFalso | null;
  claimsError: boolean;
  usuarioInvitadoId: string;
  peticiones: PeticionRegistrada[];
  usuariosEliminados: string[];
}

const CUERPO_VALIDO = {
  email: "nuevo@empresa.com",
  nombre_completo: "Nuevo Empleado",
  rol: "empleado",
  centro_costo_id: CENTRO_HIJO,
};

function estadoInicial(): EstadoFalso {
  return {
    sesionValida: true,
    appMetadata: {
      empresa_id: EMPRESA_ID,
      centro_costo_id: CENTRO_ADMIN,
      rol: "admin",
    },
    // Registro actual del usuario en Auth. Puede diferir de los claims del
    // token cuando la sesión quedó vieja; la función debe usar el token.
    appMetadataUsuario: {
      empresa_id: EMPRESA_ID,
      centro_costo_id: CENTRO_ADMIN,
      rol: "admin",
    },
    perfil: {
      empresa_id: EMPRESA_ID,
      centro_costo_id: CENTRO_ADMIN,
      rol: "admin",
      activo: true,
    },
    perfilError: false,
    empresa: { activa: true },
    empresaError: false,
    centro: {
      id: CENTRO_HIJO,
      empresa_id: EMPRESA_ID,
      ruta: [CENTRO_ADMIN],
    },
    centroError: false,
    invitacionError: null,
    claimsError: false,
    usuarioInvitadoId: INVITADO_ID,
    peticiones: [],
    usuariosEliminados: [],
  };
}

let estado: EstadoFalso = estadoInicial();

function responder(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function base64url(texto: string): string {
  return btoa(texto)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function jwtFalso(
  appMetadata: Record<string, unknown>,
  sub = ADMIN_ID,
): string {
  const cabecera = base64url(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const payload = base64url(JSON.stringify({
    sub,
    exp: Math.floor(Date.now() / 1000) + 3600,
    app_metadata: appMetadata,
  }));
  return `${cabecera}.${payload}.firma-falsa`;
}

async function manejador(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const body = await req.text();
  estado.peticiones.push({
    method: req.method,
    pathname: url.pathname,
    search: url.search,
    body,
  });

  if (url.pathname === "/auth/v1/user") {
    if (!estado.sesionValida) {
      return responder({ message: "invalid JWT: token is expired" }, 401);
    }
    return responder({
      id: ADMIN_ID,
      email: "admin@empresa.com",
      app_metadata: estado.appMetadataUsuario,
    });
  }

  if (url.pathname === "/rest/v1/perfiles") {
    if (estado.perfilError) {
      return responder({ message: "fallo al consultar perfiles" }, 500);
    }
    return responder(estado.perfil ? [estado.perfil] : []);
  }

  if (url.pathname === "/rest/v1/empresas") {
    if (estado.empresaError) {
      return responder({ message: "fallo al consultar empresas" }, 500);
    }
    return responder(estado.empresa ? [estado.empresa] : []);
  }

  if (url.pathname === "/rest/v1/centros_costo") {
    if (estado.centroError) {
      return responder({ message: "fallo al consultar centros" }, 500);
    }
    return responder(estado.centro ? [estado.centro] : []);
  }

  if (url.pathname === "/auth/v1/invite" && req.method === "POST") {
    if (estado.invitacionError) {
      return responder(
        { message: estado.invitacionError.message },
        estado.invitacionError.status,
      );
    }
    const { email } = JSON.parse(body) as { email?: string };
    return responder({
      user: { id: estado.usuarioInvitadoId, email: email ?? null },
    });
  }

  const usuarioAdmin = url.pathname.match(
    /^\/auth\/v1\/admin\/users\/([^/]+)$/,
  );
  if (usuarioAdmin) {
    const id = usuarioAdmin[1];
    if (req.method === "GET") {
      return responder({ id });
    }
    if (req.method === "PUT") {
      if (estado.claimsError) {
        return responder({ message: "fallo al escribir app_metadata" }, 500);
      }
      const atributos = JSON.parse(body) as Record<string, unknown>;
      return responder({ id, ...atributos });
    }
    if (req.method === "DELETE") {
      estado.usuariosEliminados.push(id);
      return responder({});
    }
  }

  return responder({
    message: `ruta no emulada: ${req.method} ${url.pathname}`,
  }, 404);
}

function assert(condicion: unknown, mensaje: string): asserts condicion {
  if (!condicion) throw new Error(mensaje);
}

function assertEquals<T>(
  actual: T,
  esperado: T,
  mensaje = "Valores distintos",
) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(esperado);
  if (a !== e) throw new Error(`${mensaje}: esperado ${e}, recibido ${a}`);
}

function puertoLibre(): number {
  const listener = Deno.listen({ hostname: "127.0.0.1", port: 0 });
  const { port } = listener.addr as Deno.NetAddr;
  listener.close();
  return port;
}

function rutaFuncion(): string {
  const url = new URL("../invitar-usuario/index.ts", import.meta.url);
  return decodeURIComponent(url.pathname).replace(/^\/([A-Za-z]:)/, "$1");
}

interface Falso {
  url: string;
  detener: () => Promise<void>;
}

function iniciarFalso(): Promise<Falso> {
  let resolver!: (url: string) => void;
  const listo = new Promise<string>((resolve) => {
    resolver = resolve;
  });
  const servidor = Deno.serve({
    hostname: "127.0.0.1",
    port: 0,
    onListen: (addr) => {
      resolver(`http://127.0.0.1:${(addr as Deno.NetAddr).port}`);
    },
  }, manejador);

  return listo.then((url) => ({
    url,
    detener: async () => {
      await servidor.shutdown();
    },
  }));
}

interface Funcion {
  base: string;
  detener: () => Promise<void>;
}

async function iniciarFuncion(supabaseUrl: string): Promise<Funcion> {
  const port = puertoLibre();
  const proceso = new Deno.Command(Deno.execPath(), {
    args: ["run", "--allow-all", "--no-check", rutaFuncion()],
    env: {
      SUPABASE_URL: supabaseUrl,
      SUPABASE_SERVICE_ROLE_KEY: "service-role-key",
      SUPABASE_ANON_KEY: "anon-key",
      APP_REDIRECT_URL: REDIRECT,
      PORT: String(port),
    },
    stdout: "piped",
    stderr: "piped",
  }).spawn();

  let salida = "";
  const leer = async (stream: ReadableStream<Uint8Array>) => {
    const decoder = new TextDecoder();
    for await (const chunk of stream) {
      salida += decoder.decode(chunk, { stream: true });
    }
  };
  const lecturas = [leer(proceso.stdout), leer(proceso.stderr)];
  let terminado = false;
  const esperaEstado = proceso.status.then((status) => {
    terminado = true;
    return status;
  });

  const base = `http://127.0.0.1:${port}`;
  for (let intento = 0; intento < 200; intento++) {
    if (terminado) break;
    try {
      const res = await fetch(base, { method: "GET" });
      if (res.status === 405) {
        return {
          base,
          detener: async () => {
            proceso.kill();
            await esperaEstado;
            await Promise.allSettled(lecturas);
          },
        };
      }
    } catch {
      // La función todavía no escucha; se reintenta.
    }
    await new Promise((resolve) => setTimeout(resolve, 50));
  }

  proceso.kill();
  await esperaEstado;
  await Promise.allSettled(lecturas);
  throw new Error(`La Edge Function no arrancó.\nSalida:\n${salida}`);
}

interface Invocacion {
  authorization?: string | null;
  body?: unknown;
  rawBody?: string;
  method?: string;
}

interface RespuestaInvocada {
  status: number;
  json: Record<string, unknown> | null;
  texto: string;
}

async function invocar(
  base: string,
  opciones: Invocacion = {},
): Promise<RespuestaInvocada> {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };
  if (opciones.authorization !== null) {
    headers.Authorization = opciones.authorization ??
      `Bearer ${jwtFalso(estado.appMetadata)}`;
  }
  const body = opciones.rawBody ??
    (opciones.body === undefined ? undefined : JSON.stringify(opciones.body));

  const res = await fetch(base, {
    method: opciones.method ?? "POST",
    headers,
    body,
  });
  const texto = await res.text();
  let json: Record<string, unknown> | null = null;
  try {
    json = texto ? JSON.parse(texto) as Record<string, unknown> : null;
  } catch {
    json = null;
  }
  return { status: res.status, json, texto };
}

function peticion(metodo: string, pathname: string): PeticionRegistrada {
  const encontrada = estado.peticiones.find((p) =>
    p.method === metodo && p.pathname === pathname
  );
  assert(encontrada, `No se registró ${metodo} ${pathname}`);
  return encontrada;
}

Deno.test({
  name: "invitar-usuario",
  sanitizeOps: false,
  sanitizeResources: false,
  async fn(t) {
    const falso = await iniciarFalso();
    const funcion = await iniciarFuncion(falso.url);
    try {
      await t.step("CORS preflight sin sesión", async () => {
        estado = estadoInicial();
        const res = await fetch(funcion.base, { method: "OPTIONS" });
        assertEquals(res.status, 200);
        assertEquals(res.headers.get("access-control-allow-origin"), "*");
        assertEquals(await res.text(), "ok");
      });

      await t.step("método distinto de POST", async () => {
        estado = estadoInicial();
        const res = await invocar(funcion.base, { method: "GET" });
        assertEquals(res.status, 405);
        assertEquals(res.json, { error: "Método no permitido." });
      });

      await t.step("sin cabecera Authorization", async () => {
        estado = estadoInicial();
        const res = await invocar(funcion.base, {
          authorization: null,
          body: CUERPO_VALIDO,
        });
        assertEquals(res.status, 401);
        assertEquals(res.json, { error: "Falta la sesión del administrador." });
      });

      await t.step("sesión inválida o expirada", async () => {
        estado = estadoInicial();
        estado.sesionValida = false;
        const res = await invocar(funcion.base, { body: CUERPO_VALIDO });
        assertEquals(res.status, 401);
        assertEquals(res.json, { error: "Sesión inválida o expirada." });
      });

      await t.step("perfil inexistente", async () => {
        estado = estadoInicial();
        estado.perfil = null;
        const res = await invocar(funcion.base, { body: CUERPO_VALIDO });
        assertEquals(res.status, 403);
        assertEquals(res.json, {
          error: "Solo un administrador activo puede invitar usuarios.",
        });
      });

      await t.step("perfil con rol empleado", async () => {
        estado = estadoInicial();
        assert(estado.perfil, "El perfil de prueba debe existir");
        estado.perfil.rol = "empleado";
        const res = await invocar(funcion.base, { body: CUERPO_VALIDO });
        assertEquals(res.status, 403);
        assertEquals(res.json, {
          error: "Solo un administrador activo puede invitar usuarios.",
        });
      });

      await t.step("perfil inactivo", async () => {
        estado = estadoInicial();
        assert(estado.perfil, "El perfil de prueba debe existir");
        estado.perfil.activo = false;
        const res = await invocar(funcion.base, { body: CUERPO_VALIDO });
        assertEquals(res.status, 403);
        assertEquals(res.json, {
          error: "Solo un administrador activo puede invitar usuarios.",
        });
      });

      await t.step("JWT sin rol admin", async () => {
        estado = estadoInicial();
        estado.appMetadata = {
          ...estado.appMetadata,
          rol: "empleado",
        };
        const res = await invocar(funcion.base, { body: CUERPO_VALIDO });
        assertEquals(res.status, 403);
        assertEquals(res.json, {
          error:
            "Tu sesión ya no refleja tu alcance actual. Vuelve a iniciar sesión.",
        });
        assertEquals(
          estado.peticiones.some((p) => p.pathname === "/auth/v1/invite"),
          false,
        );
      });

      await t.step("JWT de otra empresa", async () => {
        estado = estadoInicial();
        estado.appMetadata = {
          ...estado.appMetadata,
          empresa_id: EMPRESA_OTRA,
        };
        const res = await invocar(funcion.base, { body: CUERPO_VALIDO });
        assertEquals(res.status, 403);
        assertEquals(res.json, {
          error:
            "Tu sesión ya no refleja tu alcance actual. Vuelve a iniciar sesión.",
        });
      });

      await t.step("JWT con otro centro de costo", async () => {
        estado = estadoInicial();
        estado.appMetadata = {
          ...estado.appMetadata,
          centro_costo_id: CENTRO_HIJO,
        };
        const res = await invocar(funcion.base, { body: CUERPO_VALIDO });
        assertEquals(res.status, 403);
        assertEquals(res.json, {
          error:
            "Tu sesión ya no refleja tu alcance actual. Vuelve a iniciar sesión.",
        });
      });

      await t.step("token sin forma de JWT", async () => {
        estado = estadoInicial();
        const res = await invocar(funcion.base, {
          authorization: "Bearer admin-token",
          body: CUERPO_VALIDO,
        });
        assertEquals(res.status, 401);
        assertEquals(res.json, { error: "Sesión inválida o expirada." });
      });

      await t.step("token emitido para otro usuario", async () => {
        estado = estadoInicial();
        const res = await invocar(funcion.base, {
          authorization: `Bearer ${jwtFalso(estado.appMetadata, OTRO_ID)}`,
          body: CUERPO_VALIDO,
        });
        assertEquals(res.status, 401);
        assertEquals(res.json, { error: "Sesión inválida o expirada." });
      });

      await t.step(
        "usa los claims del token, no el registro actual",
        async () => {
          estado = estadoInicial();
          // El registro actual dice que el admin está en su centro, pero el token
          // emitido conserva otro alcance: debe mandar el token.
          estado.appMetadata = {
            ...estado.appMetadata,
            centro_costo_id: CENTRO_HIJO,
          };
          const res = await invocar(funcion.base, { body: CUERPO_VALIDO });
          assertEquals(res.status, 403);
          assertEquals(res.json, {
            error:
              "Tu sesión ya no refleja tu alcance actual. Vuelve a iniciar sesión.",
          });
        },
      );

      await t.step(
        "un registro actual desalineado no invalida el token",
        async () => {
          estado = estadoInicial();
          estado.appMetadataUsuario = {
            ...estado.appMetadataUsuario,
            centro_costo_id: CENTRO_HIJO,
          };
          const res = await invocar(funcion.base, { body: CUERPO_VALIDO });
          assertEquals(res.status, 201);
        },
      );

      await t.step("error al consultar el perfil", async () => {
        estado = estadoInicial();
        estado.perfilError = true;
        const res = await invocar(funcion.base, { body: CUERPO_VALIDO });
        assertEquals(res.status, 500);
        assertEquals(res.json, {
          error: "No se pudo verificar el perfil del solicitante.",
        });
      });

      await t.step("error al consultar la empresa", async () => {
        estado = estadoInicial();
        estado.empresaError = true;
        const res = await invocar(funcion.base, { body: CUERPO_VALIDO });
        assertEquals(res.status, 500);
        assertEquals(res.json, {
          error: "No se pudo verificar la empresa.",
        });
        assertEquals(
          estado.peticiones.some((p) => p.pathname === "/auth/v1/invite"),
          false,
        );
      });

      await t.step("empresa suspendida", async () => {
        estado = estadoInicial();
        assert(estado.empresa, "La empresa de prueba debe existir");
        estado.empresa.activa = false;
        const res = await invocar(funcion.base, { body: CUERPO_VALIDO });
        assertEquals(res.status, 403);
        assertEquals(res.json, { error: "La empresa está suspendida." });
        assertEquals(
          estado.peticiones.some((p) => p.pathname === "/auth/v1/invite"),
          false,
        );
      });

      await t.step("empresa inexistente", async () => {
        estado = estadoInicial();
        estado.empresa = null;
        const res = await invocar(funcion.base, { body: CUERPO_VALIDO });
        assertEquals(res.status, 403);
        assertEquals(res.json, { error: "La empresa está suspendida." });
      });

      await t.step("cuerpo que no es JSON", async () => {
        estado = estadoInicial();
        const res = await invocar(funcion.base, { rawBody: "{" });
        assertEquals(res.status, 400);
        assertEquals(res.json, { error: "El cuerpo debe ser JSON válido." });
      });

      await t.step("correo inválido", async () => {
        estado = estadoInicial();
        const res = await invocar(funcion.base, {
          body: { ...CUERPO_VALIDO, email: "no-es-correo" },
        });
        assertEquals(res.status, 400);
        assertEquals(res.json, {
          error: "Escribe un correo electrónico válido.",
        });
      });

      await t.step("nombre demasiado corto", async () => {
        estado = estadoInicial();
        const res = await invocar(funcion.base, {
          body: { ...CUERPO_VALIDO, nombre_completo: "A" },
        });
        assertEquals(res.status, 400);
        assertEquals(res.json, {
          error: "El nombre completo debe tener entre 2 y 120 caracteres.",
        });
      });

      await t.step("rol fuera del enum de negocio", async () => {
        estado = estadoInicial();
        const res = await invocar(funcion.base, {
          body: { ...CUERPO_VALIDO, rol: "gerente" },
        });
        assertEquals(res.status, 400);
        assertEquals(res.json, { error: "El rol debe ser empleado o admin." });
      });

      await t.step("centro de costo con UUID inválido", async () => {
        estado = estadoInicial();
        const res = await invocar(funcion.base, {
          body: { ...CUERPO_VALIDO, centro_costo_id: "no-es-uuid" },
        });
        assertEquals(res.status, 400);
        assertEquals(res.json, {
          error: "El centro de costo no es válido.",
        });
      });

      await t.step("error al consultar el centro de costo", async () => {
        estado = estadoInicial();
        estado.centroError = true;
        const res = await invocar(funcion.base, { body: CUERPO_VALIDO });
        assertEquals(res.status, 500);
        assertEquals(res.json, {
          error: "No se pudo verificar el centro de costo.",
        });
      });

      await t.step("centro de otra empresa", async () => {
        estado = estadoInicial();
        assert(estado.centro, "El centro de prueba debe existir");
        estado.centro.empresa_id = EMPRESA_OTRA;
        const res = await invocar(funcion.base, { body: CUERPO_VALIDO });
        assertEquals(res.status, 400);
        assertEquals(res.json, {
          error: "El centro de costo no pertenece a tu empresa.",
        });
      });

      await t.step("centro fuera del subárbol del admin", async () => {
        estado = estadoInicial();
        estado.centro = {
          id: CENTRO_FUERA,
          empresa_id: EMPRESA_ID,
          ruta: ["99999999-9999-4999-8999-999999999999"],
        };
        const res = await invocar(funcion.base, {
          body: { ...CUERPO_VALIDO, centro_costo_id: CENTRO_FUERA },
        });
        assertEquals(res.status, 403);
        assertEquals(res.json, {
          error:
            "Solo puedes invitar usuarios a centros dentro de tu subárbol.",
        });
      });

      await t.step("invitación exitosa de empleado", async () => {
        estado = estadoInicial();
        const res = await invocar(funcion.base, {
          body: { ...CUERPO_VALIDO, empresa_id: EMPRESA_OTRA },
        });
        assertEquals(res.status, 201);
        assertEquals(res.json, {
          id: INVITADO_ID,
          email: "nuevo@empresa.com",
          rol: "empleado",
          empresa_id: EMPRESA_ID,
          centro_costo_id: CENTRO_HIJO,
          nombre_completo: "Nuevo Empleado",
          invitacion_enviada: true,
        });

        const consultaPerfil = peticion("GET", "/rest/v1/perfiles");
        assert(
          consultaPerfil.search.includes("limit=1"),
          "El perfil debe consultarse con limit=1",
        );
        assert(
          consultaPerfil.search.includes(`id=eq.${ADMIN_ID}`),
          "El perfil debe filtrarse por el usuario autenticado",
        );

        const consultaEmpresa = peticion("GET", "/rest/v1/empresas");
        assert(
          consultaEmpresa.search.includes("limit=1"),
          "La empresa debe consultarse con limit=1",
        );
        assert(
          consultaEmpresa.search.includes(`id=eq.${EMPRESA_ID}`),
          "La empresa debe filtrarse por la empresa del perfil",
        );

        const consultaCentro = peticion("GET", "/rest/v1/centros_costo");
        assert(
          consultaCentro.search.includes("limit=1"),
          "El centro debe consultarse con limit=1",
        );
        assert(
          consultaCentro.search.includes(`id=eq.${CENTRO_HIJO}`),
          "El centro debe filtrarse por el id recibido",
        );

        const invitacion = peticion("POST", "/auth/v1/invite");
        assertEquals(JSON.parse(invitacion.body), {
          email: "nuevo@empresa.com",
        });
        assert(
          invitacion.search.includes(
            `redirect_to=${encodeURIComponent(REDIRECT)}`,
          ),
          "La invitación debe usar el deep link configurado",
        );

        const claims = peticion(
          "PUT",
          `/auth/v1/admin/users/${INVITADO_ID}`,
        );
        assertEquals(JSON.parse(claims.body), {
          app_metadata: {
            empresa_id: EMPRESA_ID,
            centro_costo_id: CENTRO_HIJO,
            rol: "empleado",
          },
          user_metadata: { nombre_completo: "Nuevo Empleado" },
        });
        assertEquals(estado.usuariosEliminados, []);
      });

      await t.step(
        "invitación exitosa de admin en su propio centro",
        async () => {
          estado = estadoInicial();
          estado.centro = {
            id: CENTRO_ADMIN,
            empresa_id: EMPRESA_ID,
            ruta: [],
          };
          const res = await invocar(funcion.base, {
            body: {
              ...CUERPO_VALIDO,
              email: "nuevo-admin@empresa.com",
              rol: "admin",
              centro_costo_id: CENTRO_ADMIN,
            },
          });
          assertEquals(res.status, 201);
          assertEquals(res.json?.rol, "admin");
          assertEquals(res.json?.centro_costo_id, CENTRO_ADMIN);

          const claims = peticion(
            "PUT",
            `/auth/v1/admin/users/${INVITADO_ID}`,
          );
          const atributos = JSON.parse(claims.body) as {
            app_metadata: Record<string, unknown>;
          };
          assertEquals(atributos.app_metadata, {
            empresa_id: EMPRESA_ID,
            centro_costo_id: CENTRO_ADMIN,
            rol: "admin",
          });
        },
      );

      await t.step("correo ya registrado", async () => {
        estado = estadoInicial();
        estado.invitacionError = {
          status: 422,
          message: "A user with this email address has already been registered",
        };
        const res = await invocar(funcion.base, { body: CUERPO_VALIDO });
        assertEquals(res.status, 409);
        assertEquals(res.json, {
          error: "Ese correo ya tiene una cuenta en Carrousel.",
        });
        assertEquals(estado.usuariosEliminados, []);
      });

      await t.step("error genérico al invitar", async () => {
        estado = estadoInicial();
        estado.invitacionError = {
          status: 500,
          message: "smtp no disponible",
        };
        const res = await invocar(funcion.base, { body: CUERPO_VALIDO });
        assertEquals(res.status, 502);
        assertEquals(res.json, {
          error:
            "No se pudo enviar la invitación. Revisa la configuración de correo.",
        });
        assertEquals(estado.usuariosEliminados, []);
      });

      await t.step("error al escribir claims revierte el usuario", async () => {
        estado = estadoInicial();
        estado.claimsError = true;
        const res = await invocar(funcion.base, { body: CUERPO_VALIDO });
        assertEquals(res.status, 500);
        assertEquals(res.json, {
          error:
            "No se pudo asignar el alcance al usuario. La invitación se revirtió.",
        });
        assertEquals(estado.usuariosEliminados, [INVITADO_ID]);
        peticion("GET", `/auth/v1/admin/users/${INVITADO_ID}`);
        peticion("DELETE", `/auth/v1/admin/users/${INVITADO_ID}`);
      });
    } finally {
      await funcion.detener();
      await falso.detener();
    }
  },
});
