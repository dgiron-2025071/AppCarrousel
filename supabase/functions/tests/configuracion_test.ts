// =============================================================================
// Carrousel — Pruebas unitarias de la capa de configuracion
//
// Ejercitan las funciones puras que antes solo se podian comprobar leyendo el
// entorno al importar el modulo: timeout de Auth, puerto local y secretos de
// Supabase. No usan credenciales ni red.
//
// Ejecución:
//   npx -y deno test -A supabase/functions/tests/configuracion_test.ts
// =============================================================================

import {
  configuracionDesdeEntorno,
  puertoDesdeEntorno,
  REDIRECT_POR_DEFECTO,
  timeoutDesdeEntorno,
} from "../invitar-usuario/config.ts";

function assertEquals<T>(
  actual: T,
  esperado: T,
  mensaje = "Valores distintos",
) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(esperado);
  if (a !== e) throw new Error(`${mensaje}: esperado ${e}, recibido ${a}`);
}

Deno.test("configuracion: el timeout usa 10000 ms por defecto y acepta los limites", () => {
  assertEquals(timeoutDesdeEntorno(undefined), 10000);
  assertEquals(timeoutDesdeEntorno("50"), 50);
  assertEquals(timeoutDesdeEntorno("1000"), 1000);
  assertEquals(timeoutDesdeEntorno("60000"), 60000);
});

Deno.test("configuracion: un timeout fuera de rango cae al valor seguro", () => {
  for (
    const valor of [
      "",
      "   ",
      "49",
      "60001",
      "10000.5",
      "abc",
      "Infinity",
      "-1",
    ]
  ) {
    assertEquals(timeoutDesdeEntorno(valor), 10000, `valor=${valor}`);
  }
});

Deno.test("configuracion: el puerto respeta el entorno y cae a 8000 si no es numero", () => {
  assertEquals(puertoDesdeEntorno(undefined), 8000);
  assertEquals(puertoDesdeEntorno("9000"), 9000);
  assertEquals(puertoDesdeEntorno("abc"), 8000);
});

Deno.test("configuracion: falta un secreto y la funcion no queda configurada", () => {
  const base = {
    SUPABASE_URL: "url-local",
    SUPABASE_SERVICE_ROLE_KEY: "clave-servicio",
    SUPABASE_ANON_KEY: "clave-anonima",
  };

  assertEquals(configuracionDesdeEntorno({}), null);
  assertEquals(configuracionDesdeEntorno({ ...base, SUPABASE_URL: "" }), null);
  assertEquals(
    configuracionDesdeEntorno({
      ...base,
      SUPABASE_SERVICE_ROLE_KEY: undefined,
    }),
    null,
  );
  assertEquals(
    configuracionDesdeEntorno({ ...base, SUPABASE_ANON_KEY: "" }),
    null,
  );
});

Deno.test("configuracion: los secretos completos respetan el redirect configurado", () => {
  const base = {
    SUPABASE_URL: "url-local",
    SUPABASE_SERVICE_ROLE_KEY: "clave-servicio",
    SUPABASE_ANON_KEY: "clave-anonima",
  };
  const esperado = {
    supabaseUrl: "url-local",
    serviceRoleKey: "clave-servicio",
    anonKey: "clave-anonima",
  };

  assertEquals(configuracionDesdeEntorno(base), {
    ...esperado,
    redirectTo: REDIRECT_POR_DEFECTO,
  });
  assertEquals(
    configuracionDesdeEntorno({ ...base, APP_REDIRECT_URL: "app://callback" }),
    {
      ...esperado,
      redirectTo: "app://callback",
    },
  );
  assertEquals(configuracionDesdeEntorno({ ...base, APP_REDIRECT_URL: "" }), {
    ...esperado,
    redirectTo: "",
  });
});
