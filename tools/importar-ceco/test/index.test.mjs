import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const indice = fileURLToPath(new URL('../index.mjs', import.meta.url));
const csv = 'codigo,nombre,padre\nA,Centro A,\nB,Centro B,A\n';

function ejecutar(dir, opciones) {
  return spawnSync(
    process.execPath,
    [indice, '--empresa', 'EMPRESA-A', '--archivo', join(dir, 'centros.csv'), ...opciones],
    { encoding: 'utf8' },
  );
}

test('la CLI rechaza archivos que superan --max-bytes', () => {
  const dir = mkdtempSync(join(tmpdir(), 'ceco-max-bytes-'));
  try {
    writeFileSync(join(dir, 'centros.csv'), csv, 'utf8');
    const resultado = ejecutar(dir, ['--max-bytes', '10']);

    assert.equal(resultado.status, 1);
    assert.match(resultado.stderr, /supera el límite de 10 bytes/);
    assert.equal(resultado.stdout, '');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('la CLI rechaza CSVs que superan --max-nodos', () => {
  const dir = mkdtempSync(join(tmpdir(), 'ceco-max-nodos-'));
  try {
    writeFileSync(join(dir, 'centros.csv'), csv, 'utf8');
    const resultado = ejecutar(dir, ['--max-nodos', '1']);

    assert.equal(resultado.status, 1);
    assert.match(resultado.stderr, /supera el límite de 1 filas/);
    assert.equal(resultado.stdout, '');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('la CLI rechaza --empresa repetido', () => {
  const dir = mkdtempSync(join(tmpdir(), 'ceco-empresa-duplicada-'));
  try {
    writeFileSync(join(dir, 'centros.csv'), csv, 'utf8');
    const resultado = spawnSync(process.execPath, [
      indice,
      '--empresa', 'EMPRESA-A',
      '--empresa', 'EMPRESA-B',
      '--archivo', join(dir, 'centros.csv'),
    ], { encoding: 'utf8' });

    assert.equal(resultado.status, 1);
    assert.match(resultado.stderr, /Opción repetida: --empresa/);
    assert.equal(resultado.stdout, '');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('la CLI rechaza banderas y límites repetidos', () => {
  const dir = mkdtempSync(join(tmpdir(), 'ceco-opciones-duplicadas-'));
  try {
    writeFileSync(join(dir, 'centros.csv'), csv, 'utf8');
    const base = ['--empresa', 'EMPRESA-A', '--archivo', join(dir, 'centros.csv')];
    for (const [opcion, mensaje] of [
      [['--forzar-raices', '--forzar-raices'], '--forzar-raices'],
      [['--max-bytes', '1000', '--max-bytes', '2000'], '--max-bytes'],
    ]) {
      const resultado = spawnSync(process.execPath, [
        indice, ...base, ...opcion,
      ], { encoding: 'utf8' });

      assert.equal(resultado.status, 1);
      assert.match(resultado.stderr, new RegExp(`Opción repetida: ${mensaje}`));
      assert.equal(resultado.stdout, '');
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
