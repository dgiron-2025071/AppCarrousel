import test from 'node:test';
import assert from 'node:assert/strict';
import {
  construirPlan,
  generarSql,
  normalizarCodigo,
  normalizarNombre,
} from '../lib/ceco.mjs';

test('normaliza el código sin perder ceros a la izquierda', () => {
  assert.equal(normalizarCodigo('057.01'), '05701');
  assert.equal(normalizarCodigo(' 057-01 '), '05701');
  assert.equal(normalizarCodigo('abc_12/3'), 'ABC123');
  assert.equal(normalizarCodigo('CECO 01'), 'CECO01');
});

test('rechaza códigos vacíos, no textuales o con caracteres inválidos', () => {
  assert.throws(() => normalizarCodigo('   '), /no puede estar vacío/);
  assert.throws(() => normalizarCodigo(123), /debe ser texto/);
  assert.throws(() => normalizarCodigo('A#B'), /caracteres no permitidos/);
});

test('rechaza un código que supera el largo máximo', () => {
  assert.throws(() => normalizarCodigo('A'.repeat(33)), /supera 32 caracteres/);
});

test('normaliza el nombre y rechaza vacíos o demasiado largos', () => {
  assert.equal(normalizarNombre('  Parque   Central  '), 'Parque Central');
  assert.throws(() => normalizarNombre('   '), /no puede estar vacío/);
  assert.throws(() => normalizarNombre('N'.repeat(161)), /supera 160 caracteres/);
});

test('construye un plan con jerarquía y sin errores', () => {
  const plan = construirPlan([
    { linea: 2, codigo: '100', nombre: 'Parque', padre: '' },
    { linea: 3, codigo: '110', nombre: 'Operaciones', padre: '100' },
    { linea: 4, codigo: '111', nombre: 'Atracciones', padre: '110' },
  ]);

  assert.deepEqual(plan.errores, []);
  assert.deepEqual(plan.advertencias, []);
  assert.deepEqual(plan.nodos.map((nodo) => [nodo.codigo, nodo.padre]), [
    ['100', null],
    ['110', '100'],
    ['111', '110'],
  ]);
});

test('detecta códigos duplicados aunque cambie el formato', () => {
  const plan = construirPlan([
    { linea: 2, codigo: '057.01', nombre: 'Uno', padre: '' },
    { linea: 3, codigo: '057-01', nombre: 'Dos', padre: '' },
  ]);

  assert.equal(plan.nodos.length, 1);
  assert.match(plan.errores[0], /ya apareció en la línea 2/);
});

test('rechaza que un centro sea su propio padre', () => {
  const plan = construirPlan([
    { linea: 2, codigo: '100', nombre: 'Parque', padre: '100' },
  ]);

  assert.match(plan.errores[0], /no puede ser su propio padre/);
});

test('detecta ciclos en la jerarquía', () => {
  const plan = construirPlan([
    { linea: 2, codigo: 'A', nombre: 'Centro A', padre: 'B' },
    { linea: 3, codigo: 'B', nombre: 'Centro B', padre: 'A' },
  ]);

  assert.equal(plan.errores.length, 1);
  assert.match(plan.errores[0], /Ciclo de centros de costo: A → B → A/);
});

test('advierte cuando el padre no viene en el archivo', () => {
  const plan = construirPlan([
    { linea: 2, codigo: '110', nombre: 'Operaciones', padre: '100' },
  ]);

  assert.deepEqual(plan.errores, []);
  assert.equal(plan.advertencias.length, 1);
  assert.match(plan.advertencias[0], /el padre 100 no viene en el archivo/);
});

test('acumula todos los errores de las filas', () => {
  const plan = construirPlan([
    { linea: 2, codigo: '', nombre: 'Sin código', padre: '' },
    { linea: 3, codigo: 'A', nombre: '', padre: '' },
    { linea: 4, codigo: 'B', nombre: 'Centro B', padre: 'B#' },
  ]);

  assert.equal(plan.errores.length, 3);
});

test('genera SQL idempotente con alta, enlace y raíz', () => {
  const { nodos } = construirPlan([
    { linea: 2, codigo: '100', nombre: 'Parque', padre: '' },
    { linea: 3, codigo: '110', nombre: 'Operaciones', padre: '100' },
  ]);
  const sql = generarSql({ empresa: 'EMPRESA-A', nodos });

  assert.match(sql, /begin;/);
  assert.match(sql, /on conflict \(empresa_id, codigo\) do update/);
  assert.match(sql, /raise exception 'Padres no encontrados en la empresa %: %'/);
  assert.match(sql, /set padre_id = null/);
  assert.match(sql, /commit;/);
});

test('escapa comillas simples en códigos y nombres', () => {
  const { nodos } = construirPlan([
    { linea: 2, codigo: 'A', nombre: "Parque O'Higgins", padre: '' },
  ]);
  const sql = generarSql({ empresa: 'EMPRESA-A', nodos });

  assert.match(sql, /Parque O''Higgins/);
});

test('incluye las advertencias como comentarios del SQL', () => {
  const { nodos, advertencias } = construirPlan([
    { linea: 2, codigo: '110', nombre: 'Operaciones', padre: '100' },
  ]);
  const sql = generarSql({ empresa: 'EMPRESA-A', nodos, advertencias });

  assert.match(sql, /-- ADVERTENCIA: Línea 2: el padre 100/);
});

test('exige empresa y al menos un centro', () => {
  assert.throws(() => generarSql({ empresa: '', nodos: [{ codigo: 'A' }] }), /Falta el código/);
  assert.throws(() => generarSql({ empresa: 'A', nodos: [] }), /No hay centros de costo/);
});
