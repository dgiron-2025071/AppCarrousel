#!/usr/bin/env node
// Convierte un listado de CECO (TSV o CSV con columnas codigo,nombre) en SQL
// para cargarlo en public.centros_costo con su jerarquía.
//
// Uso:
//   node tools/importar-ceco/importar.mjs listado.tsv \
//     --empresa CARR --raiz CORP --raiz-nombre "Corporación Carrousel" > ceco.sql
//   supabase db query --remote -f ceco.sql
//
// El listado con datos reales no se versiona: se exporta de la fuente (por
// ejemplo, caja chica) en el momento de la carga.

import fs from 'node:fs';

import { construirJerarquia, generarSql, leerListado } from './ceco.mjs';

function argumento(nombre, porDefecto) {
  const i = process.argv.indexOf(`--${nombre}`);
  return i > 0 && process.argv[i + 1] ? process.argv[i + 1] : porDefecto;
}

const archivo = process.argv[2];
if (!archivo || archivo.startsWith('--')) {
  console.error('Uso: node importar.mjs <listado.tsv|csv> --empresa CODIGO [--raiz CODIGO] [--raiz-nombre NOMBRE]');
  process.exit(1);
}

const empresaCodigo = argumento('empresa');
if (!empresaCodigo) {
  console.error('Falta --empresa con el código de la empresa (public.empresas.codigo).');
  process.exit(1);
}

const filas = leerListado(fs.readFileSync(archivo, 'utf8'));
const { centros, conflictos, sinPadre, descartadas } = construirJerarquia(filas);

process.stdout.write(generarSql({
  centros,
  empresaCodigo,
  raizCodigo: argumento('raiz', 'RAIZ'),
  raizNombre: argumento('raiz-nombre', 'Empresa'),
}));

// El resumen va a stderr para no mezclarse con el SQL.
console.error(`CECO leídos: ${filas.length}`);
console.error(`CECO a cargar: ${centros.length} (${centros.filter((c) => !c.padre).length} de primer nivel)`);
console.error(`Filas descartadas (sin código o de prueba): ${descartadas.length}`);
for (const c of conflictos) {
  console.error(`Código repetido ${c.codigo}: se conserva "${c.conservado}", se descarta "${c.descartado}"`);
}
for (const c of sinPadre) {
  console.error(`Parque creado ${c.codigo} "${c.nombre}" para ${c.hijos} sub-centros sin padre`);
}
