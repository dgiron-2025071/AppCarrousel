// =============================================================================
// Carrousel — Pruebas unitarias de autorizacion y servicio de `invitar-usuario`
//
// Ejercitan el nucleo de reglas con un cliente de Supabase falso: sesion,
// perfil, claims del JWT, empresa, subarbol, invitacion, claims, rollback y
// reconciliacion. Comprueban ademas el orden de las consultas y los payloads
// enviados a Auth, sin levantar HTTP ni usar credenciales.
//
// Ejecución:
//   npx -y deno test -A supabase/functions/tests/autorizacion_servicio_test.ts
// =============================================================================

import { autorizar, verificarSesion } from "../invitar-usuario/autorizacion.ts";
import type { ClienteSupabase } from "../invitar-usuario/clientes.ts";
import { MARCA_TIMEOUT } from "../invitar-usuario/errores.ts";
import { ejecutarInvitacion } from "../invitar-usuario/servicio.ts";
import type { DatosInvitacion } from "../invitar-usuario/tipos.ts";

const ADMIN_ID = "11111111-1111-4111-8111-111111111111";
const EMPRESA_ID = "22222222-2222-4222-8222-222222222222";
const CENTRO_ADMIN = "44444444-4444-4444-8444-444444444444";
const CENTRO_HIJO = "55555555-5555-4555-8555-555555555555";
const CENTRO_FUERA = "66666666-6666-4666-8666-666666666666";
const INVITADO_ID = "77777777-7777-4777-8777-777777777777";
const EMAIL = "nuevo@empresa.com";
const REDIRECT = "io.supabase.carrousel://login-callback";

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

async function sinAlertas<T>(operacion: () => Promise<T>): Promise<T> {
  const original = console.error;
  console.error = () => {};
  try {
    return await operacion();
  } finally {
    console.error = original;
  }
}

