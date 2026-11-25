// =============================================================================
// Carrousel — Pruebas unitarias de las capas de `invitar-usuario`
//
// Complementan el arnés HTTP (`invitar_usuario_test.ts`) con pruebas directas de
// las capas puras: validacion, claims del token, errores de dependencia,
// respuestas HTTP y reconciliacion de cuentas huérfanas. No requieren Docker,
// credenciales ni red.
//
// Ejecución:
//   npx -y deno test -A supabase/functions/tests/modulos_test.ts
// =============================================================================

import type { ClienteSupabase } from "../invitar-usuario/clientes.ts";
import {
  MAX_PAGINAS_USUARIOS,
  USUARIOS_POR_PAGINA,
  VENTANA_HUERFANO_MS,
} from "../invitar-usuario/config.ts";
import {
  esTimeout,
  MARCA_TIMEOUT,
  TimeoutDependencia,
} from "../invitar-usuario/errores.ts";
import { reconciliarInvitacionFallida } from "../invitar-usuario/reconciliacion.ts";
import {
  CORS,
  error,
  json,
  respuestaFalloNoControlado,
} from "../invitar-usuario/respuestas.ts";
import {
  claimsDelToken,
  normalizarEmail,
  tieneCaracterDeControl,
  validarCuerpo,
} from "../invitar-usuario/validacion.ts";

const CENTRO = "44444444-4444-4444-8444-444444444444";

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

