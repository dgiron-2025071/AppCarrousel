import test from 'node:test';
import assert from 'node:assert/strict';
import { parsearCsv, normalizarEncabezado } from '../lib/csv.mjs';

test('normaliza encabezados con acentos y espacios', () => {
  assert.equal(normalizarEncabezado('Código'), 'codigo');
  assert.equal(normalizarEncabezado(' Nombre del centro '), 'nombre_del_centro');
  assert.equal(normalizarEncabezado('CECO-Padre'), 'ceco_padre');
});

test('parsea un CSV simple y mapea los alias de encabezado', () => {
  const { filas } = parsearCsv(
    'Código,Nombre,Padre\n100,Parque Central,\n110,Operaciones,100\n',
  );

  assert.deepEqual(filas, [
    { linea: 2, codigo: '100', nombre: 'Parque Central', padre: '' },
    { linea: 3, codigo: '110', nombre: 'Operaciones', padre: '100' },
  ]);
});

test('detecta el punto y coma como delimitador', () => {
  const { filas } = parsearCsv('codigo;nombre;padre\nA;Centro A;R\n');

  assert.equal(filas.length, 1);
  assert.equal(filas[0].codigo, 'A');
  assert.equal(filas[0].padre, 'R');
});

test('detecta el tabulador como delimitador', () => {
  const { filas } = parsearCsv('codigo\tnombre\tpadre\nA\tCentro A\tR\n');

  assert.equal(filas[0].nombre, 'Centro A');
  assert.equal(filas[0].padre, 'R');
});

test('respeta comas y comillas escapadas dentro de un campo', () => {
  const { filas } = parsearCsv(
    'codigo,nombre,padre\nA,"Parque ""El Sol"", zona 1",R\n',
  );

  assert.equal(filas[0].nombre, 'Parque "El Sol", zona 1');
});

test('acepta saltos de línea dentro de un campo y conserva la línea física', () => {
  const { filas } = parsearCsv(
    'codigo,nombre,padre\nA,"Centro\nGrande",R\nB,Centro B,A\n',
  );

  assert.deepEqual(filas, [
    { linea: 2, codigo: 'A', nombre: 'Centro\nGrande', padre: 'R' },
    { linea: 4, codigo: 'B', nombre: 'Centro B', padre: 'A' },
  ]);
});

test('ignora BOM, CRLF, comentarios y líneas vacías', () => {
  const { filas } = parsearCsv(
    '\uFEFF# Jerarquía de ejemplo\r\ncodigo,nombre,padre\r\n\r\nA,Centro A,\r\n# nota\r\nB,Centro B,A\r\n',
  );

  assert.deepEqual(filas, [
    { linea: 4, codigo: 'A', nombre: 'Centro A', padre: '' },
    { linea: 6, codigo: 'B', nombre: 'Centro B', padre: 'A' },
  ]);
});

test('permite un CSV sin columna padre', () => {
  const { filas } = parsearCsv('codigo,nombre\nA,Centro A\n');

  assert.equal(filas[0].padre, '');
});

test('rechaza un CSV sin las columnas obligatorias', () => {
  assert.throws(
    () => parsearCsv('clave,detalle\nA,Centro A\n'),
    /Faltan columnas obligatorias: codigo, nombre/,
  );
});

test('rechaza un archivo vacío', () => {
  assert.throws(() => parsearCsv('\r\n# solo comentarios\r\n'), /El CSV está vacío/);
});

test('rechaza comillas sin cerrar', () => {
  assert.throws(
    () => parsearCsv('codigo,nombre\nA,"Centro sin cierre\n'),
    /comillas sin cerrar/,
  );
});
