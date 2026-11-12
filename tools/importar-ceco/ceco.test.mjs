import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  construirJerarquia,
  generarSql,
  leerListado,
  limpiarNombre,
  nombrePadre,
  normalizarCodigo,
} from './ceco.mjs';

test('unifica las tres formas de escribir un hijo', () => {
  for (const codigo of ['057.01', '057-01', '05701']) {
    assert.deepEqual(normalizarCodigo(codigo), { codigo: '057.01', padre: '057' });
  }
});

test('los códigos de primer nivel no tienen padre', () => {
  assert.deepEqual(normalizarCodigo('105'), { codigo: '105', padre: null });
  assert.deepEqual(normalizarCodigo(' 1000 '), { codigo: '1000', padre: null });
});

test('ignora códigos vacíos o NULL', () => {
  assert.equal(normalizarCodigo(''), null);
  assert.equal(normalizarCodigo('NULL'), null);
  assert.equal(normalizarCodigo(undefined), null);
});

test('quita el código repetido entre paréntesis y los espacios dobles', () => {
  assert.equal(limpiarNombre('Andaria Cinestar Kiddies (057.05)', '057.05'), 'Andaria Cinestar Kiddies');
  assert.equal(limpiarNombre('Celajes Quiche  Cajas Magicas', '071.02'), 'Celajes Quiche Cajas Magicas');
  assert.equal(limpiarNombre('Logistica (114)', '114'), 'Logistica');
  assert.equal(limpiarNombre('Promocionales (Bodegueros)', '109'), 'Promocionales (Bodegueros)');
});

test('arma la jerarquía con los padres antes que los hijos', () => {
  const { centros } = construirJerarquia([
    { codigo: '05701', nombre: 'Andaria Kiddies' },
    { codigo: '057', nombre: 'Andaria' },
    { codigo: '103-01', nombre: 'Bodega Amatitlan' },
    { codigo: '103', nombre: 'Bodega' },
  ]);
  assert.deepEqual(centros, [
    { codigo: '057', nombre: 'Andaria', padre: null },
    { codigo: '103', nombre: 'Bodega', padre: null },
    { codigo: '057.01', nombre: 'Andaria Kiddies', padre: '057' },
    { codigo: '103.01', nombre: 'Bodega Amatitlan', padre: '103' },
  ]);
});

test('reporta duplicados y prefiere el nombre no genérico', () => {
  const { centros, conflictos } = construirJerarquia([
    { codigo: '025', nombre: 'Otro1' },
    { codigo: '025', nombre: 'Pradera Escuintla' },
    { codigo: '105', nombre: 'Administracion' },
    { codigo: '105', nombre: 'Administracion' },
    { codigo: '057.05', nombre: 'Andaria Cinestar Kiddies' },
    { codigo: '057.05', nombre: 'Andaria Cinestar Kiddies (057.05)' },
  ]);
  assert.deepEqual(conflictos, [
    { codigo: '025', conservado: 'Pradera Escuintla', descartado: 'Otro1' },
  ]);
  assert.equal(centros.find((c) => c.codigo === '025').nombre, 'Pradera Escuintla');
  assert.equal(centros.filter((c) => c.codigo === '105').length, 1);
  assert.equal(centros.filter((c) => c.codigo === '057.05').length, 1);
});

test('crea el parque que falta con el nombre común de sus hijos', () => {
  const { centros, sinPadre } = construirJerarquia([
    { codigo: '060.01', nombre: 'Cinestar Kiddies' },
    { codigo: '060.02', nombre: 'Cinestar Cajas Magicas' },
    { codigo: '06803', nombre: 'Cine Xela Cm' },
  ]);
  assert.deepEqual(sinPadre, [
    { codigo: '060', nombre: 'Cinestar', hijos: 2 },
    { codigo: '068', nombre: 'Cine Xela', hijos: 1 },
  ]);
  assert.deepEqual(centros.filter((c) => !c.padre).map((c) => c.codigo), ['060', '068']);
  assert.equal(centros.find((c) => c.codigo === '060.02').padre, '060');
});

test('descarta registros de prueba', () => {
  const { centros, descartadas } = construirJerarquia([
    { codigo: '000.0123', nombre: 'Kenny-Pruebas' },
    { codigo: '105', nombre: 'Administracion' },
  ]);
  assert.deepEqual(centros.map((c) => c.codigo), ['105']);
  assert.equal(descartadas.length, 1);
});

test('nombre del parque a partir de sus sub-centros', () => {
  assert.equal(nombrePadre(['Futeca Dinamia Kiddies', 'Futeca Dinamia Cajas Magicas']), 'Futeca Dinamia');
  assert.equal(nombrePadre(['Vidu Surf Van']), 'Vidu Surf Van');
  assert.equal(nombrePadre(['Los Encuentros Kiddies', 'Los Encuentro Cajas Magicas']), 'Los Encuentros');
});

test('lee TSV de MySQL y CSV', () => {
  const tsv = 'codigo\tnombre\n057\tAndaria\nNULL\tBrayan\n';
  assert.deepEqual(leerListado(tsv), [
    { codigo: '057', nombre: 'Andaria' },
    { codigo: 'NULL', nombre: 'Brayan' },
  ]);
  assert.deepEqual(leerListado('\uFEFFcodigo,nombre\r\n105,Administracion\r\n'), [
    { codigo: '105', nombre: 'Administracion' },
  ]);
  assert.throws(() => leerListado('code,name\n1,a'), /codigo/);
});

test('genera SQL idempotente y escapa comillas', () => {
  const salida = generarSql({
    centros: [
      { codigo: '057', nombre: "D'Andaria", padre: null },
      { codigo: '057.01', nombre: 'Kiddies', padre: '057' },
    ],
    empresaCodigo: 'CARR',
    raizCodigo: 'CORP',
    raizNombre: 'Corporación Carrousel',
  });
  assert.match(salida, /^-- Generado/);
  assert.match(salida, /'D''Andaria'/);
  // Cada CECO se cuelga de su padre dentro de su propia sentencia.
  assert.match(salida, /'057', 'D''Andaria'\n[^;]*p\.codigo = 'CORP'/);
  assert.match(salida, /'057\.01', 'Kiddies'\n[^;]*p\.codigo = '057'\n/);
  assert.equal((salida.match(/on conflict \(empresa_id, codigo\)/g) ?? []).length, 3);
  assert.match(salida, /commit;\n$/);
});