function base64url(valor: unknown): string {
  return btoa(JSON.stringify(valor))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function jwt(payload: unknown): string {
  return `${base64url({ alg: "HS256", typ: "JWT" })}.${
    base64url(payload)
  }.firma`;
}

Deno.test("validacion: normaliza el correo y detecta caracteres de control", () => {
  assertEquals(
    normalizarEmail("  Usuario@Ejemplo.COM  "),
    "usuario@ejemplo.com",
  );
  assertEquals(normalizarEmail("A\u0301@Ejemplo.com"), "á@ejemplo.com");
  assertEquals(normalizarEmail(123), "");
  assert(tieneCaracterDeControl("a\u0000b@example.com"), "C0 no detectado");
  assert(tieneCaracterDeControl("a\u007fb@example.com"), "DEL no detectado");
  assert(
    !tieneCaracterDeControl("á@ejemplo.com"),
    "Un correo Unicode válido fue rechazado",
  );
});

Deno.test("validacion: aplica las reglas del cuerpo en orden", () => {
  const base = {
    email: "Nuevo@Empresa.com",
    nombre_completo: "  Nuevo Empleado  ",
    rol: "empleado",
    centro_costo_id: `  ${CENTRO}  `,
  };

  const sinArroba = validarCuerpo({ ...base, email: "sin-arroba" });
  assertEquals(sinArroba.datos, null);
  assertEquals(
    sinArroba.mensaje,
    "Escribe un correo electrónico válido.",
  );

  const conControl = validarCuerpo({ ...base, email: "a\u0000@b.com" });
  assertEquals(conControl.mensaje, "Escribe un correo electrónico válido.");

  const nombreCorto = validarCuerpo({ ...base, nombre_completo: "A" });
  assertEquals(
    nombreCorto.mensaje,
    "El nombre completo debe tener entre 2 y 120 caracteres.",
  );

  const rolFuera = validarCuerpo({ ...base, rol: "admin General" });
  assertEquals(rolFuera.mensaje, "El rol debe ser empleado o admin.");

  const centroInvalido = validarCuerpo({ ...base, centro_costo_id: "abc" });
  assertEquals(centroInvalido.mensaje, "El centro de costo no es válido.");

  const valido = validarCuerpo(base);
  assertEquals(valido.mensaje, null);
  assertEquals(valido.datos, {
    email: "nuevo@empresa.com",
    nombre: "Nuevo Empleado",
    rol: "empleado",
    centroId: CENTRO,
  });
});

Deno.test("validacion: decodifica los claims emitidos en el JWT", () => {
  const token = jwt({
    sub: "11111111-1111-4111-8111-111111111111",
    app_metadata: { rol: "admin", empresa_id: "empresa", centro_costo_id: "c" },
  });
  const claims = claimsDelToken(`Bearer ${token}`);
  assert(claims !== null, "No se decodificó el payload");
  assertEquals(
    claims.sub,
    "11111111-1111-4111-8111-111111111111",
  );
  assertEquals((claims.app_metadata as Record<string, unknown>).rol, "admin");

  assertEquals(claimsDelToken(token), claims);
  assertEquals(claimsDelToken("no-es-un-jwt"), null);
  assertEquals(
    claimsDelToken(`${base64url({ alg: "HS256" })}.no-es-json.firma`),
    null,
  );
  assertEquals(
    claimsDelToken(`${base64url({ alg: "HS256" })}.${base64url(null)}.firma`),
    null,
  );
});

Deno.test("errores: la marca de timeout sobrevive a supabase-js", () => {
  const causa = new Error("red colgada");
  const fallo = new TimeoutDependencia(causa);
  assertEquals(fallo.message, MARCA_TIMEOUT);
  assertEquals(fallo.name, "AbortError");
  assertEquals((fallo as { code?: string }).code, "ABORT_ERR");
  assert(fallo.cause === causa, "La causa original se perdió");
  assert(esTimeout(fallo), "TimeoutDependencia no se clasificó");
  assert(
    esTimeout({ message: `fetch failed: ${MARCA_TIMEOUT}` }),
    "El error convertido por supabase-js no se clasificó",
  );
  assert(esTimeout(MARCA_TIMEOUT), "La marca suelta no se clasificó");
  assert(!esTimeout(new Error("otro fallo")), "Un error normal se clasificó");
  assert(!esTimeout(undefined), "undefined se clasificó como timeout");
});

Deno.test("respuestas: los timeouts dan 504 y los fallos internos no filtran detalles", async () => {
  const timeout = respuestaFalloNoControlado({ message: MARCA_TIMEOUT });
  assertEquals(timeout.status, 504);
  assertEquals(await timeout.json(), {
    error: "Una dependencia no respondió a tiempo. Intenta de nuevo.",
  });
  assertEquals(timeout.headers.get("Access-Control-Allow-Origin"), "*");

  const interno = respuestaFalloNoControlado(new Error("secreto de infra"));
  assertEquals(interno.status, 500);
  assertEquals(await interno.json(), {
    error: "Error interno de la función.",
  });

  const fallo = error("fallo controlado", 409);
  assertEquals(fallo.status, 409);
  assertEquals(await fallo.json(), { error: "fallo controlado" });

  const correcta = json({ ok: true }, 201);
  assertEquals(correcta.status, 201);
  assertEquals(await correcta.json(), { ok: true });
  assertEquals(CORS["Access-Control-Allow-Methods"], "POST, OPTIONS");
});

interface UsuarioListado {
  id: string;
  email: string | null;
  created_at: string;
  app_metadata: Record<string, unknown>;
}

interface ResultadoListado {
  data: { users: UsuarioListado[]; nextPage?: number | null } | null;
  error: unknown;
}

interface LlamadaListado {
  page: number;
  perPage: number;
}

interface ClienteReconciliacion {
  cliente: ClienteSupabase;
  paginas: LlamadaListado[];
  borrados: string[];
}

function clienteReconciliacion(
  listar: (
    args: LlamadaListado,
  ) => ResultadoListado | Promise<ResultadoListado>,
  borrar: (id: string) => { error: unknown } = () => ({ error: null }),
): ClienteReconciliacion {
  const paginas: LlamadaListado[] = [];
  const borrados: string[] = [];
  const cliente = {
    auth: {
      admin: {
        listUsers: async (args: LlamadaListado) => {
          paginas.push({ ...args });
          return await listar(args);
        },
        deleteUser: async (id: string) => {
          borrados.push(id);
          return await borrar(id);
        },
      },
    },
  } as unknown as ClienteSupabase;
  return { cliente, paginas, borrados };
}

function paginaLlena(): UsuarioListado[] {
  return Array.from({ length: USUARIOS_POR_PAGINA }, (_, indice) => ({
    id: `otro-${indice}`,
    email: "otro@ejemplo.com",
    created_at: new Date(Date.now() - 1000).toISOString(),
    app_metadata: {},
  }));
}

Deno.test("reconciliacion: elimina solo la huérfana reciente del mismo correo", async () => {
  const reciente = new Date(Date.now() - 60_000).toISOString();
  const antigua = new Date(Date.now() - VENTANA_HUERFANO_MS - 1000)
    .toISOString();
  const futura = new Date(Date.now() + 60_000).toISOString();
  const usuarios: UsuarioListado[] = [
    {
      id: "con-claims",
      email: "NUEVO@EMPRESA.COM",
      created_at: reciente,
      app_metadata: { empresa_id: "otra" },
    },
    {
      id: "antigua",
      email: "nuevo@empresa.com",
      created_at: antigua,
      app_metadata: {},
    },
    {
      id: "futura",
      email: "nuevo@empresa.com",
      created_at: futura,
      app_metadata: {},
    },
    {
      id: "huerfana",
      email: "NUEVO@EMPRESA.COM",
      created_at: reciente,
      app_metadata: {},
    },
  ];
  const falso = clienteReconciliacion(() => ({
    data: { users: usuarios },
    error: null,
  }));

  assertEquals(
    await reconciliarInvitacionFallida(falso.cliente, "nuevo@empresa.com"),
    "revertido",
  );
  assertEquals(falso.borrados, ["huerfana"]);
  assertEquals(falso.paginas.length, 1);
  assertEquals(falso.paginas[0].perPage, USUARIOS_POR_PAGINA);
});

Deno.test("reconciliacion: sin huérfana reporta limpio sin borrar nada", async () => {
  const falso = clienteReconciliacion(() => ({
    data: { users: paginaLlena().slice(0, 3) },
    error: null,
  }));

  assertEquals(
    await reconciliarInvitacionFallida(falso.cliente, "nuevo@empresa.com"),
    "limpio",
  );
  assertEquals(falso.borrados, []);
});

Deno.test("reconciliacion: un puntero de pagina repetido falla cerrado", async () => {
  const falso = clienteReconciliacion(({ page }) => ({
    data: { users: paginaLlena(), nextPage: page },
    error: null,
  }));

  assertEquals(
    await reconciliarInvitacionFallida(falso.cliente, "nuevo@empresa.com"),
    "error",
  );
  assertEquals(falso.paginas.length, 1);
  assertEquals(falso.borrados, []);
});

Deno.test("reconciliacion: el techo de paginas falla cerrado", async () => {
  const falso = clienteReconciliacion(() => ({
    data: { users: paginaLlena() },
    error: null,
  }));

  assertEquals(
    await reconciliarInvitacionFallida(falso.cliente, "nuevo@empresa.com"),
    "error",
  );
  assertEquals(falso.paginas.length, MAX_PAGINAS_USUARIOS);
  assertEquals(falso.borrados, []);
});

Deno.test("reconciliacion: distingue timeouts de errores al listar y al borrar", async () => {
  const timeoutListado = clienteReconciliacion(() => ({
    data: null,
    error: { message: `fallo de red: ${MARCA_TIMEOUT}` },
  }));
  assertEquals(
    await reconciliarInvitacionFallida(
      timeoutListado.cliente,
      "nuevo@empresa.com",
    ),
    "timeout",
  );

  const errorListado = clienteReconciliacion(() => ({
    data: null,
    error: new Error("fallo al listar"),
  }));
  assertEquals(
    await reconciliarInvitacionFallida(
      errorListado.cliente,
      "nuevo@empresa.com",
    ),
    "error",
  );

  const huerfana: UsuarioListado = {
    id: "huerfana",
    email: "nuevo@empresa.com",
    created_at: new Date(Date.now() - 1000).toISOString(),
    app_metadata: {},
  };
  const timeoutBorrado = clienteReconciliacion(
    () => ({ data: { users: [huerfana] }, error: null }),
    () => ({ error: { message: MARCA_TIMEOUT } }),
  );
  assertEquals(
    await reconciliarInvitacionFallida(
      timeoutBorrado.cliente,
      "nuevo@empresa.com",
    ),
    "timeout",
  );
  assertEquals(timeoutBorrado.borrados, ["huerfana"]);
});