function base64url(valor: unknown): string {
  return btoa(JSON.stringify(valor))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function jwt(
  appMetadata: Record<string, unknown> = {
    rol: "admin",
    empresa_id: EMPRESA_ID,
    centro_costo_id: CENTRO_ADMIN,
  },
  sub = ADMIN_ID,
): string {
  const payload = { sub, exp: 4102444800, app_metadata: appMetadata };
  return `${base64url({ alg: "HS256" })}.${base64url(payload)}.firma`;
}

function timeout(): Error {
  return new Error(`fallo de red: ${MARCA_TIMEOUT}`);
}

interface ResultadoConsulta {
  data: unknown[] | null;
  error: unknown;
}

interface ResultadoListado {
  data: { users: UsuarioListado[] } | null;
  error: unknown;
}

interface UsuarioListado {
  id: string;
  email: string | null;
  created_at: string;
  app_metadata: Record<string, unknown>;
}

interface ArgsListado {
  page: number;
  perPage: number;
}

interface OpcionesInvitacion {
  redirectTo: string;
}

interface ConsultaRegistrada {
  tabla: string;
  columnas: string;
  columna: string;
  valor: unknown;
}

interface EstadoFalso {
  getUser: () => Promise<{
    data: { user: { id: string } | null } | null;
    error: unknown;
  }>;
  perfiles: () => ResultadoConsulta;
  empresas: () => ResultadoConsulta;
  centros: () => ResultadoConsulta;
  invitar: (
    email: string,
    opciones: OpcionesInvitacion,
  ) => Promise<{ data: { user: { id: string } } | null; error: unknown }>;
  actualizar: (
    id: string,
    cambios: unknown,
  ) => Promise<{ error: unknown }>;
  borrar: (id: string) => Promise<{ error: unknown }>;
  listar: (args: ArgsListado) => Promise<ResultadoListado>;
}

function estadoValido(): EstadoFalso {
  return {
    getUser: () =>
      Promise.resolve({ data: { user: { id: ADMIN_ID } }, error: null }),
    perfiles: () => ({
      data: [{
        empresa_id: EMPRESA_ID,
        centro_costo_id: CENTRO_ADMIN,
        rol: "admin",
        activo: true,
      }],
      error: null,
    }),
    empresas: () => ({ data: [{ activa: true }], error: null }),
    centros: () => ({
      data: [{
        id: CENTRO_HIJO,
        empresa_id: EMPRESA_ID,
        ruta: [CENTRO_ADMIN],
      }],
      error: null,
    }),
    invitar: (_email, _opciones) =>
      Promise.resolve({
        data: { user: { id: INVITADO_ID } },
        error: null,
      }),
    actualizar: () => Promise.resolve({ error: null }),
    borrar: () => Promise.resolve({ error: null }),
    listar: () => Promise.resolve({ data: { users: [] }, error: null }),
  };
}

function clienteFalso(estado: EstadoFalso): {
  cliente: ClienteSupabase;
  consultas: ConsultaRegistrada[];
  invitaciones: Array<{ email: string; opciones: OpcionesInvitacion }>;
  actualizaciones: Array<{ id: string; cambios: Record<string, unknown> }>;
  borrados: string[];
  listados: ArgsListado[];
} {
  const consultas: ConsultaRegistrada[] = [];
  const invitaciones: Array<{ email: string; opciones: OpcionesInvitacion }> =
    [];
  const actualizaciones: Array<
    { id: string; cambios: Record<string, unknown> }
  > = [];
  const borrados: string[] = [];
  const listados: ArgsListado[] = [];

  const cliente = {
    auth: {
      getUser: async () => await estado.getUser(),
      admin: {
        inviteUserByEmail: async (
          email: string,
          opciones: OpcionesInvitacion,
        ) => {
          invitaciones.push({ email, opciones });
          return await estado.invitar(email, opciones);
        },
        updateUserById: async (id: string, cambios: unknown) => {
          actualizaciones.push({
            id,
            cambios: cambios as Record<string, unknown>,
          });
          return await estado.actualizar(id, cambios);
        },
        deleteUser: async (id: string) => {
          borrados.push(id);
          return await estado.borrar(id);
        },
        listUsers: async (args: ArgsListado) => {
          listados.push({ ...args });
          return await estado.listar(args);
        },
      },
    },
    from: (tabla: string) => ({
      select: (columnas: string) => ({
        eq: (columna: string, valor: unknown) => ({
          limit: async () => {
            consultas.push({ tabla, columnas, columna, valor });
            if (tabla === "perfiles") return await estado.perfiles();
            if (tabla === "empresas") return await estado.empresas();
            if (tabla === "centros_costo") return await estado.centros();
            return { data: [], error: new Error(`tabla inesperada: ${tabla}`) };
          },
        }),
      }),
    }),
  } as unknown as ClienteSupabase;

  return {
    cliente,
    consultas,
    invitaciones,
    actualizaciones,
    borrados,
    listados,
  };
}

function datos(
  centrosId = CENTRO_HIJO,
  rol: DatosInvitacion["rol"] = "empleado",
): DatosInvitacion {
  return {
    email: EMAIL,
    nombre: "Nuevo Empleado",
    rol,
    centroId: centrosId,
  };
}

function parametros(
  estado: EstadoFalso,
  centrosId = CENTRO_HIJO,
  rol: DatosInvitacion["rol"] = "empleado",
) {
  const falso = clienteFalso(estado);
  return {
    ...falso,
    args: {
      datos: datos(centrosId, rol),
      autorizacion: jwt(),
      idUsuario: ADMIN_ID,
      redirectTo: REDIRECT,
      admin: falso.cliente,
    },
  };
}

Deno.test("sesion: devuelve el id del usuario autenticado", async () => {
  const falso = clienteFalso(estadoValido());
  const resultado = await verificarSesion(falso.cliente);
  assertEquals(resultado.id, ADMIN_ID);
  assertEquals(resultado.respuesta, null);
});

Deno.test("sesion: un timeout de Auth responde 504 y no 401", async () => {
  const estado = estadoValido();
  estado.getUser = () => Promise.resolve({ data: null, error: timeout() });
  const falso = clienteFalso(estado);
  const resultado = await verificarSesion(falso.cliente);
  assertEquals(resultado.id, null);
  assert(resultado.respuesta !== null, "Faltó la respuesta de error");
  assertEquals(resultado.respuesta.status, 504);
  assertEquals(await resultado.respuesta.json(), {
    error: "Auth no respondió al verificar la sesión. Intenta de nuevo.",
  });
});

Deno.test("sesion: una sesión inválida responde 401", async () => {
  const estado = estadoValido();
  estado.getUser = () =>
    Promise.resolve({
      data: { user: null },
      error: new Error("token expirado"),
    });
  const falso = clienteFalso(estado);
  const resultado = await verificarSesion(falso.cliente);
  assert(resultado.respuesta !== null, "Faltó la respuesta de error");
  assertEquals(resultado.respuesta.status, 401);
  assertEquals(await resultado.respuesta.json(), {
    error: "Sesión inválida o expirada.",
  });
});

Deno.test("autorizacion: consulta perfil, empresa y centro en ese orden", async () => {
  const falso = clienteFalso(estadoValido());
  const resultado = await autorizar(
    falso.cliente,
    jwt(),
    ADMIN_ID,
    CENTRO_HIJO,
  );

  assertEquals(resultado.respuesta, null);
  assert(resultado.contexto !== null, "Faltó el contexto autorizado");
  assertEquals(resultado.contexto.perfil.rol, "admin");
  assertEquals(resultado.contexto.centro.id, CENTRO_HIJO);
  assertEquals(
    falso.consultas.map(({ tabla, columna, valor }) => [tabla, columna, valor]),
    [
      ["perfiles", "id", ADMIN_ID],
      ["empresas", "id", EMPRESA_ID],
      ["centros_costo", "id", CENTRO_HIJO],
    ],
  );
});

Deno.test("autorizacion: un perfil que no es admin activo detiene la consulta", async () => {
  const estado = estadoValido();
  estado.perfiles = () => ({
    data: [{
      empresa_id: EMPRESA_ID,
      centro_costo_id: CENTRO_ADMIN,
      rol: "empleado",
      activo: true,
    }],
    error: null,
  });
  const falso = clienteFalso(estado);
  const resultado = await autorizar(
    falso.cliente,
    jwt(),
    ADMIN_ID,
    CENTRO_HIJO,
  );

  assert(resultado.respuesta !== null, "Faltó la respuesta de error");
  assertEquals(resultado.respuesta.status, 403);
  assertEquals(await resultado.respuesta.json(), {
    error: "Solo un administrador activo puede invitar usuarios.",
  });
  assertEquals(falso.consultas.length, 1);
});

Deno.test("autorizacion: claims desalineados frenan antes de leer empresa", async () => {
  const falso = clienteFalso(estadoValido());
  const resultado = await autorizar(
    falso.cliente,
    jwt({
      rol: "admin",
      empresa_id: EMPRESA_ID,
      centro_costo_id: CENTRO_FUERA,
    }),
    ADMIN_ID,
    CENTRO_HIJO,
  );

  assert(resultado.respuesta !== null, "Faltó la respuesta de error");
  assertEquals(resultado.respuesta.status, 403);
  assertEquals(await resultado.respuesta.json(), {
    error:
      "Tu sesión ya no refleja tu alcance actual. Vuelve a iniciar sesión.",
  });
  assertEquals(falso.consultas.length, 1);
});

Deno.test("autorizacion: un JWT de otro usuario responde 401", async () => {
  const falso = clienteFalso(estadoValido());
  const resultado = await autorizar(
    falso.cliente,
    jwt(undefined, "99999999-9999-4999-8999-999999999999"),
    ADMIN_ID,
    CENTRO_HIJO,
  );

  assert(resultado.respuesta !== null, "Faltó la respuesta de error");
  assertEquals(resultado.respuesta.status, 401);
  assertEquals(await resultado.respuesta.json(), {
    error: "Sesión inválida o expirada.",
  });
  assertEquals(falso.consultas.length, 1);
});

Deno.test("autorizacion: empresa suspendida no consulta el centro", async () => {
  const estado = estadoValido();
  estado.empresas = () => ({ data: [{ activa: false }], error: null });
  const falso = clienteFalso(estado);
  const resultado = await autorizar(
    falso.cliente,
    jwt(),
    ADMIN_ID,
    CENTRO_HIJO,
  );

  assert(resultado.respuesta !== null, "Faltó la respuesta de error");
  assertEquals(resultado.respuesta.status, 403);
  assertEquals(await resultado.respuesta.json(), {
    error: "La empresa está suspendida.",
  });
  assertEquals(
    falso.consultas.map(({ tabla }) => tabla),
    ["perfiles", "empresas"],
  );
});

Deno.test("autorizacion: un centro fuera del subárbol se rechaza", async () => {
  const estado = estadoValido();
  estado.centros = () => ({
    data: [{
      id: CENTRO_FUERA,
      empresa_id: EMPRESA_ID,
      ruta: [],
    }],
    error: null,
  });
  const falso = clienteFalso(estado);
  const resultado = await autorizar(
    falso.cliente,
    jwt(),
    ADMIN_ID,
    CENTRO_FUERA,
  );

  assert(resultado.respuesta !== null, "Faltó la respuesta de error");
  assertEquals(resultado.respuesta.status, 403);
  assertEquals(await resultado.respuesta.json(), {
    error: "Solo puedes invitar usuarios a centros dentro de tu subárbol.",
  });
  assertEquals(
    falso.consultas.map(({ tabla }) => tabla),
    ["perfiles", "empresas", "centros_costo"],
  );
});

Deno.test("autorizacion: timeouts de base de datos responden 504", async () => {
  const casos: Array<{
    propiedad: "perfiles" | "empresas" | "centros";
    etiqueta: string;
    mensaje: string;
    consultas: number;
  }> = [
    {
      propiedad: "perfiles",
      etiqueta: "perfiles",
      mensaje: "La base de datos no respondió al leer el perfil.",
      consultas: 1,
    },
    {
      propiedad: "empresas",
      etiqueta: "empresas",
      mensaje: "La base de datos no respondió al leer la empresa.",
      consultas: 2,
    },
    {
      propiedad: "centros",
      etiqueta: "centros_costo",
      mensaje: "La base de datos no respondió al leer el centro de costo.",
      consultas: 3,
    },
  ];

  for (const caso of casos) {
    const estado = estadoValido();
    estado[caso.propiedad] = () => ({ data: null, error: timeout() });
    const falso = clienteFalso(estado);
    const resultado = await autorizar(
      falso.cliente,
      jwt(),
      ADMIN_ID,
      CENTRO_HIJO,
    );

    assert(
      resultado.respuesta !== null,
      `Faltó la respuesta de ${caso.etiqueta}`,
    );
    assertEquals(resultado.respuesta.status, 504, caso.etiqueta);
    assertEquals(await resultado.respuesta.json(), { error: caso.mensaje });
    assertEquals(falso.consultas.length, caso.consultas, caso.etiqueta);
  }
});

Deno.test("autorizacion: errores de base de datos distintos de timeout responden 500", async () => {
  const casos: Array<{
    propiedad: "perfiles" | "empresas" | "centros";
    etiqueta: string;
    mensaje: string;
  }> = [
    {
      propiedad: "perfiles",
      etiqueta: "perfiles",
      mensaje: "No se pudo verificar el perfil del solicitante.",
    },
    {
      propiedad: "empresas",
      etiqueta: "empresas",
      mensaje: "No se pudo verificar la empresa.",
    },
    {
      propiedad: "centros",
      etiqueta: "centros_costo",
      mensaje: "No se pudo verificar el centro de costo.",
    },
  ];

  for (const caso of casos) {
    const estado = estadoValido();
    estado[caso.propiedad] = () => ({
      data: null,
      error: new Error("fallo de consulta"),
    });
    const falso = clienteFalso(estado);
    const resultado = await autorizar(
      falso.cliente,
      jwt(),
      ADMIN_ID,
      CENTRO_HIJO,
    );

    assert(
      resultado.respuesta !== null,
      `Faltó la respuesta de ${caso.etiqueta}`,
    );
    assertEquals(resultado.respuesta.status, 500, caso.etiqueta);
    assertEquals(await resultado.respuesta.json(), { error: caso.mensaje });
  }
});

Deno.test("servicio: la invitación correcta escribe los claims del perfil", async () => {
  const caso = parametros(estadoValido(), CENTRO_HIJO, "admin");
  const resultado = await ejecutarInvitacion(caso.args);

  assertEquals(resultado.status, 201);
  assertEquals(await resultado.json(), {
    id: INVITADO_ID,
    email: EMAIL,
    rol: "admin",
    empresa_id: EMPRESA_ID,
    centro_costo_id: CENTRO_HIJO,
    nombre_completo: "Nuevo Empleado",
    invitacion_enviada: true,
  });
  assertEquals(caso.invitaciones, [{
    email: EMAIL,
    opciones: { redirectTo: REDIRECT },
  }]);
  assertEquals(caso.actualizaciones, [{
    id: INVITADO_ID,
    cambios: {
      app_metadata: {
        empresa_id: EMPRESA_ID,
        centro_costo_id: CENTRO_HIJO,
        rol: "admin",
      },
      user_metadata: { nombre_completo: "Nuevo Empleado" },
    },
  }]);
  assertEquals(caso.borrados, []);
  assertEquals(caso.listados, []);
});

Deno.test("servicio: un correo ya registrado no busca huérfanas", async () => {
  const estado = estadoValido();
  estado.invitar = () =>
    Promise.resolve({
      data: null,
      error: new Error("User already been registered"),
    });
  const caso = parametros(estado);
  const resultado = await sinAlertas(() => ejecutarInvitacion(caso.args));

  assertEquals(resultado.status, 409);
  assertEquals(await resultado.json(), {
    error: "Ese correo ya tiene una cuenta en Carrousel.",
  });
  assertEquals(caso.listados, []);
  assertEquals(caso.actualizaciones, []);
});

Deno.test("servicio: error de invitación con huérfana reporta limpieza", async () => {
  const estado = estadoValido();
  estado.invitar = () =>
    Promise.resolve({
      data: null,
      error: new Error("fallo al enviar correo"),
    });
  estado.listar = () =>
    Promise.resolve({
      data: {
        users: [{
          id: "huerfana",
          email: EMAIL,
          created_at: new Date(Date.now() - 1000).toISOString(),
          app_metadata: {},
        }],
      },
      error: null,
    });
  const caso = parametros(estado);
  const resultado = await sinAlertas(() => ejecutarInvitacion(caso.args));

  assertEquals(resultado.status, 502);
  assertEquals(await resultado.json(), {
    error:
      "No se pudo enviar la invitación. Se eliminó la cuenta huérfana; vuelve a intentar.",
  });
  assertEquals(caso.borrados, ["huerfana"]);
});

Deno.test("servicio: fallos de reconciliación no afirman limpieza", async () => {
  const casos: Array<{
    listar: EstadoFalso["listar"];
    status: number;
    mensaje: string;
  }> = [
    {
      listar: () =>
        Promise.resolve({ data: null, error: new Error("fallo al listar") }),
      status: 500,
      mensaje:
        "No se pudo enviar la invitación ni verificar si quedó una cuenta huérfana. Revisa Auth.",
    },
    {
      listar: () => Promise.resolve({ data: null, error: timeout() }),
      status: 504,
      mensaje:
        "Auth no respondió al buscar una cuenta huérfana. Revisa Auth antes de reintentar.",
    },
    {
      listar: () => Promise.resolve({ data: { users: [] }, error: null }),
      status: 502,
      mensaje:
        "No se pudo enviar la invitación. Revisa la configuración de correo.",
    },
  ];

  for (const caso of casos) {
    const estado = estadoValido();
    estado.invitar = () =>
      Promise.resolve({
        data: null,
        error: new Error("fallo al enviar correo"),
      });
    estado.listar = caso.listar;
    const resultado = await sinAlertas(() =>
      ejecutarInvitacion(parametros(estado).args)
    );

    assertEquals(resultado.status, caso.status);
    assertEquals(await resultado.json(), { error: caso.mensaje });
  }
});

Deno.test("servicio: timeout al invitar no afirma que no se creó la cuenta", async () => {
  const estado = estadoValido();
  estado.invitar = () => Promise.resolve({ data: null, error: timeout() });
  const caso = parametros(estado);
  const resultado = await sinAlertas(() => ejecutarInvitacion(caso.args));

  assertEquals(resultado.status, 504);
  assertEquals(await resultado.json(), {
    error:
      "Auth no respondió al enviar la invitación; no se confirmó si se creó la cuenta. Revisa Auth antes de reintentar.",
  });
  assertEquals(caso.listados.length, 1);
  assertEquals(caso.actualizaciones, []);
});

Deno.test("servicio: error al escribir claims revierte la invitación", async () => {
  const estado = estadoValido();
  estado.actualizar = () =>
    Promise.resolve({
      error: new Error("fallo al escribir app_metadata"),
    });
  const caso = parametros(estado);
  const resultado = await sinAlertas(() => ejecutarInvitacion(caso.args));

  assertEquals(resultado.status, 500);
  assertEquals(await resultado.json(), {
    error:
      "No se pudo asignar el alcance al usuario. La invitación se revirtió.",
  });
  assertEquals(caso.borrados, [INVITADO_ID]);
});

Deno.test("servicio: timeout al escribir claims no borra al usuario", async () => {
  const estado = estadoValido();
  estado.actualizar = () => Promise.resolve({ error: timeout() });
  const caso = parametros(estado);
  const resultado = await sinAlertas(() => ejecutarInvitacion(caso.args));

  assertEquals(resultado.status, 504);
  assertEquals(await resultado.json(), {
    error:
      "No se pudo confirmar la asignación de alcance. Revisa el usuario en Auth antes de reintentar.",
  });
  assertEquals(caso.borrados, []);
});

Deno.test("servicio: un rollback fallido se explica sin prometer reversión", async () => {
  const casos: Array<{
    borrar: EstadoFalso["borrar"];
    status: number;
  }> = [
    {
      borrar: () => Promise.resolve({ error: new Error("fallo al borrar") }),
      status: 500,
    },
    { borrar: () => Promise.resolve({ error: timeout() }), status: 504 },
  ];

  for (const caso of casos) {
    const estado = estadoValido();
    estado.actualizar = () =>
      Promise.resolve({ error: new Error("fallo en claims") });
    estado.borrar = caso.borrar;
    const resultado = await sinAlertas(() =>
      ejecutarInvitacion(parametros(estado).args)
    );

    assertEquals(resultado.status, caso.status);
    assertEquals(await resultado.json(), {
      error:
        "No se pudo asignar el alcance ni revertir la invitación. Revisa el usuario creado en Auth.",
    });
  }
});
