// Pruebas del catálogo del front de pruebas. No necesitan navegador ni red.
// Ejecución: node tools/front-pruebas/test/presets.test.mjs

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import {
  ACCIONES,
  CONSULTAS,
  TOKENS,
  cuerpoAccion,
  interpolar,
  rutaAccion,
} from "../presets.mjs";

const raiz = join(dirname(fileURLToPath(import.meta.url)), "..");
const metodos = new Set(["GET", "POST", "PATCH", "DELETE"]);
const tipos = new Set(["funcion", "rest", "rpc"]);
const contexto = Object.fromEntries(
  TOKENS.map((clave, indice) => [
    clave,
    `00000000-0000-4000-8000-${String(indice + 1).padStart(12, "0")}`,
  ]),
);

function idsUnicos(lista, nombre) {
  const ids = lista.map((elemento) => elemento.id);
  assert.equal(new Set(ids).size, ids.length, `${nombre} tiene ids repetidos`);
}

idsUnicos(CONSULTAS, "consultas");
idsUnicos(ACCIONES, "acciones");

assert.ok(CONSULTAS.length >= 10, "debe haber consultas para las tablas principales");
assert.ok(ACCIONES.length >= 15, "debe haber acciones para los flujos principales");

for (const consulta of CONSULTAS) {
  assert.ok(consulta.id && consulta.etiqueta && consulta.nota, `consulta incompleta: ${consulta.id}`);
  assert.match(consulta.ruta, /^\/rest\/v1\//, `ruta de consulta inválida: ${consulta.id}`);
  assert.ok(!interpolar(consulta.ruta, contexto).includes("{{"), `marcador sin valor en ${consulta.id}`);
}

for (const accion of ACCIONES) {
  assert.ok(accion.id && accion.etiqueta && accion.nota, `acción incompleta: ${accion.id}`);
  assert.ok(tipos.has(accion.tipo), `tipo desconocido en ${accion.id}`);
  assert.ok(metodos.has(accion.metodo), `método desconocido en ${accion.id}`);
  assert.notEqual(accion.metodo, "GET", `una acción no debería ser GET: ${accion.id}`);
  assert.ok(accion.ruta.startsWith("/"), `ruta relativa esperada en ${accion.id}`);
  if (accion.tipo === "rpc") {
    assert.match(accion.ruta, /^\/rest\/v1\/rpc\//, `ruta RPC inválida en ${accion.id}`);
  }
  assert.equal(typeof accion.cuerpo, "object", `cuerpo esperado en ${accion.id}`);
  assert.ok(!Array.isArray(accion.cuerpo), `cuerpo debe ser objeto en ${accion.id}`);
  assert.ok(!cuerpoAccion(accion, contexto).includes("{{"), `marcador sin valor en ${accion.id}`);
  assert.ok(!rutaAccion(accion, contexto).includes("{{"), `marcador sin valor en la ruta de ${accion.id}`);
}

assert.equal(interpolar("{{usuario}}", { usuario: "abc" }), "abc");
assert.equal(interpolar("{{sin_valor}}", {}), "{{sin_valor}}");
assert.deepEqual(JSON.parse(cuerpoAccion(ACCIONES[0], contexto)), {
  email: "empleado@ejemplo.test",
  nombre_completo: "Empleado Ejemplo",
  rol: "empleado",
  centro_costo_id: contexto.centro,
});

const app = readFileSync(join(raiz, "app.js"), "utf8");
assert.ok(app.includes("v-${clave}"), "los campos de memoria se construyen desde TOKENS");
const html = readFileSync(join(raiz, "index.html"), "utf8");
assert.ok(html.includes('id="campos-id"'), "falta el contenedor de valores de prueba");
assert.ok(!/localStorage|sessionStorage/i.test(app), "el front no debe persistir estado");
assert.ok(!/document\.cookie/i.test(app), "el front no debe escribir cookies");

const provisional = ["index.html", "app.js", "presets.mjs", "styles.css"];
const secretos = /service_role|SUPABASE_SERVICE_ROLE_KEY|eyJ[A-Za-z0-9_-]{20,}|[a-z0-9-]+\.supabase\.co/i;
for (const archivo of provisional) {
  const contenido = readFileSync(join(raiz, archivo), "utf8");
  assert.ok(!secretos.test(contenido), `${archivo} parece contener secretos o una URL real`);
}

console.log(`front de pruebas: ${CONSULTAS.length} consultas, ${ACCIONES.length} acciones, ${TOKENS.length} marcadores, 0 fallos`);
