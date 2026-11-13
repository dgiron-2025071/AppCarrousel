#!/usr/bin/env node
/**
 * Importa centros de costo desde un CSV y genera SQL idempotente.
 *
 * Uso:
 *   node tools/importar-ceco/index.mjs \
 *     --empresa EMPRESA-A \
 *     --archivo datos/centros.csv \
 *     --salida datos/importar-centros.sql
 *
 * Sin `--salida` el SQL se escribe en stdout. Los mensajes van a stderr para
 * poder redirigir el SQL sin ensuciarlo.
 */

import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { parsearCsv } from './lib/csv.mjs';
import { construirPlan, generarSql } from './lib/ceco.mjs';

const AYUDA = `Importa centros de costo desde CSV.

Opciones:
  --empresa <código>   Código de la empresa destino (obligatorio).
  --archivo <ruta>     CSV de entrada (obligatorio).
  --salida <ruta>      Archivo SQL de salida. Sin esta opción usa stdout.
  --help               Muestra esta ayuda.

Columnas del CSV:
  codigo  Código del centro (obligatorio).
  nombre  Nombre visible (obligatorio).
  padre   Código del centro padre. Vacío para una raíz.

El SQL resultante debe ejecutarse con service_role: crear raíces y mover
centros de costo está reservado a ese rol. La importación se puede repetir
sin duplicar filas.`;

function leerArgumentos(argv) {
  const opciones = {};

  for (let i = 0; i < argv.length; i++) {
    const argumento = argv[i];

    if (argumento === '--help' || argumento === '-h') {
      opciones.ayuda = true;
      continue;
    }

    if (argumento === '--empresa' || argumento === '--archivo' || argumento === '--salida') {
      const valor = argv[i + 1];
      if (!valor || valor.startsWith('--')) {
        throw new Error(`Falta el valor de ${argumento}`);
      }
      opciones[argumento.slice(2)] = valor;
      i++;
      continue;
    }

    throw new Error(`Opción desconocida: ${argumento}`);
  }

  return opciones;
}

async function principal() {
  const opciones = leerArgumentos(process.argv.slice(2));

  if (opciones.ayuda) {
    process.stdout.write(`${AYUDA}\n`);
    return;
  }

  if (!opciones.empresa || !opciones.archivo) {
    throw new Error('Faltan --empresa o --archivo. Usa --help para ver la ayuda.');
  }

  const rutaEntrada = resolve(opciones.archivo);
  const contenido = await readFile(rutaEntrada, 'utf8');
  const { filas } = parsearCsv(contenido);

  if (filas.length === 0) {
    throw new Error(`El archivo ${rutaEntrada} no tiene filas de datos`);
  }

  const { nodos, errores, advertencias } = construirPlan(filas);

  if (errores.length > 0) {
    process.stderr.write(`No se generó SQL: ${errores.length} error(es).\n`);
    for (const error of errores) {
      process.stderr.write(`  - ${error}\n`);
    }
    process.exitCode = 1;
    return;
  }

  for (const advertencia of advertencias) {
    process.stderr.write(`ADVERTENCIA: ${advertencia}\n`);
  }

  const sql = generarSql({ empresa: opciones.empresa, nodos, advertencias });

  if (opciones.salida) {
    const rutaSalida = resolve(opciones.salida);
    await writeFile(rutaSalida, sql, 'utf8');
    process.stderr.write(
      `Listo: ${nodos.length} centro(s) para ${opciones.empresa} en ${rutaSalida}\n`,
    );
  } else {
    process.stdout.write(sql);
  }
}

principal().catch((error) => {
  process.stderr.write(`[error] ${error.message}\n`);
  process.exitCode = 1;
});
