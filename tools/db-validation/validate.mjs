import EmbeddedPostgres from 'embedded-postgres';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '..', '..');
const migrationsDir = path.join(repo, 'supabase', 'migrations');
const dataDir = path.join(os.tmpdir(), `carrousel-db-validation-${process.pid}-${Date.now()}`);
const port = Number(process.env.PGPORT ?? 55434);
const keepData = process.argv.includes('--keep');

const pg = new EmbeddedPostgres({
  databaseDir: dataDir,
  user: 'postgres',
  password: 'postgres',
  port,
  // persistent:true evita el EBUSY al apagar en Windows; el directorio se
  // elimina en el bloque finally.
  persistent: true,
  initdbFlags: ['--encoding=UTF8', '--locale=C'],
  onLog: () => {},
  onError: (e) => console.error('[pg:err]', e),
});

let exitCode = 0;

async function main() {
await pg.initialise();
await pg.start();
await pg.createDatabase('carrousel_test');
const client = pg.getPgClient('carrousel_test');
await client.connect();

const q = (sql, params = []) => client.query(sql, params);
const scalar = async (sql, params = []) => {
  const r = await q(sql, params);
  return r.rows[0] ? Object.values(r.rows[0])[0] : undefined;
};

let pass = 0;
let fail = 0;
const failures = [];
function ok(name, cond, detail = '') {
  if (cond) {
    pass++;
    console.log(`  OK   ${name}`);
  } else {
    fail++;
    failures.push(`${name}${detail ? ` — ${detail}` : ''}`);
    console.log(`  FAIL ${name}${detail ? ` — ${detail}` : ''}`);
  }
}
function eq(name, actual, expected) {
  ok(name, JSON.stringify(actual) === JSON.stringify(expected),
    `esperado=${JSON.stringify(expected)} actual=${JSON.stringify(actual)}`);
}
function group(name) {
  console.log(`\n== ${name} ==`);
}

async function applyFile(label, file) {
  process.stdout.write(`- ${label} ... `);
  try {
    await q(fs.readFileSync(file, 'utf8'));
    console.log('OK');
  } catch (error) {
    console.log('FALLÓ');
    console.error(error.message);
    throw error;
  }
}

async function expectError(name, sql, params, code) {
  await q('begin');
  try {
    await q(sql, params);
    ok(name, false, 'no lanzó error');
  } catch (error) {
    ok(name, error.code === code, `code=${error.code}, esperado=${code}, msg=${error.message}`);
  } finally {
    await q('rollback');
  }
}

const claims = (sub, empresa_id, centro_costo_id, rol) => ({
  sub,
  app_metadata: { empresa_id, centro_costo_id, rol },
});

async function withRole(role, jwtClaims, fn) {
  await q('begin');
  try {
    await q(`set local role ${role}`);
    await q(`select set_config('request.jwt.claims', $1, true)`, [JSON.stringify(jwtClaims)]);
    return await fn();
  } finally {
    await q('rollback');
  }
}

async function expectRoleError(name, role, jwtClaims, sql, params, code) {
  await q('begin');
  try {
    await q(`set local role ${role}`);
    await q(`select set_config('request.jwt.claims', $1, true)`, [JSON.stringify(jwtClaims)]);
    await q(sql, params);
    ok(name, false, 'no lanzó error');
  } catch (error) {
    ok(name, error.code === code, `code=${error.code}, esperado=${code}, msg=${error.message}`);
  } finally {
    await q('rollback');
  }
}

// -----------------------------------------------------------------------------
// Migraciones
// -----------------------------------------------------------------------------
group('Aplicación de migraciones en PostgreSQL real');
await applyFile('stub Supabase', 'supabase-stub.sql');

const files = fs.readdirSync(migrationsDir).filter((f) => f.endsWith('.sql')).sort();
for (const file of files) {
  await applyFile(file, path.join(migrationsDir, file));
}

process.stdout.write('- grants de service_role (emulación Supabase) ... ');
await q(`
  grant usage on schema public to service_role;
  grant all on all tables in schema public to service_role;
  grant all on all sequences in schema public to service_role;
`);
console.log('OK');

// -----------------------------------------------------------------------------
// Datos de prueba
// -----------------------------------------------------------------------------
const A = {
  empresa: '11111111-1111-4111-8111-111111111111',
  root: 'a1000000-0000-4000-8000-000000000001',
  child: 'a1000000-0000-4000-8000-000000000002',
  grand: 'a1000000-0000-4000-8000-000000000003',
  sibling: 'a1000000-0000-4000-8000-000000000004',
};
const B = {
  empresa: '22222222-2222-4222-8222-222222222222',
  root: 'b1000000-0000-4000-8000-000000000001',
};
const U = {
  empA: 'e1000000-0000-4000-8000-000000000001',
  gerA: 'e1000000-0000-4000-8000-000000000002',
  empGrand: 'e1000000-0000-4000-8000-000000000003',
  empB: 'e1000000-0000-4000-8000-000000000004',
  gerRoot: 'e1000000-0000-4000-8000-000000000005',
  noClaims: 'e1000000-0000-4000-8000-000000000006',
};
const P = {
  root: 'c1000000-0000-4000-8000-000000000001',
  child: 'c1000000-0000-4000-8000-000000000002',
  grand: 'c1000000-0000-4000-8000-000000000003',
  sibling: 'c1000000-0000-4000-8000-000000000004',
  b: 'c1000000-0000-4000-8000-000000000005',
};
const J = {
  aCerrada: 'd1000000-0000-4000-8000-000000000001',
  grandAbierta: 'd1000000-0000-4000-8000-000000000002',
  bCerrada: 'd1000000-0000-4000-8000-000000000003',
};
const S = {
  aPendiente: 'f1000000-0000-4000-8000-000000000001',
  aAprobada: 'f1000000-0000-4000-8000-000000000002',
  grandPendiente: 'f1000000-0000-4000-8000-000000000003',
  bPendiente: 'f1000000-0000-4000-8000-000000000004',
  adminPropia: 'f1000000-0000-4000-8000-000000000005',
  aCancelable: 'f1000000-0000-4000-8000-000000000006',
};

group('Datos de prueba');
await q(`
  insert into public.empresas (id, codigo, nombre) values
    ($1, 'EMPRESA-A', 'Empresa A'),
    ($2, 'EMPRESA-B', 'Empresa B');
`, [A.empresa, B.empresa]);

await q(`
  insert into public.centros_costo (id, empresa_id, padre_id, codigo, nombre) values
    ($1, $2, null, 'A-ROOT', 'Centro raíz A'),
    ($3, $2, $1, 'A-CHILD', 'Centro hijo A'),
    ($4, $2, $3, 'A-GRAND', 'Centro nieto A'),
    ($5, $2, $1, 'A-SIB', 'Centro hermano A'),
    ($6, $7, null, 'B-ROOT', 'Centro raíz B');
`, [A.root, A.empresa, A.child, A.grand, A.sibling, B.root, B.empresa]);

await q(`
  insert into public.parques
    (id, empresa_id, centro_costo_id, codigo, nombre, latitud, longitud, radio_metros)
  values
    ($1, $2, $3, 'P-ROOT', 'Parque raíz A', 14.6349, -90.5069, 100),
    ($4, $2, $5, 'P-CHILD', 'Parque hijo A', 14.6350, -90.5070, 100),
    ($6, $2, $7, 'P-GRAND', 'Parque nieto A', 14.6351, -90.5071, 100),
    ($8, $2, $9, 'P-SIB', 'Parque hermano A', 14.6352, -90.5072, 100),
    ($10, $11, $12, 'P-B', 'Parque B', 14.6400, -90.5100, 100);
`, [P.root, A.empresa, A.root, P.child, A.child, P.grand, A.grand, P.sibling, A.sibling, P.b, B.empresa, B.root]);

const appMeta = (empresa, centro, rol) =>
  JSON.stringify({ empresa_id: empresa, centro_costo_id: centro, rol });

await q(`
  insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data) values
    ($1, 'emp.a@example.com',  $2::jsonb, '{"nombre_completo":"Empleado A"}'::jsonb),
    ($3, 'ger.a@example.com',  $4::jsonb, '{"nombre_completo":"Admin A"}'::jsonb),
    ($5, 'emp.grand@example.com', $6::jsonb, '{"nombre_completo":"Empleado Nieto"}'::jsonb),
    ($7, 'emp.b@example.com',  $8::jsonb, '{"nombre_completo":"Empleado B"}'::jsonb),
    ($9, 'ger.root@example.com', $10::jsonb, '{"nombre_completo":"Admin Raíz"}'::jsonb),
    ($11, 'sin.claims@example.com', '{}'::jsonb, '{"nombre_completo":"Sin Claims"}'::jsonb);
`, [
  U.empA, appMeta(A.empresa, A.child, 'empleado'),
  U.gerA, appMeta(A.empresa, A.child, 'admin'),
  U.empGrand, appMeta(A.empresa, A.grand, 'empleado'),
  U.empB, appMeta(B.empresa, B.root, 'empleado'),
  U.gerRoot, appMeta(A.empresa, A.root, 'admin'),
  U.noClaims,
]);

// Jornadas históricas: se siembran como dueño (auth.uid() NULL), igual que una
// carga administrativa. Sirven para probar visibilidad entre roles.
await q(`
  insert into public.jornadas (
    id, empresa_id, empleado_id, parque_id, entrada_en, salida_en,
    entrada_lat, entrada_lon, entrada_precision_metros, entrada_dentro_geocerca,
    salida_lat, salida_lon, salida_precision_metros, salida_dentro_geocerca
  ) values
    ($1, $2, $3, $4, now() - interval '8 hours', now() - interval '1 hour',
     14.6350, -90.5070, 5, true, 14.6350, -90.5070, 5, true),
    ($5, $2, $6, $7, now() - interval '2 hours', null,
     14.6351, -90.5071, 5, true, null, null, null, null),
    ($8, $9, $10, $11, now() - interval '6 hours', now() - interval '3 hours',
     14.6400, -90.5100, 5, true, 14.6400, -90.5100, 5, true);
`, [
  J.aCerrada, A.empresa, U.empA, P.child,
  J.grandAbierta, U.empGrand, P.grand,
  J.bCerrada, B.empresa, U.empB, P.b,
]);

// Solicitudes históricas en todos los estados.
await q(`
  insert into public.solicitudes_horas_extras (
    id, empresa_id, empleado_id, centro_costo_id, inicio, fin,
    justificacion, estado, comentario_admin, revisado_por, revisado_en
  ) values
    ($1, $2, $3, $4, now() - interval '2 days', now() - interval '2 days' + interval '3 hours',
     'Apoyo en inventario del parque central', 'pendiente', null, null, null),
    ($5, $2, $3, $4, now() - interval '3 days', now() - interval '3 days' + interval '2 hours',
     'Cobertura de turno especial', 'aprobada', 'Aprobado por necesidad operativa', $6, now() - interval '2 days'),
    ($7, $2, $8, $9, now() - interval '1 day', now() - interval '1 day' + interval '4 hours',
     'Apoyo en montaje del parque grande', 'pendiente', null, null, null),
    ($10, $11, $12, $13, now() - interval '1 day', now() - interval '1 day' + interval '3 hours',
     'Solicitud de la empresa B', 'pendiente', null, null, null),
    ($14, $2, $15, $16, now() - interval '1 day', now() - interval '1 day' + interval '3 hours',
     'Solicitud propia del admin', 'pendiente', null, null, null),
    ($17, $2, $3, $4, now() - interval '1 day', now() - interval '1 day' + interval '2 hours',
     'Solicitud enviada por error que el especialista retirará', 'pendiente', null, null, null);
`, [
  S.aPendiente, A.empresa, U.empA, A.grand,
  S.aAprobada, U.gerRoot,
  S.grandPendiente, U.empGrand, A.grand,
  S.bPendiente, B.empresa, U.empB, B.root,
  S.adminPropia, U.gerA, A.child,
  S.aCancelable,
]);

console.log('  Datos insertados.');

// -----------------------------------------------------------------------------
// Estructura
// -----------------------------------------------------------------------------
group('Estructura');
const BUSINESS_TABLES = [
  'empresas', 'centros_costo', 'parques', 'perfiles',
  'jornadas', 'solicitudes_horas_extras',
];
eq('6 tablas de negocio', await scalar(`
  select count(*)::int from information_schema.tables
  where table_schema = 'public'
    and table_name = any ($1::text[])
`, [BUSINESS_TABLES]), 6);
eq('RLS habilitada en las 6 tablas', await scalar(`
  select count(*)::int from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = any ($1::text[])
    and c.relrowsecurity
`, [BUSINESS_TABLES]), 6);
eq('extensiones citext y pgcrypto', await scalar(`
  select count(*)::int from pg_extension where extname in ('citext','pgcrypto')
`), 2);
eq('políticas RLS creadas (2+4+4+1+3+4 base + 9 de la propuesta 0018–0023)', await scalar(`
  select count(*)::int from pg_policies where schemaname = 'public'
`), 27);
eq('enum de estado de solicitud', await scalar(`
  select enum_range(null::public.estado_solicitud)::text
`), '{pendiente,aprobada,rechazada,cancelada}');

// -----------------------------------------------------------------------------
// Jerarquía
// -----------------------------------------------------------------------------
group('Jerarquía de centros de costo');
const rutas = await q(`
  select id, ruta from public.centros_costo
  where id in ($1, $2, $3, $4, $5) order by id
`, [A.root, A.child, A.grand, A.sibling, B.root]);
const rutaPorId = Object.fromEntries(rutas.rows.map((r) => [r.id, r.ruta]));
eq('raíz A sin ancestros', rutaPorId[A.root], []);
eq('hijo A con raíz como ancestro', rutaPorId[A.child], [A.root]);
eq('nieto A con raíz e hijo como ancestros', rutaPorId[A.grand], [A.root, A.child]);
eq('hermano A con raíz como ancestro', rutaPorId[A.sibling], [A.root]);
eq('raíz B aislada', rutaPorId[B.root], []);

await expectError('rechaza un centro como su propio padre', `
  insert into public.centros_costo (id, empresa_id, padre_id, codigo, nombre)
  values ($1, $2, $1, 'SELF', 'Auto padre')
`, [randomUUID(), A.empresa], '23514');

await expectError('rechaza padre de otra empresa', `
  insert into public.centros_costo (id, empresa_id, padre_id, codigo, nombre)
  values ($1, $2, $3, 'CROSS', 'Cruce de empresa')
`, [randomUUID(), A.empresa, B.root], '23503');

await expectError('rechaza ciclos al mover un centro', `
  update public.centros_costo set padre_id = $1 where id = $2
`, [A.grand, A.root], '23514');

await expectError('código duplicado en la misma empresa', `
  insert into public.centros_costo (id, empresa_id, padre_id, codigo, nombre)
  values ($1, $2, $3, 'A-CHILD', 'Duplicado')
`, [randomUUID(), A.empresa, A.root], '23505');

await q('begin');
try {
  const okId = randomUUID();
  await q(`
    insert into public.centros_costo (id, empresa_id, padre_id, codigo, nombre)
    values ($1, $2, $3, 'A-CHILD', 'Mismo código en otra empresa')
  `, [okId, B.empresa, B.root]);
  eq('mismo código permitido en otra empresa', await scalar('select count(*)::int from public.centros_costo where id = $1', [okId]), 1);
} finally {
  await q('rollback');
}

// Profundidad: 32 niveles permitidos, el 33 falla.
await q('begin');
try {
  let parent = B.root;
  for (let nivel = 2; nivel <= 32; nivel++) {
    const id = randomUUID();
    await q(`
      insert into public.centros_costo (id, empresa_id, padre_id, codigo, nombre)
      values ($1, $2, $3, $4, $5)
    `, [id, B.empresa, parent, `N${nivel}`, `Nivel ${nivel}`]);
    parent = id;
  }
  eq('permite 32 niveles', await scalar('select count(*)::int from public.centros_costo where empresa_id = $1', [B.empresa]), 32);

  await q('savepoint nivel33');
  try {
    await q(`
      insert into public.centros_costo (id, empresa_id, padre_id, codigo, nombre)
      values ($1, $2, $3, 'N33', 'Nivel 33')
    `, [randomUUID(), B.empresa, parent]);
    ok('rechaza el nivel 33', false, 'no lanzó error');
  } catch (error) {
    ok('rechaza el nivel 33', error.code === '23514', `code=${error.code}, msg=${error.message}`);
  }
  await q('rollback to savepoint nivel33');
  eq('el nivel 33 no altera la jerarquía', await scalar('select count(*)::int from public.centros_costo where empresa_id = $1', [B.empresa]), 32);
} finally {
  await q('rollback');
}

// Propagación al mover: se hace como service_role (dueño) y se revierte.
await q('begin');
try {
  const great = randomUUID();
  await q(`
    insert into public.centros_costo (id, empresa_id, padre_id, codigo, nombre)
    values ($1, $2, $3, 'A-GREAT', 'Centro bisnieto A')
  `, [great, A.empresa, A.grand]);
  await q('update public.centros_costo set padre_id = $1 where id = $2', [A.root, A.grand]);
  eq('mover centro recalcula su ruta', await scalar('select ruta from public.centros_costo where id = $1', [A.grand]), [A.root]);
  eq('mover centro propaga la ruta al subárbol', await scalar('select ruta from public.centros_costo where id = $1', [great]), [A.root, A.grand]);
} finally {
  await q('rollback');
}

await expectError('no elimina un centro con hijos', 'delete from public.centros_costo where id = $1', [A.child], '23503');
await expectError('no elimina una empresa con centros', 'delete from public.empresas where id = $1', [A.empresa], '23503');

// -----------------------------------------------------------------------------
// Empresas: RLS
// -----------------------------------------------------------------------------
group('RLS de empresas');
eq('empleado solo ve su empresa',
  await withRole('authenticated', claims(U.empA, A.empresa, A.child, 'empleado'), async () =>
    (await q('select id from public.empresas order by id')).rows.map((r) => r.id)),
  [A.empresa]);

eq('admin ve su empresa',
  await withRole('authenticated', claims(U.gerA, A.empresa, A.child, 'admin'), async () =>
    (await q('select id from public.empresas order by id')).rows.map((r) => r.id)),
  [A.empresa]);

eq('service_role ve todas las empresas',
  (await withRole('service_role', {}, async () =>
    (await q('select id from public.empresas order by id')).rows.map((r) => r.id))).length,
  2);

eq('empleado no puede actualizar su empresa',
  await withRole('authenticated', claims(U.empA, A.empresa, A.child, 'empleado'), async () =>
    (await q(`update public.empresas set nombre = 'Hackeada' where id = $1`, [A.empresa])).rowCount),
  0);

eq('admin sí puede actualizar su empresa',
  await withRole('authenticated', claims(U.gerA, A.empresa, A.child, 'admin'), async () =>
    (await q(`update public.empresas set nombre = 'Empresa A actualizada' where id = $1`, [A.empresa])).rowCount),
  1);

await expectRoleError('empleado no puede crear empresas', 'authenticated',
  claims(U.empA, A.empresa, A.child, 'empleado'),
  `insert into public.empresas (codigo, nombre) values ('NUEVA', 'Nueva')`, [], '42501');

// -----------------------------------------------------------------------------
// Centros de costo: RLS por subárbol
// -----------------------------------------------------------------------------
group('RLS de centros de costo');
eq('empleado ve la jerarquía de su empresa',
  await withRole('authenticated', claims(U.empA, A.empresa, A.child, 'empleado'), async () =>
    (await q('select count(*)::int from public.centros_costo')).rows[0].count),
  4);
eq('empleado B no ve centros de A',
  await withRole('authenticated', claims(U.empB, B.empresa, B.root, 'empleado'), async () =>
    (await q('select count(*)::int from public.centros_costo')).rows[0].count),
  1);

await expectRoleError('empleado no puede crear centros', 'authenticated',
  claims(U.empA, A.empresa, A.child, 'empleado'),
  `insert into public.centros_costo (empresa_id, padre_id, codigo, nombre) values ($1,$2,'X','X')`,
  [A.empresa, A.child], '42501');

const rutaNuevoHijo = await withRole('authenticated', claims(U.gerA, A.empresa, A.child, 'admin'), async () => {
  const r = await q(`insert into public.centros_costo (empresa_id, padre_id, codigo, nombre)
                     values ($1,$2,'NEW-CHILD','Nuevo') returning id`,
    [A.empresa, A.child]);
  return (await q('select ruta from public.centros_costo where id = $1', [r.rows[0].id])).rows[0].ruta;
});
eq('admin crea un subcentro y calcula la ruta', rutaNuevoHijo, [A.root, A.child]);

await expectRoleError('admin no crea centros fuera de su subárbol', 'authenticated',
  claims(U.gerA, A.empresa, A.child, 'admin'),
  `insert into public.centros_costo (empresa_id, padre_id, codigo, nombre) values ($1,$2,'OUT','Fuera')`,
  [A.empresa, A.root], '42501');

await expectRoleError('admin no crea raíces', 'authenticated',
  claims(U.gerA, A.empresa, A.child, 'admin'),
  `insert into public.centros_costo (empresa_id, padre_id, codigo, nombre) values ($1,null,'ROOT2','Raíz')`,
  [A.empresa], '42501');

await expectRoleError('admin no crea centros en otra empresa', 'authenticated',
  claims(U.gerA, A.empresa, A.child, 'admin'),
  `insert into public.centros_costo (empresa_id, padre_id, codigo, nombre) values ($1,$2,'B-X','B')`,
  [B.empresa, B.root], '42501');

eq('admin actualiza centros de su subárbol',
  await withRole('authenticated', claims(U.gerA, A.empresa, A.child, 'admin'), async () =>
    (await q(`update public.centros_costo set nombre = 'Nieto editado' where id = $1`, [A.grand])).rowCount),
  1);

eq('admin no actualiza centros fuera de su subárbol',
  await withRole('authenticated', claims(U.gerA, A.empresa, A.child, 'admin'), async () =>
    (await q(`update public.centros_costo set nombre = 'Raíz editada' where id = $1`, [A.root])).rowCount),
  0);

await expectRoleError('admin no puede mover centros', 'authenticated',
  claims(U.gerA, A.empresa, A.child, 'admin'),
  `update public.centros_costo set padre_id = null where id = $1`, [A.child], '42501');

await expectRoleError('admin no puede escribir la ruta', 'authenticated',
  claims(U.gerA, A.empresa, A.child, 'admin'),
  `update public.centros_costo set ruta = '{}' where id = $1`, [A.grand], '42501');

await expectRoleError('admin no puede cambiar la empresa de un centro', 'authenticated',
  claims(U.gerA, A.empresa, A.child, 'admin'),
  `update public.centros_costo set empresa_id = $1 where id = $2`, [B.empresa, A.grand], '42501');

await expectRoleError('admin no puede falsificar actualizado_por', 'authenticated',
  claims(U.gerA, A.empresa, A.child, 'admin'),
  `update public.centros_costo set actualizado_por = $1 where id = $2`, [U.empB, A.grand], '42501');

eq('admin no elimina centros fuera de su subárbol',
  await withRole('authenticated', claims(U.gerA, A.empresa, A.child, 'admin'), async () =>
    (await q('delete from public.centros_costo where id = $1', [A.sibling])).rowCount),
  0);

eq('empleado no actualiza centros',
  await withRole('authenticated', claims(U.empA, A.empresa, A.child, 'empleado'), async () =>
    (await q(`update public.centros_costo set nombre = 'X' where id = $1`, [A.grand])).rowCount),
  0);

// -----------------------------------------------------------------------------
// Parques: RLS por subárbol y geocerca
// -----------------------------------------------------------------------------
group('RLS de parques y geocerca');
eq('empleado A hijo ve solo parques de su subárbol',
  await withRole('authenticated', claims(U.empA, A.empresa, A.child, 'empleado'), async () =>
    (await q('select codigo from public.parques order by codigo')).rows.map((r) => r.codigo)),
  ['P-CHILD', 'P-GRAND']);

eq('empleado A raíz ve todos los parques de A',
  await withRole('authenticated', claims(U.gerRoot, A.empresa, A.root, 'admin'), async () =>
    (await q('select count(*)::int from public.parques')).rows[0].count),
  4);

eq('empleado B ve solo el parque de B',
  await withRole('authenticated', claims(U.empB, B.empresa, B.root, 'empleado'), async () =>
    (await q('select codigo from public.parques')).rows.map((r) => r.codigo)),
  ['P-B']);

await expectRoleError('empleado no puede crear parques', 'authenticated',
  claims(U.empA, A.empresa, A.child, 'empleado'),
  `insert into public.parques (empresa_id, centro_costo_id, codigo, nombre, latitud, longitud)
   values ($1,$2,'NEW','Nuevo',14.6,-90.5)`, [A.empresa, A.child], '42501');

const parqueCreado = await withRole('authenticated', claims(U.gerA, A.empresa, A.child, 'admin'), async () => {
  const r = await q(`insert into public.parques (empresa_id, centro_costo_id, codigo, nombre, latitud, longitud)
                     values ($1,$2,'NEW-P','Nuevo parque',14.6,-90.5) returning id`,
    [A.empresa, A.grand]);
  return await scalar('select count(*)::int from public.parques where id = $1', [r.rows[0].id]);
});
eq('admin crea un parque en su subárbol', parqueCreado, 1);

await expectRoleError('admin no crea parques fuera de su subárbol', 'authenticated',
  claims(U.gerA, A.empresa, A.child, 'admin'),
  `insert into public.parques (empresa_id, centro_costo_id, codigo, nombre, latitud, longitud)
   values ($1,$2,'OUT','Fuera',14.6,-90.5)`, [A.empresa, A.root], '42501');

await expectRoleError('admin no crea parques en otra empresa', 'authenticated',
  claims(U.gerA, A.empresa, A.child, 'admin'),
  `insert into public.parques (empresa_id, centro_costo_id, codigo, nombre, latitud, longitud)
   values ($1,$2,'B-X','B',14.6,-90.5)`, [B.empresa, B.root], '42501');

eq('empleado no actualiza parques',
  await withRole('authenticated', claims(U.empA, A.empresa, A.child, 'empleado'), async () =>
    (await q(`update public.parques set nombre = 'X' where id = $1`, [P.child])).rowCount),
  0);

eq('admin actualiza parques de su subárbol',
  await withRole('authenticated', claims(U.gerA, A.empresa, A.child, 'admin'), async () =>
    (await q(`update public.parques set nombre = 'Nieto editado' where id = $1`, [P.grand])).rowCount),
  1);

eq('admin no elimina parques fuera de su subárbol',
  await withRole('authenticated', claims(U.gerA, A.empresa, A.child, 'admin'), async () =>
    (await q('delete from public.parques where id = $1', [P.root])).rowCount),
  0);

await expectError('latitud fuera de rango', `
  insert into public.parques (empresa_id, centro_costo_id, codigo, nombre, latitud, longitud)
  values ($1,$2,'LAT','Lat',91, -90.5)
`, [A.empresa, A.root], '23514');
await expectError('longitud fuera de rango', `
  insert into public.parques (empresa_id, centro_costo_id, codigo, nombre, latitud, longitud)
  values ($1,$2,'LON','Lon',14.6, -181)
`, [A.empresa, A.root], '23514');
await expectError('radio cero inválido', `
  insert into public.parques (empresa_id, centro_costo_id, codigo, nombre, latitud, longitud, radio_metros)
  values ($1,$2,'R0','R0',14.6,-90.5,0)
`, [A.empresa, A.root], '23514');
await expectError('radio mayor a 10 km inválido', `
  insert into public.parques (empresa_id, centro_costo_id, codigo, nombre, latitud, longitud, radio_metros)
  values ($1,$2,'RMAX','RMax',14.6,-90.5,10001)
`, [A.empresa, A.root], '23514');
await expectError('parque no puede apuntar a centro de otra empresa', `
  insert into public.parques (empresa_id, centro_costo_id, codigo, nombre, latitud, longitud)
  values ($1,$2,'CROSS','Cruce',14.6,-90.5)
`, [A.empresa, B.root], '23503');

// -----------------------------------------------------------------------------
// Geocerca
// -----------------------------------------------------------------------------
group('Geocerca');
eq('distancia al mismo punto es 0', await scalar(
  'select private.distancia_metros(14.6350, -90.5070, 14.6350, -90.5070)'), 0);
ok('distancia entre parques lejanos supera 100 m', (await scalar(
  'select private.distancia_metros(14.6350, -90.5070, 14.6400, -90.5100)')) > 100);

const empAClaims = claims(U.empA, A.empresa, A.child, 'empleado');
eq('en_geocerca acepta el centro del parque',
  await withRole('authenticated', empAClaims, async () =>
    scalar('select private.en_geocerca($1, 14.6350, -90.5070, 0)', [P.child])),
  true);
eq('en_geocerca rechaza un punto lejano',
  await withRole('authenticated', empAClaims, async () =>
    scalar('select private.en_geocerca($1, 14.7000, -90.6000, 0)', [P.child])),
  false);
// 0.00135° de latitud ≈ 150 m: fuera del radio de 100 m, dentro si el GPS
// declara 100 m de precisión.
eq('en_geocerca rechaza 150 m sin tolerancia de GPS',
  await withRole('authenticated', empAClaims, async () =>
    scalar('select private.en_geocerca($1, 14.63635, -90.5070, 0)', [P.child])),
  false);
eq('en_geocerca tolera la precisión GPS declarada',
  await withRole('authenticated', empAClaims, async () =>
    scalar('select private.en_geocerca($1, 14.63635, -90.5070, 100)', [P.child])),
  true);
eq('en_geocerca no cruza empresas',
  await withRole('authenticated', empAClaims, async () =>
    scalar('select private.en_geocerca($1, 14.6400, -90.5100, 0)', [P.b])),
  false);
eq('en_geocerca falla cerrado sin claims',
  await withRole('authenticated', { sub: U.empA }, async () =>
    scalar('select private.en_geocerca($1, 14.6350, -90.5070, 0)', [P.child])),
  false);

// -----------------------------------------------------------------------------
// Jornadas
// -----------------------------------------------------------------------------
group('Jornadas y marcaje');

const jornadaCreada = await withRole('authenticated', empAClaims, async () => {
  const r = await q(`
    insert into public.jornadas (parque_id, entrada_lat, entrada_lon, entrada_precision_metros)
    values ($1, 14.6350, -90.5070, 5)
    returning empresa_id, empleado_id, entrada_dentro_geocerca, salida_en
  `, [P.child]);
  return r.rows[0];
});
eq('el empleado abre una jornada en su parque',
  [jornadaCreada.empresa_id, jornadaCreada.empleado_id,
    jornadaCreada.entrada_dentro_geocerca, jornadaCreada.salida_en],
  [A.empresa, U.empA, true, null]);

const jornadaCerrada = await withRole('authenticated', empAClaims, async () => {
  const id = (await q(`
    insert into public.jornadas (parque_id, entrada_lat, entrada_lon)
    values ($1, 14.6350, -90.5070) returning id
  `, [P.child])).rows[0].id;
  const r = await q(`
    update public.jornadas
    set salida_lat = 14.6350, salida_lon = -90.5070, salida_precision_metros = 5
    where id = $1
  `, [id]);
  const row = (await q(`
    select salida_en is not null as cerrada, salida_dentro_geocerca
    from public.jornadas where id = $1
  `, [id])).rows[0];
  return [r.rowCount, row.cerrada, row.salida_dentro_geocerca];
});
eq('el empleado cierra su jornada con GPS válido', jornadaCerrada, [1, true, true]);

await q('begin');
try {
  await q('set local role authenticated');
  await q(`select set_config('request.jwt.claims', $1, true)`, [JSON.stringify(empAClaims)]);
  const id = (await q(`
    insert into public.jornadas (parque_id, entrada_lat, entrada_lon)
    values ($1, 14.6350, -90.5070) returning id
  `, [P.child])).rows[0].id;
  try {
    await q(`
      update public.jornadas set salida_lat = 14.7000, salida_lon = -90.6000 where id = $1
    `, [id]);
    ok('rechaza la salida fuera de la geocerca', false, 'no lanzó error');
  } catch (error) {
    ok('rechaza la salida fuera de la geocerca', error.code === '23514',
      `code=${error.code}, msg=${error.message}`);
  }
} finally {
  await q('rollback');
}

await q('begin');
try {
  await q('set local role authenticated');
  await q(`select set_config('request.jwt.claims', $1, true)`, [JSON.stringify(empAClaims)]);
  await q(`
    insert into public.jornadas (parque_id, entrada_lat, entrada_lon)
    values ($1, 14.6350, -90.5070)
  `, [P.child]);
  try {
    await q(`
      insert into public.jornadas (parque_id, entrada_lat, entrada_lon)
      values ($1, 14.6350, -90.5070)
    `, [P.child]);
    ok('rechaza dos jornadas abiertas del mismo empleado', false, 'no lanzó error');
  } catch (error) {
    ok('rechaza dos jornadas abiertas del mismo empleado', error.code === '23505',
      `code=${error.code}, msg=${error.message}`);
  }
} finally {
  await q('rollback');
}

await expectRoleError('no abre jornada fuera de la geocerca', 'authenticated', empAClaims, `
  insert into public.jornadas (parque_id, entrada_lat, entrada_lon)
  values ($1, 14.7000, -90.6000)
`, [P.child], '23514');

await expectRoleError('no abre jornada en un parque de otra empresa', 'authenticated', empAClaims, `
  insert into public.jornadas (parque_id, entrada_lat, entrada_lon)
  values ($1, 14.6400, -90.5100)
`, [P.b], '23514');

await expectRoleError('no falsifica la empresa de la jornada', 'authenticated', empAClaims, `
  insert into public.jornadas (empresa_id, parque_id, entrada_lat, entrada_lon)
  values ($1, $2, 14.6350, -90.5070)
`, [A.empresa, P.child], '42501');

await expectRoleError('no abre jornada a nombre de otro', 'authenticated', empAClaims, `
  insert into public.jornadas (empleado_id, parque_id, entrada_lat, entrada_lon)
  values ($1, $2, 14.6350, -90.5070)
`, [U.empGrand, P.child], '42501');

await expectRoleError('no escribe la salida al abrir', 'authenticated', empAClaims, `
  insert into public.jornadas (parque_id, entrada_lat, entrada_lon, salida_en)
  values ($1, 14.6350, -90.5070, now())
`, [P.child], '42501');

await expectRoleError('no escribe el veredicto de geocerca', 'authenticated', empAClaims, `
  insert into public.jornadas (parque_id, entrada_lat, entrada_lon, entrada_dentro_geocerca)
  values ($1, 14.6350, -90.5070, true)
`, [P.child], '42501');

eq('el empleado A ve solo sus jornadas',
  await withRole('authenticated', empAClaims, async () =>
    (await q('select id from public.jornadas order by id')).rows.map((r) => r.id)),
  [J.aCerrada]);
eq('el empleado B ve solo sus jornadas',
  await withRole('authenticated', claims(U.empB, B.empresa, B.root, 'empleado'), async () =>
    (await q('select id from public.jornadas order by id')).rows.map((r) => r.id)),
  [J.bCerrada]);
eq('el admin ve las jornadas de su subárbol',
  await withRole('authenticated', claims(U.gerA, A.empresa, A.child, 'admin'), async () =>
    (await q('select id from public.jornadas order by id')).rows.map((r) => r.id)),
  [J.aCerrada, J.grandAbierta].sort());
eq('el admin raíz ve las jornadas de su empresa',
  await withRole('authenticated', claims(U.gerRoot, A.empresa, A.root, 'admin'), async () =>
    (await q('select count(*)::int from public.jornadas')).rows[0].count),
  2);
eq('el admin A no ve jornadas de B',
  await withRole('authenticated', claims(U.gerA, A.empresa, A.child, 'admin'), async () =>
    (await q('select count(*)::int from public.jornadas where id = $1', [J.bCerrada])).rows[0].count),
  0);
eq('otro empleado no cierra una jornada ajena',
  await withRole('authenticated', empAClaims, async () =>
    (await q(`
      update public.jornadas
      set salida_lat = 14.6351, salida_lon = -90.5071
      where id = $1
    `, [J.grandAbierta])).rowCount),
  0);
eq('el admin no cierra jornadas de su equipo',
  await withRole('authenticated', claims(U.gerA, A.empresa, A.child, 'admin'), async () =>
    (await q(`
      update public.jornadas
      set salida_lat = 14.6351, salida_lon = -90.5071
      where id = $1
    `, [J.grandAbierta])).rowCount),
  0);

await expectRoleError('no se pueden borrar jornadas', 'authenticated', empAClaims,
  'delete from public.jornadas where id = $1', [J.aCerrada], '42501');

await q('begin');
try {
  const id = randomUUID();
  await q(`
    insert into public.jornadas (
      id, empresa_id, empleado_id, parque_id, entrada_en, salida_en,
      entrada_lat, entrada_lon, entrada_dentro_geocerca,
      salida_lat, salida_lon, salida_dentro_geocerca
    ) values (
      $1, $2, $3, $4, now() - interval '30 hours', now() - interval '25 hours',
      0, 0, false, 0, 0, false
    )
  `, [id, A.empresa, U.empA, P.child]);
  eq('service_role siembra jornadas históricas sin geocerca',
    await scalar('select count(*)::int from public.jornadas where id = $1', [id]), 1);
} finally {
  await q('rollback');
}

// -----------------------------------------------------------------------------
// Horas extras
// -----------------------------------------------------------------------------
group('Solicitudes de horas extras');

const solicitudCreada = await withRole('authenticated', empAClaims, async () => {
  const r = await q(`
    insert into public.solicitudes_horas_extras (centro_costo_id, inicio, fin, justificacion)
    values ($1, now(), now() + interval '3 hours', 'Apoyo en inventario del parque central')
    returning empresa_id, empleado_id, estado, revisado_por, revisado_en
  `, [A.grand]);
  return r.rows[0];
});
eq('el especialista crea una solicitud pendiente',
  [solicitudCreada.empresa_id, solicitudCreada.empleado_id,
    solicitudCreada.estado, solicitudCreada.revisado_por, solicitudCreada.revisado_en],
  [A.empresa, U.empA, 'pendiente', null, null]);

await expectRoleError('justificación demasiado corta', 'authenticated', empAClaims, `
  insert into public.solicitudes_horas_extras (centro_costo_id, inicio, fin, justificacion)
  values ($1, now(), now() + interval '1 hour', 'corta')
`, [A.grand], '23514');

await expectRoleError('fin anterior al inicio', 'authenticated', empAClaims, `
  insert into public.solicitudes_horas_extras (centro_costo_id, inicio, fin, justificacion)
  values ($1, now(), now() - interval '1 hour', 'Rango inválido de prueba')
`, [A.grand], '23514');

await expectRoleError('duración mayor a 24 horas', 'authenticated', empAClaims, `
  insert into public.solicitudes_horas_extras (centro_costo_id, inicio, fin, justificacion)
  values ($1, now(), now() + interval '25 hours', 'Duración excesiva de prueba')
`, [A.grand], '23514');

await expectRoleError('no solicita para un centro de otra empresa', 'authenticated', empAClaims, `
  insert into public.solicitudes_horas_extras (centro_costo_id, inicio, fin, justificacion)
  values ($1, now(), now() + interval '1 hour', 'Cruce de empresa en solicitud')
`, [B.root], '42501');

await expectRoleError('no falsifica la empresa de la solicitud', 'authenticated', empAClaims, `
  insert into public.solicitudes_horas_extras (empresa_id, centro_costo_id, inicio, fin, justificacion)
  values ($1, $2, now(), now() + interval '1 hour', 'Intento de falsificar empresa')
`, [A.empresa, A.grand], '42501');

await expectRoleError('no solicita a nombre de otro', 'authenticated', empAClaims, `
  insert into public.solicitudes_horas_extras (empleado_id, centro_costo_id, inicio, fin, justificacion)
  values ($1, $2, now(), now() + interval '1 hour', 'Intento de suplantación')
`, [U.empGrand, A.grand], '42501');

await expectRoleError('no nace aprobada', 'authenticated', empAClaims, `
  insert into public.solicitudes_horas_extras (centro_costo_id, inicio, fin, justificacion, estado)
  values ($1, now(), now() + interval '1 hour', 'Intento de autoaprobarse', 'aprobada')
`, [A.grand], '42501');

await expectRoleError('no falsifica la revisión al crear', 'authenticated', empAClaims, `
  insert into public.solicitudes_horas_extras (centro_costo_id, inicio, fin, justificacion, revisado_por)
  values ($1, now(), now() + interval '1 hour', 'Intento de falsificar revisor', $2)
`, [A.grand, U.gerA], '42501');

await expectRoleError('no escribe comentario del admin al crear', 'authenticated', empAClaims, `
  insert into public.solicitudes_horas_extras (centro_costo_id, inicio, fin, justificacion, comentario_admin)
  values ($1, now(), now() + interval '1 hour', 'Intento de comentario propio', 'comentario')
`, [A.grand], '42501');

eq('el especialista ve solo sus solicitudes',
  await withRole('authenticated', empAClaims, async () =>
    (await q('select id from public.solicitudes_horas_extras order by id')).rows.map((r) => r.id)),
  [S.aPendiente, S.aAprobada, S.aCancelable].sort());
eq('el especialista nieto ve solo las suyas',
  await withRole('authenticated', claims(U.empGrand, A.empresa, A.grand, 'empleado'), async () =>
    (await q('select id from public.solicitudes_horas_extras order by id')).rows.map((r) => r.id)),
  [S.grandPendiente]);
eq('el admin ve las solicitudes de su subárbol',
  await withRole('authenticated', claims(U.gerA, A.empresa, A.child, 'admin'), async () =>
    (await q('select id from public.solicitudes_horas_extras order by id')).rows.map((r) => r.id)),
  [S.aPendiente, S.aAprobada, S.grandPendiente, S.adminPropia, S.aCancelable].sort());
eq('el admin raíz ve todas las solicitudes de su empresa',
  await withRole('authenticated', claims(U.gerRoot, A.empresa, A.root, 'admin'), async () =>
    (await q('select count(*)::int from public.solicitudes_horas_extras')).rows[0].count),
  5);
eq('el admin A no ve solicitudes de B',
  await withRole('authenticated', claims(U.gerA, A.empresa, A.child, 'admin'), async () =>
    (await q('select count(*)::int from public.solicitudes_horas_extras where id = $1', [S.bPendiente])).rows[0].count),
  0);
eq('el especialista B ve solo las suyas',
  await withRole('authenticated', claims(U.empB, B.empresa, B.root, 'empleado'), async () =>
    (await q('select id from public.solicitudes_horas_extras order by id')).rows.map((r) => r.id)),
  [S.bPendiente]);

const aprobada = await withRole('authenticated', claims(U.gerA, A.empresa, A.child, 'admin'), async () => {
  const r = await q(`
    update public.solicitudes_horas_extras
    set estado = 'aprobada', comentario_admin = 'Aprobado, gracias'
    where id = $1
  `, [S.aPendiente]);
  const row = (await q(`
    select estado, comentario_admin, revisado_por, revisado_en is not null as revisado
    from public.solicitudes_horas_extras where id = $1
  `, [S.aPendiente])).rows[0];
  return [r.rowCount, row.estado, row.comentario_admin, row.revisado_por, row.revisado];
});
eq('el admin aprueba con comentario y firma la revisión', aprobada,
  [1, 'aprobada', 'Aprobado, gracias', U.gerA, true]);

const rechazada = await withRole('authenticated', claims(U.gerA, A.empresa, A.child, 'admin'), async () => {
  const r = await q(`
    update public.solicitudes_horas_extras set estado = 'rechazada'
    where id = $1
  `, [S.grandPendiente]);
  const row = (await q(`
    select estado, comentario_admin, revisado_por
    from public.solicitudes_horas_extras where id = $1
  `, [S.grandPendiente])).rows[0];
  return [r.rowCount, row.estado, row.comentario_admin, row.revisado_por];
});
eq('el admin rechaza sin comentario obligatorio', rechazada,
  [1, 'rechazada', null, U.gerA]);

eq('el admin no revisa solicitudes fuera de su subárbol',
  await withRole('authenticated', claims(U.gerA, A.empresa, A.child, 'admin'), async () =>
    (await q(`
      update public.solicitudes_horas_extras set estado = 'aprobada' where id = $1
    `, [S.bPendiente])).rowCount),
  0);

await expectRoleError('el admin no revisa su propia solicitud', 'authenticated',
  claims(U.gerA, A.empresa, A.child, 'admin'),
  `update public.solicitudes_horas_extras set estado = 'aprobada' where id = $1`,
  [S.adminPropia], '42501');

eq('no se revisa dos veces una solicitud',
  await withRole('authenticated', claims(U.gerA, A.empresa, A.child, 'admin'), async () =>
    (await q(`
      update public.solicitudes_horas_extras set estado = 'rechazada' where id = $1
    `, [S.aAprobada])).rowCount),
  0);

await expectRoleError('el especialista no cambia el estado de su solicitud', 'authenticated',
  empAClaims,
  `update public.solicitudes_horas_extras set estado = 'aprobada' where id = $1`,
  [S.aPendiente], '42501');

await expectRoleError('el admin no cambia el especialista', 'authenticated',
  claims(U.gerA, A.empresa, A.child, 'admin'),
  `update public.solicitudes_horas_extras set empleado_id = $1 where id = $2`,
  [U.empGrand, S.aPendiente], '42501');

await expectRoleError('el admin no falsifica quién revisó', 'authenticated',
  claims(U.gerA, A.empresa, A.child, 'admin'),
  `update public.solicitudes_horas_extras set revisado_por = $1 where id = $2`,
  [U.gerRoot, S.aPendiente], '42501');

await expectRoleError('el admin no cambia la empresa', 'authenticated',
  claims(U.gerA, A.empresa, A.child, 'admin'),
  `update public.solicitudes_horas_extras set empresa_id = $1 where id = $2`,
  [B.empresa, S.aPendiente], '42501');

await expectRoleError('no se pueden borrar solicitudes', 'authenticated', empAClaims,
  'delete from public.solicitudes_horas_extras where id = $1', [S.aPendiente], '42501');

await expectError('no se reabre una solicitud revisada', `
  update public.solicitudes_horas_extras set estado = 'pendiente' where id = $1
`, [S.aAprobada], '23514');

await expectRoleError('el especialista no aprueba su solicitud pendiente', 'authenticated',
  empAClaims,
  `update public.solicitudes_horas_extras set estado = 'aprobada' where id = $1`,
  [S.aCancelable], '42501');

eq('el especialista no retira una solicitud ajena',
  await withRole('authenticated', empAClaims, async () =>
    (await q(`
      update public.solicitudes_horas_extras set estado = 'cancelada' where id = $1
    `, [S.adminPropia])).rowCount),
  0);

eq('el especialista no retira una solicitud ya aprobada',
  await withRole('authenticated', empAClaims, async () =>
    (await q(`
      update public.solicitudes_horas_extras set estado = 'cancelada' where id = $1
    `, [S.aAprobada])).rowCount),
  0);

await q('begin');
try {
  await q('set local role authenticated');
  await q(`select set_config('request.jwt.claims', $1, true)`, [JSON.stringify(empAClaims)]);
  const retiro = await q(`
    update public.solicitudes_horas_extras
    set estado = 'cancelada', comentario_admin = 'comentario no permitido'
    where id = $1
  `, [S.aCancelable]);
  const fila = (await q(`
    select estado, comentario_admin, revisado_por, revisado_en is not null as cerrada
    from public.solicitudes_horas_extras where id = $1
  `, [S.aCancelable])).rows[0];
  eq('el especialista retira su solicitud pendiente',
    [retiro.rowCount, fila.estado, fila.comentario_admin, fila.revisado_por, fila.cerrada],
    [1, 'cancelada', null, null, true]);

  await q(`select set_config('request.jwt.claims', $1, true)`,
    [JSON.stringify(claims(U.gerA, A.empresa, A.child, 'admin'))]);
  eq('el admin no revisa una solicitud cancelada',
    (await q(`
      update public.solicitudes_horas_extras set estado = 'aprobada' where id = $1
    `, [S.aCancelable])).rowCount,
    0);

  await q('reset role');
  try {
    await q(`
      update public.solicitudes_horas_extras set estado = 'pendiente' where id = $1
    `, [S.aCancelable]);
    ok('una solicitud cancelada no se reabre', false, 'no lanzó error');
  } catch (error) {
    ok('una solicitud cancelada no se reabre', error.code === '23514',
      `code=${error.code}, msg=${error.message}`);
  }
} finally {
  await q('rollback');
}

// -----------------------------------------------------------------------------
// Tiempo real
// -----------------------------------------------------------------------------
group('Realtime');
eq('la publicación incluye jornadas y solicitudes', await scalar(`
  select count(*)::int from pg_publication_tables
  where pubname = 'supabase_realtime'
    and schemaname = 'public'
    and tablename in ('jornadas', 'solicitudes_horas_extras')
`), 2);
eq('replica identity full en jornadas y solicitudes', await scalar(`
  select count(*)::int from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in ('jornadas', 'solicitudes_horas_extras')
    and c.relreplident = 'f'
`), 2);

// -----------------------------------------------------------------------------
// Perfiles y roles
// -----------------------------------------------------------------------------
group('Perfiles y separación de roles');
eq('la sincronización materializó 5 perfiles', await scalar('select count(*)::int from public.perfiles'), 5);
eq('usuario sin claims no tiene perfil',
  await scalar('select count(*)::int from public.perfiles where id = $1', [U.noClaims]), 0);
eq('el rol se materializa desde app_metadata',
  await scalar('select rol from public.perfiles where id = $1', [U.gerA]), 'admin');
eq('el alcance se materializa desde app_metadata',
  await scalar('select centro_costo_id from public.perfiles where id = $1', [U.empGrand]), A.grand);

await expectError('alcance inválido rechaza el alta del usuario', `
  insert into auth.users (id, email, raw_app_meta_data)
  values ($1, 'invalido@example.com', $2::jsonb)
`, [randomUUID(), appMeta(A.empresa, B.root, 'empleado')], '23503');

// Actualización administrativa del rol.
await q('begin');
try {
  await q(`update auth.users set raw_app_meta_data = $1::jsonb where id = $2`,
    [appMeta(A.empresa, A.grand, 'admin'), U.empA]);
  eq('service_role puede promover el rol y el perfil se sincroniza',
    await scalar('select rol from public.perfiles where id = $1', [U.empA]), 'admin');
  eq('el cambio de alcance también se sincroniza',
    await scalar('select centro_costo_id from public.perfiles where id = $1', [U.empA]), A.grand);
} finally {
  await q('rollback');
}

// Borrado en cascada.
await q('begin');
try {
  const temporal = randomUUID();
  await q(`insert into auth.users (id, email, raw_app_meta_data) values ($1,'temp@example.com',$2::jsonb)`,
    [temporal, appMeta(A.empresa, A.child, 'empleado')]);
  eq('el alta de auth crea el perfil', await scalar('select count(*)::int from public.perfiles where id = $1', [temporal]), 1);
  await q('delete from auth.users where id = $1', [temporal]);
  eq('el borrado de auth elimina el perfil en cascada',
    await scalar('select count(*)::int from public.perfiles where id = $1', [temporal]), 0);
} finally {
  await q('rollback');
}

// Retención del historial: una cuenta con actividad no se puede borrar; se
// desactiva el perfil para dar de baja sin perder la evidencia.
group('Retención del historial laboral');
eq('las FK de empleado son compuestas y usan ON DELETE RESTRICT', await scalar(`
  select count(*)::int
  from pg_constraint c
  join pg_class t on t.oid = c.conrelid
  join pg_namespace n on n.oid = t.relnamespace
  where n.nspname = 'public'
    and t.relname in ('jornadas', 'solicitudes_horas_extras')
    and c.conname in (
      'jornadas_empleado_empresa_fkey',
      'solicitudes_empleado_empresa_fkey'
    )
    and c.contype = 'f'
    and c.confdeltype = 'r'
    and pg_get_constraintdef(c.oid) like '%(empresa_id, empleado_id)%'
`), 2);

await q('begin');
try {
  const conJornada = randomUUID();
  await q(
    `insert into auth.users (id, email, raw_app_meta_data)
     values ($1, 'historial.jornada@example.com', $2::jsonb)`,
    [conJornada, appMeta(A.empresa, A.child, 'empleado')],
  );
  await q(`
    insert into public.jornadas (
      empresa_id, empleado_id, parque_id, entrada_en, salida_en,
      entrada_lat, entrada_lon, entrada_dentro_geocerca,
      salida_lat, salida_lon, salida_dentro_geocerca
    ) values (
      $1, $2, $3, now() - interval '2 hours', now() - interval '1 hour',
      14.6350, -90.5070, true, 14.6350, -90.5070, true
    )
  `, [A.empresa, conJornada, P.child]);

  await q('savepoint intento_jornada');
  let errorJornada = null;
  try {
    await q('delete from auth.users where id = $1', [conJornada]);
  } catch (error) {
    errorJornada = error;
  }
  await q('rollback to savepoint intento_jornada');
  eq('borrar una cuenta con jornadas falla por la FK de jornadas',
    [errorJornada?.code, errorJornada?.constraint,
      await scalar('select count(*)::int from public.perfiles where id = $1', [conJornada]),
      await scalar('select count(*)::int from public.jornadas where empleado_id = $1', [conJornada])],
    ['23503', 'jornadas_empleado_empresa_fkey', 1, 1]);

  const conSolicitud = randomUUID();
  await q(
    `insert into auth.users (id, email, raw_app_meta_data)
     values ($1, 'historial.solicitud@example.com', $2::jsonb)`,
    [conSolicitud, appMeta(A.empresa, A.child, 'empleado')],
  );
  await q(`
    insert into public.solicitudes_horas_extras (
      empresa_id, empleado_id, centro_costo_id, inicio, fin, justificacion
    ) values (
      $1, $2, $3, now() - interval '2 hours', now() - interval '1 hour',
      'Historial retenido ante el borrado de la cuenta'
    )
  `, [A.empresa, conSolicitud, A.child]);

  await q('savepoint intento_solicitud');
  let errorSolicitud = null;
  try {
    await q('delete from auth.users where id = $1', [conSolicitud]);
  } catch (error) {
    errorSolicitud = error;
  }
  await q('rollback to savepoint intento_solicitud');
  eq('borrar una cuenta con solicitudes falla por la FK de solicitudes',
    [errorSolicitud?.code, errorSolicitud?.constraint,
      await scalar('select count(*)::int from public.perfiles where id = $1', [conSolicitud]),
      await scalar('select count(*)::int from public.solicitudes_horas_extras where empleado_id = $1', [conSolicitud])],
    ['23503', 'solicitudes_empleado_empresa_fkey', 1, 1]);
} finally {
  await q('rollback');
}

// -----------------------------------------------------------------------------
// Integridad cross-tenant y evidencia de revisión
// -----------------------------------------------------------------------------
group('Integridad cross-tenant y evidencia de revisión');
eq('la FK del revisor es compuesta y usa ON DELETE RESTRICT', await scalar(`
  select count(*)::int
  from pg_constraint c
  join pg_class t on t.oid = c.conrelid
  join pg_namespace n on n.oid = t.relnamespace
  where n.nspname = 'public'
    and t.relname = 'solicitudes_horas_extras'
    and c.conname = 'solicitudes_revisado_por_empresa_fkey'
    and c.contype = 'f'
    and c.confdeltype = 'r'
    and pg_get_constraintdef(c.oid) like '%(empresa_id, revisado_por)%'
`), 1);

await q('begin');
try {
  const revisor = randomUUID();
  await q(
    `insert into auth.users (id, email, raw_app_meta_data)
     values ($1, 'revisor.retenido@example.com', $2::jsonb)`,
    [revisor, appMeta(A.empresa, A.child, 'admin')],
  );

  const solicitudRevisada = randomUUID();
  await q(`
    insert into public.solicitudes_horas_extras (
      id, empresa_id, empleado_id, centro_costo_id, inicio, fin,
      justificacion, estado, revisado_por, revisado_en
    ) values (
      $1, $2, $3, $4, now() - interval '2 hours', now() - interval '1 hour',
      'Evidencia de revisión retenida para auditoría', 'aprobada', $5, now()
    )
  `, [solicitudRevisada, A.empresa, U.empA, A.child, revisor]);

  // Un revisor de otra empresa no puede quedar asociado a la solicitud.
  await q('savepoint revisor_ajeno');
  let errorRevisor = null;
  try {
    await q(`
      insert into public.solicitudes_horas_extras (
        empresa_id, empleado_id, centro_costo_id, inicio, fin,
        justificacion, estado, revisado_por, revisado_en
      ) values (
        $1, $2, $3, now() - interval '3 hours', now() - interval '2 hours',
        'Revisor que pertenece a otra empresa', 'aprobada', $4, now()
      )
    `, [A.empresa, U.empA, A.child, U.empB]);
  } catch (error) {
    errorRevisor = error;
  }
  await q('rollback to savepoint revisor_ajeno');
  eq('un revisor de otra empresa es rechazado', errorRevisor?.code, '23503');

  // Una jornada no puede apuntar a un empleado de otra empresa.
  await q('savepoint jornada_cross_tenant');
  let errorJornada = null;
  try {
    await q(`
      insert into public.jornadas (
        empresa_id, empleado_id, parque_id, entrada_lat, entrada_lon
      ) values ($1, $2, $3, 14.6350, -90.5070)
    `, [A.empresa, U.empB, P.child]);
  } catch (error) {
    errorJornada = error;
  }
  await q('rollback to savepoint jornada_cross_tenant');
  eq('una jornada con empleado de otra empresa es rechazada',
    errorJornada?.code, '23503');

  // Borrar al revisor no puede dejar la solicitud sin evidencia.
  await q('savepoint borrar_revisor');
  let errorBorrado = null;
  try {
    await q('delete from auth.users where id = $1', [revisor]);
  } catch (error) {
    errorBorrado = error;
  }
  await q('rollback to savepoint borrar_revisor');
  eq('borrar al revisor falla y conserva la evidencia',
    [errorBorrado?.code, errorBorrado?.constraint,
      await scalar('select revisado_por from public.solicitudes_horas_extras where id = $1', [solicitudRevisada])],
    ['23503', 'solicitudes_revisado_por_empresa_fkey', revisor]);

  // Tampoco se puede reescribir la empresa de un empleado con historial.
  await q('savepoint mover_empleado');
  let errorMover = null;
  try {
    await q(
      'update public.perfiles set empresa_id = $1, centro_costo_id = $2 where id = $3',
      [B.empresa, B.root, U.empA],
    );
  } catch (error) {
    errorMover = error;
  }
  await q('rollback to savepoint mover_empleado');
  eq('no se mueve de empresa a un empleado con historial',
    errorMover?.code, '23503');
} finally {
  await q('rollback');
}

eq('empleado solo ve su propio perfil',
  await withRole('authenticated', claims(U.empA, A.empresa, A.child, 'empleado'), async () =>
    (await q('select id from public.perfiles')).rows.map((r) => r.id)),
  [U.empA]);

eq('admin ve los perfiles de su subárbol',
  await withRole('authenticated', claims(U.gerA, A.empresa, A.child, 'admin'), async () =>
    (await q('select id from public.perfiles order by id')).rows.map((r) => r.id)),
  [U.empA, U.gerA, U.empGrand].sort());

eq('admin raíz ve todos los perfiles de su empresa',
  await withRole('authenticated', claims(U.gerRoot, A.empresa, A.root, 'admin'), async () =>
    (await q('select count(*)::int from public.perfiles')).rows[0].count),
  4);

eq('admin de A no ve perfiles de B',
  await withRole('authenticated', claims(U.gerA, A.empresa, A.child, 'admin'), async () =>
    (await q('select count(*)::int from public.perfiles where id = $1', [U.empB])).rows[0].count),
  0);

await expectRoleError('empleado no puede cambiar su rol', 'authenticated',
  claims(U.empA, A.empresa, A.child, 'empleado'),
  `update public.perfiles set rol = 'admin' where id = $1`, [U.empA], '42501');

await expectRoleError('empleado no puede insertar perfiles', 'authenticated',
  claims(U.empA, A.empresa, A.child, 'empleado'),
  `insert into public.perfiles (id, empresa_id, centro_costo_id, rol, nombre_completo)
   values ($1,$2,$3,'admin','X')`, [randomUUID(), A.empresa, A.child], '42501');

await expectRoleError('empleado no puede escribir auth.users', 'authenticated',
  claims(U.empA, A.empresa, A.child, 'empleado'),
  `update auth.users set raw_app_meta_data = '{"rol":"admin"}'::jsonb where id = $1`, [U.empA], '42501');

await expectRoleError('admin no puede editar perfiles ajenos', 'authenticated',
  claims(U.gerA, A.empresa, A.child, 'admin'),
  `update public.perfiles set rol = 'admin' where id = $1`, [U.empGrand], '42501');

eq('service_role puede corregir un perfil',
  await withRole('service_role', {}, async () =>
    (await q(`update public.perfiles set rol = 'admin' where id = $1`, [U.empGrand])).rowCount),
  1);

// -----------------------------------------------------------------------------
// Endurecimiento operativo (migración 0007)
// -----------------------------------------------------------------------------
group('Endurecimiento operativo');

eq('parque_en_alcance acepta un parque del subárbol',
  await withRole('authenticated', empAClaims, async () =>
    scalar('select private.parque_en_alcance($1)', [P.grand])),
  true);
eq('parque_en_alcance rechaza un parque hermano',
  await withRole('authenticated', empAClaims, async () =>
    scalar('select private.parque_en_alcance($1)', [P.sibling])),
  false);

await expectRoleError('no abre jornada en un parque fuera de su subárbol', 'authenticated',
  empAClaims, `
  insert into public.jornadas (parque_id, entrada_lat, entrada_lon)
  values ($1, 14.6352, -90.5072)
`, [P.sibling], '42501');

await expectRoleError('rechaza una precisión GPS negativa al abrir', 'authenticated',
  empAClaims, `
  insert into public.jornadas (parque_id, entrada_lat, entrada_lon, entrada_precision_metros)
  values ($1, 14.6350, -90.5070, -5)
`, [P.child], '23514');

// Un parque desactivado no acepta entradas nuevas...
await q('begin');
try {
  await q('update public.parques set activo = false where id = $1', [P.child]);
  await q('set local role authenticated');
  await q(`select set_config('request.jwt.claims', $1, true)`, [JSON.stringify(empAClaims)]);
  try {
    await q(`
      insert into public.jornadas (parque_id, entrada_lat, entrada_lon)
      values ($1, 14.6350, -90.5070)
    `, [P.child]);
    ok('no abre jornada en un parque inactivo', false, 'no lanzó error');
  } catch (error) {
    ok('no abre jornada en un parque inactivo', error.code === '23514',
      `code=${error.code}, msg=${error.message}`);
  }
} finally {
  await q('rollback');
}

// ...pero la jornada ya abierta debe poder cerrarse si el parque se desactiva
// durante el turno. Si no, el empleado queda con una jornada abierta eterna.
await q('begin');
try {
  await q('set local role authenticated');
  await q(`select set_config('request.jwt.claims', $1, true)`, [JSON.stringify(empAClaims)]);
  const id = (await q(`
    insert into public.jornadas (parque_id, entrada_lat, entrada_lon)
    values ($1, 14.6350, -90.5070) returning id
  `, [P.child])).rows[0].id;

  await q('reset role');
  await q('update public.parques set activo = false where id = $1', [P.child]);

  await q('set local role authenticated');
  await q(`select set_config('request.jwt.claims', $1, true)`, [JSON.stringify(empAClaims)]);
  const r = await q(`
    update public.jornadas
    set salida_lat = 14.6350, salida_lon = -90.5070, salida_precision_metros = 5
    where id = $1
  `, [id]);
  const row = (await q(`
    select salida_en is not null as cerrada, salida_dentro_geocerca
    from public.jornadas where id = $1
  `, [id])).rows[0];
  eq('cierra la jornada aunque el parque se haya desactivado',
    [r.rowCount, row.cerrada, row.salida_dentro_geocerca], [1, true, true]);
} finally {
  await q('rollback');
}

// Una jornada olvidada abierta más de 24 h debe poder cerrarse: si no, el
// empleado queda atrapado entre el tope de duración y el índice de jornada
// abierta.
await q('begin');
try {
  const vencida = randomUUID();
  await q(`
    insert into public.jornadas (
      id, empresa_id, empleado_id, parque_id, entrada_en,
      entrada_lat, entrada_lon, entrada_dentro_geocerca
    ) values ($1, $2, $3, $4, now() - interval '30 hours',
              14.6350, -90.5070, true)
  `, [vencida, A.empresa, U.empA, P.child]);

  await q('set local role authenticated');
  await q(`select set_config('request.jwt.claims', $1, true)`, [JSON.stringify(empAClaims)]);
  const r = await q(`
    update public.jornadas
    set salida_lat = 14.6350, salida_lon = -90.5070, salida_precision_metros = 5
    where id = $1
  `, [vencida]);
  const row = (await q(`
    select extract(epoch from (salida_en - entrada_en)) / 3600 as horas,
           salida_dentro_geocerca
    from public.jornadas where id = $1
  `, [vencida])).rows[0];
  eq('cierra una jornada olvidada de más de 24 horas',
    [r.rowCount, row.salida_dentro_geocerca, Number(row.horas) > 24],
    [1, true, true]);
} finally {
  await q('rollback');
}

// Un perfil inactivo conserva historial pero no inicia trabajo nuevo.
const inactivoEmp = randomUUID();
try {
  await q(`
    insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data)
    values ($1, 'inactivo.emp@example.com', $2::jsonb,
            '{"nombre_completo":"Empleado Inactivo"}'::jsonb)
  `, [inactivoEmp, appMeta(A.empresa, A.child, 'empleado')]);
  const inactivoClaims = claims(inactivoEmp, A.empresa, A.child, 'empleado');

  // Abre una jornada mientras está activo, desactiva el perfil y la cierra.
  // Todo dentro de una transacción para que el perfil vuelva a quedar activo
  // al hacer rollback; la desactivación definitiva se hace después.
  await q('begin');
  try {
    await q('set local role authenticated');
    await q(`select set_config('request.jwt.claims', $1, true)`, [JSON.stringify(inactivoClaims)]);
    const jornadaInactivo = (await q(`
      insert into public.jornadas (parque_id, entrada_lat, entrada_lon)
      values ($1, 14.6350, -90.5070) returning id
    `, [P.child])).rows[0].id;

    await q('reset role');
    await q('update public.perfiles set activo = false where id = $1', [inactivoEmp]);

    await q('set local role authenticated');
    await q(`select set_config('request.jwt.claims', $1, true)`, [JSON.stringify(inactivoClaims)]);
    const r = await q(`
      update public.jornadas
      set salida_lat = 14.6350, salida_lon = -90.5070, salida_precision_metros = 5
      where id = $1
    `, [jornadaInactivo]);
    const row = (await q(`
      select salida_en is not null as cerrada, salida_dentro_geocerca
      from public.jornadas where id = $1
    `, [jornadaInactivo])).rows[0];
    eq('un perfil inactivo sí cierra su jornada abierta',
      [r.rowCount, row.cerrada, row.salida_dentro_geocerca], [1, true, true]);
  } finally {
    await q('rollback');
  }

  await q('update public.perfiles set activo = false where id = $1', [inactivoEmp]);

  await expectRoleError('un perfil inactivo no abre jornadas', 'authenticated',
    inactivoClaims, `
    insert into public.jornadas (parque_id, entrada_lat, entrada_lon)
    values ($1, 14.6350, -90.5070)
  `, [P.child], '42501');

  await expectRoleError('un perfil inactivo no crea solicitudes', 'authenticated',
    inactivoClaims, `
    insert into public.solicitudes_horas_extras (centro_costo_id, inicio, fin, justificacion)
    values ($1, now(), now() + interval '1 hour', 'Solicitud de un perfil inactivo')
  `, [A.grand], '42501');

  eq('un perfil inactivo conserva la lectura de su propio perfil',
    await withRole('authenticated', inactivoClaims, async () =>
      (await q('select id from public.perfiles')).rows.map((r) => r.id)),
    [inactivoEmp]);
} finally {
  await q('delete from auth.users where id = $1', [inactivoEmp]);
}

// Un admin inactivo conserva lectura pero no puede aprobar.
const inactivoAdmin = randomUUID();
try {
  await q(`
    insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data)
    values ($1, 'inactivo.admin@example.com', $2::jsonb,
            '{"nombre_completo":"Admin Inactivo"}'::jsonb)
  `, [inactivoAdmin, appMeta(A.empresa, A.child, 'admin')]);
  await q('update public.perfiles set activo = false where id = $1', [inactivoAdmin]);
  const inactivoAdminClaims = claims(inactivoAdmin, A.empresa, A.child, 'admin');

  eq('un admin inactivo no aprueba solicitudes',
    await withRole('authenticated', inactivoAdminClaims, async () =>
      (await q(`
        update public.solicitudes_horas_extras set estado = 'aprobada' where id = $1
      `, [S.adminPropia])).rowCount),
    0);

  await expectRoleError('un admin inactivo no crea centros', 'authenticated',
    inactivoAdminClaims, `
    insert into public.centros_costo (empresa_id, padre_id, codigo, nombre)
    values ($1, $2, 'INACTIVO', 'Centro inactivo')
  `, [A.empresa, A.child], '42501');

  eq('un admin inactivo solo ve su propio perfil',
    await withRole('authenticated', inactivoAdminClaims, async () =>
      (await q('select id from public.perfiles')).rows.map((r) => r.id)),
    [inactivoAdmin]);
  eq('un admin inactivo no ve jornadas de su equipo',
    await withRole('authenticated', inactivoAdminClaims, async () =>
      (await q('select count(*)::int from public.jornadas')).rows[0].count),
    0);
  eq('un admin inactivo no ve solicitudes de su equipo',
    await withRole('authenticated', inactivoAdminClaims, async () =>
      (await q('select count(*)::int from public.solicitudes_horas_extras')).rows[0].count),
    0);
} finally {
  await q('delete from auth.users where id = $1', [inactivoAdmin]);
}

// -----------------------------------------------------------------------------
// Geocerca congelada al entrar
// -----------------------------------------------------------------------------
group('Geocerca congelada al entrar');

const jornadaFoto = await withRole('authenticated', empAClaims, async () => {
  const r = await q(`
    insert into public.jornadas (parque_id, entrada_lat, entrada_lon, entrada_precision_metros)
    values ($1, 14.6350, -90.5070, 5)
    returning entrada_parque_lat, entrada_parque_lon, entrada_parque_radio_metros
  `, [P.child]);
  return r.rows[0];
});
eq('la jornada guarda la geocerca del parque al entrar',
  [jornadaFoto.entrada_parque_lat, jornadaFoto.entrada_parque_lon,
    jornadaFoto.entrada_parque_radio_metros],
  [14.6350, -90.5070, 100]);
eq('las jornadas existentes tienen foto de geocerca',
  await scalar(`select count(*)::int from public.jornadas
                where entrada_parque_lat is null
                   or entrada_parque_lon is null
                   or entrada_parque_radio_metros is null`),
  0);

eq('en_geocerca_snapshot acepta un punto dentro de la foto',
  await withRole('authenticated', empAClaims, async () =>
    scalar('select private.en_geocerca_snapshot(14.6350, -90.5070, 0, 14.6350, -90.5070, 100)')),
  true);
eq('en_geocerca_snapshot rechaza un punto fuera de la foto',
  await withRole('authenticated', empAClaims, async () =>
    scalar('select private.en_geocerca_snapshot(14.7000, -90.6000, 0, 14.6350, -90.5070, 100)')),
  false);

await expectRoleError('el cliente no escribe la foto de la geocerca', 'authenticated',
  empAClaims, `
  insert into public.jornadas (
    parque_id, entrada_lat, entrada_lon, entrada_parque_lat
  ) values ($1, 14.6350, -90.5070, 14.7000)
`, [P.child], '42501');

// Cierre en el punto original aunque el admin mueva y reduzca el parque.
await q('begin');
try {
  await q('set local role authenticated');
  await q(`select set_config('request.jwt.claims', $1, true)`, [JSON.stringify(empAClaims)]);
  const id = (await q(`
    insert into public.jornadas (parque_id, entrada_lat, entrada_lon)
    values ($1, 14.6350, -90.5070) returning id
  `, [P.child])).rows[0].id;

  await q('reset role');
  await q(`
    update public.parques
    set latitud = 14.7000, longitud = -90.6000, radio_metros = 1
    where id = $1
  `, [P.child]);

  await q('set local role authenticated');
  await q(`select set_config('request.jwt.claims', $1, true)`, [JSON.stringify(empAClaims)]);
  const r = await q(`
    update public.jornadas
    set salida_lat = 14.6350, salida_lon = -90.5070, salida_precision_metros = 5
    where id = $1
  `, [id]);
  const row = (await q(
    'select salida_dentro_geocerca from public.jornadas where id = $1', [id],
  )).rows[0];
  eq('cierra en el punto original aunque el parque se haya movido',
    [r.rowCount, row.salida_dentro_geocerca], [1, true]);

  // Un segundo turno que empieza en la nueva ubicación no puede cerrarse en la
  // ubicación anterior: la foto ya es la nueva.
  const id2 = (await q(`
    insert into public.jornadas (parque_id, entrada_lat, entrada_lon)
    values ($1, 14.7000, -90.6000) returning id
  `, [P.child])).rows[0].id;

  await q('savepoint cierre_viejo');
  let errorCierre = null;
  try {
    await q(`
      update public.jornadas
      set salida_lat = 14.6350, salida_lon = -90.5070
      where id = $1
    `, [id2]);
  } catch (error) {
    errorCierre = error;
  }
  await q('rollback to savepoint cierre_viejo');
  eq('un turno abierto en la nueva ubicación no cierra en la anterior',
    errorCierre?.code, '23514');

  const r2 = await q(`
    update public.jornadas
    set salida_lat = 14.7000, salida_lon = -90.6000
    where id = $1
  `, [id2]);
  const row2 = (await q(
    'select salida_dentro_geocerca from public.jornadas where id = $1', [id2],
  )).rows[0];
  eq('el turno abierto en la nueva ubicación sí cierra allí',
    [r2.rowCount, row2.salida_dentro_geocerca], [1, true]);
} finally {
  await q('rollback');
}

// -----------------------------------------------------------------------------
// Puestos, jefe responsable, autorizador y reporte (0018–0020)
// -----------------------------------------------------------------------------
group('Puestos');
const PU = {
  tecnicoA: 'a2000000-0000-4000-8000-000000000001',
  jefeA: 'a2000000-0000-4000-8000-000000000002',
  tecnicoB: 'b2000000-0000-4000-8000-000000000001',
};
await q(`
  insert into public.puestos (id, empresa_id, nombre) values
    ($1, $2, 'Técnico'),
    ($3, $2, 'Jefe de mantenimiento'),
    ($4, $5, 'Técnico');
`, [PU.tecnicoA, A.empresa, PU.jefeA, PU.tecnicoB, B.empresa]);

eq('el empleado solo ve los puestos de su empresa',
  await withRole('authenticated', empAClaims, async () =>
    (await q('select id from public.puestos order by nombre')).rows.map((r) => r.id)),
  [PU.jefeA, PU.tecnicoA]);

await expectError('rechaza un puesto repetido en la empresa', `
  insert into public.puestos (empresa_id, nombre) values ($1, 'técnico')
`, [A.empresa], '23505');

await expectRoleError('el empleado no crea puestos', 'authenticated', empAClaims, `
  insert into public.puestos (empresa_id, nombre) values ($1, 'Autoasignado')
`, [A.empresa], '42501');

await q(`
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('puesto_id', $2::text)
  where id = $1
`, [U.empA, PU.tecnicoA]);
eq('el puesto se sincroniza desde app_metadata',
  await scalar('select puesto_id from public.perfiles where id = $1', [U.empA]), PU.tecnicoA);

await expectError('rechaza un puesto de otra empresa', `
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('puesto_id', $2::text)
  where id = $1
`, [U.empA, PU.tecnicoB], '23503');

await expectRoleError('el empleado no cambia su propio puesto', 'authenticated', empAClaims, `
  update public.perfiles set puesto_id = $2 where id = $1
`, [U.empA, PU.jefeA], '42501');

group('Jefe responsable y persona que autoriza');
const autorizadorDe = (empleado) =>
  scalar('select private.autorizador_para($1)', [empleado]);

eq('sin responsables, autoriza un admin del mismo centro', await autorizadorDe(U.empA), U.gerA);
eq('el nieto sube hasta el admin del centro hijo', await autorizadorDe(U.empGrand), U.gerA);
eq('un admin nunca se autoriza a sí mismo: sube a la raíz', await autorizadorDe(U.gerA), U.gerRoot);
eq('nadie por encima de la raíz', await autorizadorDe(U.gerRoot), null);

await q('begin');
try {
  await q('update public.centros_costo set responsable_id = $2 where id = $1', [A.child, U.gerRoot]);
  eq('el responsable configurado tiene prioridad sobre otros admins',
    await autorizadorDe(U.empA), U.gerRoot);
  await q('update public.perfiles set activo = false where id = $1', [U.gerRoot]);
  eq('un responsable inactivo se ignora', await autorizadorDe(U.empA), U.gerA);
} finally {
  await q('rollback');
}

await expectError('el responsable debe tener alcance sobre el centro', `
  update public.centros_costo set responsable_id = $2 where id = $1
`, [A.sibling, U.gerA], '23514');

await expectError('el responsable debe ser admin', `
  update public.centros_costo set responsable_id = $2 where id = $1
`, [A.child, U.empA], '23514');

await expectRoleError('un admin no asigna responsables desde la API', 'authenticated',
  claims(U.gerA, A.empresa, A.child, 'admin'), `
  update public.centros_costo set responsable_id = $2 where id = $1
`, [A.grand, U.gerA], '42501');

eq('las solicitudes existentes ya tienen autorizador',
  (await q(`
    select autorizador_id, autorizador_nombre
    from public.solicitudes_horas_extras where id = $1
  `, [S.aPendiente])).rows[0],
  { autorizador_id: U.gerA, autorizador_nombre: 'Admin A' });

eq('la solicitud nueva guarda quién autoriza',
  await withRole('authenticated', claims(U.empGrand, A.empresa, A.grand, 'empleado'), async () =>
    (await q(`
      insert into public.solicitudes_horas_extras (centro_costo_id, inicio, fin, justificacion)
      values ($1, now(), now() + interval '2 hours', 'Cambio de bandas en la rueda')
      returning autorizador_id, autorizador_nombre
    `, [A.grand])).rows[0]),
  { autorizador_id: U.gerA, autorizador_nombre: 'Admin A' });

await expectRoleError('el cliente no elige al autorizador', 'authenticated', empAClaims, `
  insert into public.solicitudes_horas_extras
    (centro_costo_id, inicio, fin, justificacion, autorizador_id)
  values ($1, now(), now() + interval '1 hour', 'Intento de elegir autorizador', $2)
`, [A.grand, U.empA], '42501');

eq('el empleado consulta su autorizador con nombre y puesto',
  await withRole('authenticated', empAClaims, async () =>
    (await q('select id, nombre_completo, puesto from public.mi_autorizador()')).rows),
  [{ id: U.gerA, nombre_completo: 'Admin A', puesto: null }]);

await expectRoleError('anon no consulta autorizadores', 'anon', {}, `
  select * from public.mi_autorizador()
`, [], '42501');

group('Reporte de horas extras');
const filasReporte = (jwtClaims) =>
  withRole('authenticated', jwtClaims, async () =>
    (await q('select id, empleado, puesto, horas, ceco_codigo, persona_que_autoriza from public.reporte_horas_extras order by id')).rows);

const reporteEmpA = await filasReporte(empAClaims);
eq('el empleado solo ve sus filas en el reporte',
  [...new Set(reporteEmpA.map((r) => r.empleado))], ['Empleado A']);
const filaPendiente = reporteEmpA.find((r) => r.id === S.aPendiente);
eq('el reporte trae columnas del formulario',
  [filaPendiente.puesto, filaPendiente.horas, filaPendiente.ceco_codigo, filaPendiente.persona_que_autoriza],
  ['Técnico', '3.00', 'A-GRAND', 'Admin A']);

const reporteGerA = await filasReporte(claims(U.gerA, A.empresa, A.child, 'admin'));
ok('el admin ve las filas de su subárbol', reporteGerA.some((r) => r.id === S.grandPendiente));
ok('el admin no ve filas de otra empresa', !reporteGerA.some((r) => r.id === S.bPendiente));

await expectRoleError('anon no lee el reporte', 'anon', {}, `
  select count(*) from public.reporte_horas_extras
`, [], '42501');

// -----------------------------------------------------------------------------
// Horario personalizado y horas extras detectadas por GPS (0021)
// -----------------------------------------------------------------------------
group('Horarios personalizados');
const gerAClaims = claims(U.gerA, A.empresa, A.child, 'admin');

eq('la empresa usa la zona horaria de Guatemala por defecto',
  await scalar('select zona_horaria from public.empresas where id = $1', [A.empresa]),
  'America/Guatemala');
await expectError('rechaza una zona horaria inexistente', `
  update public.empresas set zona_horaria = 'Marte/Olympus' where id = $1
`, [A.empresa], '22023');

const insertarHorario = `
  insert into public.horarios (empleado_id, dia_semana, hora_entrada, hora_salida, parque_id)
  values ($1, $2, $3, $4, $5)
  returning empresa_id, empleado_id
`;
eq('el admin define el horario de su equipo',
  await withRole('authenticated', gerAClaims, async () =>
    (await q(insertarHorario, [U.empA, 1, '08:00', '17:00', P.child])).rows[0]),
  { empresa_id: A.empresa, empleado_id: U.empA });

await expectRoleError('el admin no define su propio horario', 'authenticated', gerAClaims,
  insertarHorario, [U.gerA, 1, '08:00', '17:00', null], '42501');
await expectRoleError('el admin no define horarios fuera de su subárbol', 'authenticated', gerAClaims,
  insertarHorario, [U.gerRoot, 1, '08:00', '17:00', null], '42501');
await expectRoleError('el horario no apunta a un parque fuera de su alcance', 'authenticated', gerAClaims,
  insertarHorario, [U.empA, 2, '08:00', '17:00', P.sibling], '42501');
await expectRoleError('el empleado no edita su horario', 'authenticated', empAClaims,
  insertarHorario, [U.empA, 3, '08:00', '17:00', null], '42501');
await expectRoleError('entrada y salida no pueden ser iguales', 'authenticated', gerAClaims,
  insertarHorario, [U.empA, 4, '08:00', '08:00', null], '23514');

// Horario de lunes para el resto de pruebas (como dueño: carga administrativa).
await q(`
  insert into public.horarios (empresa_id, empleado_id, dia_semana, hora_entrada, hora_salida, parque_id)
  values ($1, $2, 1, '08:00', '17:00', $3)
`, [A.empresa, U.empA, P.child]);

eq('el empleado ve su horario',
  await withRole('authenticated', empAClaims, async () =>
    (await q('select dia_semana, hora_entrada from public.horarios')).rows),
  [{ dia_semana: 1, hora_entrada: '08:00:00' }]);
eq('otra empresa no ve el horario',
  await withRole('authenticated', claims(U.empB, B.empresa, B.root, 'empleado'), async () =>
    Number(await scalar('select count(*) from public.horarios'))),
  0);

group('Cumplimiento y horas extras por GPS');
// Lunes 9 de noviembre de 2026 en Guatemala (UTC-6): entra 08:20 y sale 18:30.
const JC = randomUUID();
const jornadaLunes = async () => q(`
  insert into public.jornadas (
    id, empresa_id, empleado_id, parque_id, entrada_en, salida_en,
    entrada_lat, entrada_lon, entrada_precision_metros,
    salida_lat, salida_lon, salida_precision_metros, salida_dentro_geocerca
  ) values ($1, $2, $3, $4, '2026-11-09 14:20:00+00', '2026-11-10 00:30:00+00',
            14.6350, -90.5070, 5, 14.6350, -90.5070, 5, true)
`, [JC, A.empresa, U.empA, P.child]);
await jornadaLunes();

const cumplimiento = await withRole('authenticated', empAClaims, async () =>
  (await q(`
    select fecha::text, minutos_tarde, llego_tarde, minutos_extra, en_parque_programado,
           salida_programada = '2026-11-09 23:00:00+00'::timestamptz as salida_ok
    from public.cumplimiento_jornadas where jornada_id = $1
  `, [JC])).rows[0]);
eq('compara la jornada con el horario del día local',
  cumplimiento,
  { fecha: '2026-11-09', minutos_tarde: 20, llego_tarde: true, minutos_extra: 90,
    en_parque_programado: true, salida_ok: true });

eq('sin horario ese día no inventa minutos extra',
  await withRole('authenticated', empAClaims, async () =>
    (await q(`
      select minutos_extra from public.cumplimiento_jornadas where jornada_id = $1
    `, [J.aCerrada])).rows),
  [{ minutos_extra: null }]);

await q('begin');
try {
  await q(`update public.horarios set hora_entrada = '22:00', hora_salida = '06:00'
           where empleado_id = $1 and dia_semana = 1`, [U.empA]);
  eq('un turno nocturno termina al día siguiente',
    await scalar(`
      select salida_programada = '2026-11-10 12:00:00+00'::timestamptz
      from public.cumplimiento_jornadas where jornada_id = $1
    `, [JC]),
    true);
} finally {
  await q('rollback');
}

eq('el admin ve el cumplimiento de su equipo',
  await withRole('authenticated', gerAClaims, async () =>
    Number(await scalar('select count(*) from public.cumplimiento_jornadas where jornada_id = $1', [JC]))),
  1);

const solicitarDesdeJornada = `
  insert into public.solicitudes_horas_extras
    (centro_costo_id, inicio, fin, justificacion, jornada_id)
  values ($1, '2026-11-09 23:00:00+00', '2026-11-10 00:30:00+00',
          'Cierre del parque después del horario', $2)
  returning jornada_id
`;
eq('la solicitud queda respaldada por la jornada GPS',
  await withRole('authenticated', empAClaims, async () =>
    (await q(solicitarDesdeJornada, [A.child, JC])).rows[0].jornada_id),
  JC);

await expectRoleError('no se respalda con la jornada de otra persona', 'authenticated',
  claims(U.empGrand, A.empresa, A.grand, 'empleado'), solicitarDesdeJornada, [A.grand, JC], '42501');

await q(`
  insert into public.solicitudes_horas_extras
    (empresa_id, empleado_id, centro_costo_id, inicio, fin, justificacion, jornada_id)
  values ($1, $2, $3, '2026-11-09 23:00:00+00', '2026-11-10 00:30:00+00',
          'Cierre del parque después del horario', $4)
`, [A.empresa, U.empA, A.child, JC]);

await expectRoleError('una jornada respalda una sola solicitud viva', 'authenticated', empAClaims,
  solicitarDesdeJornada, [A.child, JC], '23505');

eq('el cumplimiento indica que ya se solicitó',
  await withRole('authenticated', empAClaims, async () =>
    (await scalar('select solicitud_id is not null from public.cumplimiento_jornadas where jornada_id = $1', [JC]))),
  true);

eq('el reporte marca el respaldo GPS',
  await withRole('authenticated', empAClaims, async () =>
    await scalar('select bool_or(respaldo_gps) from public.reporte_horas_extras')),
  true);

// -----------------------------------------------------------------------------
// Registro, incidencias y ajustes de jornada (0022)
// -----------------------------------------------------------------------------
group('Registro de colaboradores');
const R = { nuevo: randomUUID(), otro: randomUUID(), invitado: randomUUID(), sinEmpresa: randomUUID() };
await q(`
  insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data) values
    ($1, 'nuevo@example.com', '{}'::jsonb,
     '{"empresa_codigo":"EMPRESA-A","nombre_completo":"Técnico Nuevo","telefono":"5555-0000"}'::jsonb),
    ($2, 'otro@example.com', '{}'::jsonb,
     '{"empresa_codigo":"EMPRESA-A","nombre_completo":"Otro Aspirante"}'::jsonb),
    ($3, 'invitado@example.com', $5::jsonb,
     '{"empresa_codigo":"EMPRESA-A","nombre_completo":"Invitado"}'::jsonb),
    ($4, 'perdido@example.com', '{}'::jsonb,
     '{"empresa_codigo":"NO-EXISTE","nombre_completo":"Sin Empresa"}'::jsonb)
`, [R.nuevo, R.otro, R.invitado, R.sinEmpresa, appMeta(A.empresa, A.child, 'empleado')]);

eq('el registro propio queda pendiente en su empresa',
  (await q('select empresa_id, nombre, telefono, estado from public.registros where id = $1', [R.nuevo])).rows[0],
  { empresa_id: A.empresa, nombre: 'Técnico Nuevo', telefono: '5555-0000', estado: 'pendiente' });
eq('una invitación o un código desconocido no crean registro',
  Number(await scalar('select count(*) from public.registros where id = any($1::uuid[])', [[R.invitado, R.sinEmpresa]])), 0);
eq('sin asignación todavía no hay perfil',
  Number(await scalar('select count(*) from public.perfiles where id = $1', [R.nuevo])), 0);

eq('la persona ve su propia solicitud',
  await withRole('authenticated', { sub: R.nuevo }, async () =>
    await scalar('select estado::text from public.registros')),
  'pendiente');
eq('el admin de la empresa ve las solicitudes',
  await withRole('authenticated', gerAClaims, async () =>
    Number(await scalar('select count(*) from public.registros where estado = $1', ['pendiente']))),
  2);
eq('otra empresa no ve las solicitudes',
  await withRole('authenticated', claims(U.empB, B.empresa, B.root, 'empleado'), async () =>
    Number(await scalar('select count(*) from public.registros'))),
  0);

await expectRoleError('un empleado no aprueba registros', 'authenticated', empAClaims,
  'select public.aprobar_registro($1, $2, null)', [R.nuevo, A.grand], '42501');
await expectRoleError('el admin no asigna centros fuera de su subárbol', 'authenticated', gerAClaims,
  'select public.aprobar_registro($1, $2, null)', [R.nuevo, A.sibling], '42501');

await withRole('authenticated', gerAClaims, async () => {
  await q('select public.aprobar_registro($1, $2, $3)', [R.nuevo, A.grand, PU.tecnicoA]);
  await q('commit');
  await q('begin');
});
eq('aprobar crea el perfil como empleado con centro y puesto',
  (await q('select rol::text, centro_costo_id, puesto_id, nombre_completo::text as nombre from public.perfiles where id = $1', [R.nuevo])).rows[0],
  { rol: 'empleado', centro_costo_id: A.grand, puesto_id: PU.tecnicoA, nombre: 'Técnico Nuevo' });
eq('el registro queda aprobado y firmado',
  (await q('select estado::text, revisado_por from public.registros where id = $1', [R.nuevo])).rows[0],
  { estado: 'aprobado', revisado_por: U.gerA });

await expectRoleError('un registro aprobado no se vuelve a aprobar', 'authenticated', gerAClaims,
  'select public.aprobar_registro($1, $2, null)', [R.nuevo, A.grand], '23514');
await expectRoleError('rechazar exige motivo', 'authenticated', gerAClaims,
  'select public.rechazar_registro($1, $2)', [R.otro, 'no'], '23514');
eq('el admin rechaza con motivo',
  await withRole('authenticated', gerAClaims, async () => {
    await q('select public.rechazar_registro($1, $2)', [R.otro, 'No pertenece a la empresa']);
    return await scalar('select estado::text from public.registros where id = $1', [R.otro]);
  }),
  'rechazado');

group('Incidencias automáticas');
eq('la llegada tarde del lunes genera su incidencia',
  (await q('select tipo::text, severidad::text, estado::text from public.incidencias where jornada_id = $1', [JC])).rows,
  [{ tipo: 'llegada_tarde', severidad: 'baja', estado: 'abierta' }]);

const TU = randomUUID();
await q('begin');
try {
  await q(`insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data)
           values ($1, 'turno@example.com', $2::jsonb, '{"nombre_completo":"Turno Prueba"}'::jsonb)`,
    [TU, appMeta(A.empresa, A.child, 'empleado')]);
  await q(`insert into public.horarios (empresa_id, empleado_id, dia_semana, hora_entrada, hora_salida, parque_id)
           values ($1, $2, 1, '08:00', '17:00', $3)`, [A.empresa, TU, P.child]);
  const jt = randomUUID();
  // Lunes 9/11 a las 10:30 en otro parque y con GPS de 70 m.
  await q(`insert into public.jornadas (id, empresa_id, empleado_id, parque_id, entrada_en,
             entrada_lat, entrada_lon, entrada_precision_metros)
           values ($1, $2, $3, $4, '2026-11-09 16:30:00+00', 14.6349, -90.5069, 70)`,
    [jt, A.empresa, TU, P.root]);
  eq('detecta tardanza, parque distinto y GPS impreciso',
    (await q('select tipo::text, severidad::text from public.incidencias where jornada_id = $1 order by tipo', [jt])).rows,
    [{ tipo: 'llegada_tarde', severidad: 'alta' }, { tipo: 'parque_distinto', severidad: 'media' },
      { tipo: 'precision_baja', severidad: 'baja' }]);
  await q(`update public.jornadas set salida_en = '2026-11-09 21:00:00+00', salida_lat = 14.6349,
             salida_lon = -90.5069, salida_precision_metros = 5, salida_dentro_geocerca = true
           where id = $1`, [jt]);
  eq('salir a las 15:00 con horario hasta las 17:00 es salida temprana',
    await scalar(`select severidad::text from public.incidencias where jornada_id = $1 and tipo = 'salida_temprana'`, [jt]),
    'alta');
} finally {
  await q('rollback');
}

eq('el empleado ve sus incidencias',
  await withRole('authenticated', empAClaims, async () =>
    Number(await scalar('select count(*) from public.incidencias where jornada_id = $1', [JC]))),
  1);
eq('el empleado no puede cerrar sus incidencias',
  await withRole('authenticated', empAClaims, async () =>
    (await q(`update public.incidencias set estado = 'resuelta', resolucion = 'Me autojustifico'
              where jornada_id = $1 returning id`, [JC])).rowCount),
  0);
await expectRoleError('resolver exige una nota', 'authenticated', gerAClaims, `
  update public.incidencias set estado = 'resuelta', resolucion = 'ok' where jornada_id = $1
`, [JC], '23514');
eq('el admin resuelve y queda firmado',
  await withRole('authenticated', gerAClaims, async () =>
    (await q(`update public.incidencias set estado = 'resuelta', resolucion = 'Tráfico por lluvia, justificado'
              where jornada_id = $1 returning resuelto_por, resuelto_en is not null as fecha`, [JC])).rows[0]),
  { resuelto_por: U.gerA, fecha: true });

group('Ajustes de jornada');
await expectRoleError('el empleado no ajusta su jornada', 'authenticated', empAClaims,
  'select public.ajustar_jornada($1, $2, $3, $4)',
  [JC, '2026-11-09 14:00:00+00', '2026-11-10 00:30:00+00', 'Olvidé marcar a tiempo'], '42501');
await expectRoleError('no se ajusta una jornada abierta', 'authenticated',
  claims(U.gerRoot, A.empresa, A.root, 'admin'), 'select public.ajustar_jornada($1, $2, $3, $4)',
  [J.grandAbierta, '2026-11-09 14:00:00+00', '2026-11-09 20:00:00+00', 'Corrección de prueba'], '23514');
await expectRoleError('el ajuste exige motivo', 'authenticated', gerAClaims,
  'select public.ajustar_jornada($1, $2, $3, $4)',
  [JC, '2026-11-09 14:00:00+00', '2026-11-10 00:30:00+00', 'corto'], '23514');
await expectRoleError('la salida no puede quedar antes de la entrada', 'authenticated', gerAClaims,
  'select public.ajustar_jornada($1, $2, $3, $4)',
  [JC, '2026-11-10 01:00:00+00', '2026-11-10 00:30:00+00', 'Rango invertido de prueba'], '23514');

await withRole('authenticated', gerAClaims, async () => {
  await q('select public.ajustar_jornada($1, $2, $3, $4)',
    [JC, '2026-11-09 14:00:00+00', '2026-11-10 00:30:00+00', 'Marcó tarde por falla del celular']);
  await q('commit');
  await q('begin');
});
eq('el ajuste cambia la jornada',
  await scalar(`select entrada_en = '2026-11-09 14:00:00+00'::timestamptz from public.jornadas where id = $1`, [JC]),
  true);
eq('el empleado ve el historial del ajuste',
  await withRole('authenticated', empAClaims, async () =>
    (await q(`select entrada_anterior = '2026-11-09 14:20:00+00'::timestamptz as antes, motivo
              from public.ajustes_jornada where jornada_id = $1`, [JC])).rows),
  [{ antes: true, motivo: 'Marcó tarde por falla del celular' }]);


// -----------------------------------------------------------------------------
// Centros de costo por lugar (0023)
// -----------------------------------------------------------------------------
group('Centros de costo por lugar');
eq('el admin agrega un centro a un lugar de su alcance',
  await withRole('authenticated', gerAClaims, async () =>
    (await q(`insert into public.parques_centros (empresa_id, parque_id, centro_costo_id)
              values ($1, $2, $3) returning parque_id`, [A.empresa, P.child, A.sibling])).rows[0].parque_id),
  P.child);
await expectRoleError('no configura lugares fuera de su alcance', 'authenticated', gerAClaims, `
  insert into public.parques_centros (empresa_id, parque_id, centro_costo_id) values ($1, $2, $3)
`, [A.empresa, P.sibling, A.child], '42501');
await expectRoleError('un empleado no configura lugares', 'authenticated', empAClaims, `
  insert into public.parques_centros (empresa_id, parque_id, centro_costo_id) values ($1, $2, $3)
`, [A.empresa, P.child, A.grand], '42501');
await expectError('no mezcla centros de otra empresa', `
  insert into public.parques_centros (empresa_id, parque_id, centro_costo_id) values ($1, $2, $3)
`, [A.empresa, P.child, B.root], '23503');
await q(`insert into public.parques_centros (empresa_id, parque_id, centro_costo_id) values ($1, $2, $3)`,
  [A.empresa, P.child, A.sibling]);
eq('el empleado ve los centros de cada lugar',
  await withRole('authenticated', empAClaims, async () =>
    Number(await scalar('select count(*) from public.parques_centros where parque_id = $1', [P.child]))),
  1);
eq('otra empresa no los ve',
  await withRole('authenticated', claims(U.empB, B.empresa, B.root, 'empleado'), async () =>
    Number(await scalar('select count(*) from public.parques_centros'))),
  0);

// -----------------------------------------------------------------------------
// Auditoría
// -----------------------------------------------------------------------------
group('Auditoría');
eq('actualizado_en y actualizado_por se actualizan',
  await withRole('authenticated', claims(U.gerA, A.empresa, A.child, 'admin'), async () => {
    await q(`update public.centros_costo set nombre = 'Auditado' where id = $1`, [A.grand]);
    const r = (await q(`
      select actualizado_por, actualizado_en > creado_en as avanzo
      from public.centros_costo where id = $1
    `, [A.grand])).rows[0];
    return [r.actualizado_por, r.avanzo];
  }),
  [U.gerA, true]);

// -----------------------------------------------------------------------------
// Empresas inactivas
// -----------------------------------------------------------------------------
group('Empresas inactivas');
const adminEmpresaB = randomUUID();
await q(
  `insert into auth.users (id, email, raw_app_meta_data)
   values ($1, 'admin.b@example.com', $2::jsonb)`,
  [adminEmpresaB, appMeta(B.empresa, B.root, 'admin')],
);
try {
  const claimsEmpB = claims(U.empB, B.empresa, B.root, 'empleado');
  const claimsAdminB = claims(adminEmpresaB, B.empresa, B.root, 'admin');

  await q('update public.empresas set activa = false where id = $1', [B.empresa]);

  eq('current_empresa_id devuelve NULL para una empresa inactiva',
    await withRole('authenticated', claimsEmpB, async () =>
      scalar('select private.current_empresa_id()')), null);
  eq('la empresa inactiva no expone su fila',
    await withRole('authenticated', claimsEmpB, async () =>
      (await q('select count(*)::int from public.empresas')).rows[0].count), 0);
  eq('la empresa inactiva no expone centros',
    await withRole('authenticated', claimsEmpB, async () =>
      (await q('select count(*)::int from public.centros_costo')).rows[0].count), 0);
  eq('la empresa inactiva no expone parques',
    await withRole('authenticated', claimsEmpB, async () =>
      (await q('select count(*)::int from public.parques')).rows[0].count), 0);
  eq('la empresa inactiva no expone jornadas',
    await withRole('authenticated', claimsEmpB, async () =>
      (await q('select count(*)::int from public.jornadas')).rows[0].count), 0);
  eq('la empresa inactiva no expone solicitudes',
    await withRole('authenticated', claimsEmpB, async () =>
      (await q('select count(*)::int from public.solicitudes_horas_extras')).rows[0].count), 0);
  eq('la empresa inactiva conserva la lectura del propio perfil',
    await withRole('authenticated', claimsEmpB, async () =>
      (await q('select id from public.perfiles')).rows.map((r) => r.id)), [U.empB]);
  eq('un admin de una empresa inactiva no actualiza la empresa',
    await withRole('authenticated', claimsAdminB, async () =>
      (await q(`update public.empresas set nombre = 'Suspendida' where id = $1`, [B.empresa])).rowCount),
    0);
  await expectRoleError('un admin de una empresa inactiva no crea centros', 'authenticated',
    claimsAdminB, `
      insert into public.centros_costo (empresa_id, padre_id, codigo, nombre)
      values ($1, $2, 'B-INACTIVA', 'Centro bloqueado')
    `, [B.empresa, B.root], '42501');
  eq('una empresa inactiva no afecta a las demás',
    await withRole('authenticated', claims(U.gerRoot, A.empresa, A.root, 'admin'), async () =>
      (await q('select count(*)::int from public.parques')).rows[0].count), 4);
} finally {
  await q('update public.empresas set activa = true where id = $1', [B.empresa]);
  await q('delete from auth.users where id = $1', [adminEmpresaB]);
}

eq('al reactivar la empresa se recupera el acceso',
  await withRole('authenticated', claims(U.empB, B.empresa, B.root, 'empleado'), async () =>
    (await q('select count(*)::int from public.parques')).rows[0].count), 1);

// -----------------------------------------------------------------------------
// Degradación de administradores
// -----------------------------------------------------------------------------
group('Degradación de administradores');
await q('begin');
try {
  await q(
    `update auth.users set raw_app_meta_data = $1::jsonb where id = $2`,
    [appMeta(A.empresa, A.child, 'empleado'), U.gerA],
  );
  eq('la degradación se materializa en el perfil',
    await scalar('select rol from public.perfiles where id = $1', [U.gerA]), 'empleado');

  // El JWT de la prueba sigue diciendo admin: es el escenario de una sesión
  // abierta antes de la degradación.
  await q('set local role authenticated');
  await q(`select set_config('request.jwt.claims', $1, true)`,
    [JSON.stringify(claims(U.gerA, A.empresa, A.child, 'admin'))]);

  eq('un admin degradado conserva el JWT pero deja de ser admin',
    await scalar('select private.es_admin()'), false);
  eq('un admin degradado no aprueba solicitudes de su antiguo equipo',
    (await q(`update public.solicitudes_horas_extras set estado = 'aprobada' where id = $1`,
      [S.aPendiente])).rowCount,
    0);
  eq('un admin degradado no ve perfiles de su antiguo equipo',
    (await q('select count(*)::int from public.perfiles where id <> $1', [U.gerA])).rows[0].count,
    0);
  eq('un admin degradado no ve jornadas de su antiguo equipo',
    (await q('select count(*)::int from public.jornadas where empleado_id <> $1', [U.gerA])).rows[0].count,
    0);
  eq('un admin degradado solo ve sus propias solicitudes',
    (await q('select count(*)::int from public.solicitudes_horas_extras where empleado_id <> $1', [U.gerA])).rows[0].count,
    0);
  await q('reset role');
} finally {
  await q('rollback');
}

// -----------------------------------------------------------------------------
// Cambio de alcance de administradores
// -----------------------------------------------------------------------------
group('Cambio de alcance de administradores');
await q('begin');
try {
  // Mover el perfil al centro hermano conserva la empresa y no rompe el
  // historial, pero el JWT de la prueba sigue apuntando al centro anterior.
  await q('update public.perfiles set centro_costo_id = $1 where id = $2',
    [A.sibling, U.gerA]);

  await q('set local role authenticated');
  await q(`select set_config('request.jwt.claims', $1, true)`,
    [JSON.stringify(claims(U.gerA, A.empresa, A.child, 'admin'))]);

  eq('un admin con el centro cambiado deja de ser admin con el JWT viejo',
    await scalar('select private.es_admin()'), false);
  eq('un admin con el centro cambiado no ve perfiles de su antiguo equipo',
    (await q('select count(*)::int from public.perfiles where id <> $1', [U.gerA])).rows[0].count,
    0);
  eq('un admin con el centro cambiado no aprueba solicitudes de su antiguo equipo',
    (await q(`update public.solicitudes_horas_extras set estado = 'aprobada' where id = $1`,
      [S.aPendiente])).rowCount,
    0);

  // Con el JWT actualizado al centro nuevo recupera el rol.
  await q('reset role');
  await q('set local role authenticated');
  await q(`select set_config('request.jwt.claims', $1, true)`,
    [JSON.stringify(claims(U.gerA, A.empresa, A.sibling, 'admin'))]);
  eq('con el JWT del centro nuevo recupera el rol',
    await scalar('select private.es_admin()'), true);
  await q('reset role');
} finally {
  await q('rollback');
}

// -----------------------------------------------------------------------------
// Sin claims y anon
// -----------------------------------------------------------------------------
group('Fail-closed y anon');
eq('sin app_metadata no hay acceso a empresas',
  await withRole('authenticated', { sub: U.empA }, async () =>
    (await q('select count(*)::int from public.empresas')).rows[0].count),
  0);
eq('sin app_metadata no hay acceso a parques',
  await withRole('authenticated', { sub: U.empA }, async () =>
    (await q('select count(*)::int from public.parques')).rows[0].count),
  0);
eq('sin app_metadata el usuario sí ve su propio perfil',
  await withRole('authenticated', { sub: U.empA }, async () =>
    (await q('select count(*)::int from public.perfiles')).rows[0].count),
  1);
eq('sin app_metadata no hay acceso a jornadas',
  await withRole('authenticated', { sub: U.empA }, async () =>
    (await q('select count(*)::int from public.jornadas')).rows[0].count),
  0);
eq('sin app_metadata no hay acceso a solicitudes',
  await withRole('authenticated', { sub: U.empA }, async () =>
    (await q('select count(*)::int from public.solicitudes_horas_extras')).rows[0].count),
  0);

for (const table of BUSINESS_TABLES) {
  await expectRoleError(`anon sin acceso a ${table}`, 'anon', {},
    `select count(*) from public.${table}`, [], '42501');
}

// -----------------------------------------------------------------------------
// Resumen
// -----------------------------------------------------------------------------
console.log(`\n========================================`);
console.log(`PRUEBAS: ${pass} OK, ${fail} FAIL`);
if (fail > 0) {
  console.log('Fallos:');
  for (const f of failures) console.log(` - ${f}`);
}
console.log(`========================================`);

await client.end();
if (fail > 0) exitCode = 1;
}

try {
  await main();
} catch (error) {
  console.error('\n[error] La validación no pudo completarse:');
  console.error(error);
  exitCode = 1;
} finally {
  try {
    await pg.stop();
  } catch (error) {
    console.error('[pg:stop]', error.message);
  }

  if (!keepData) {
    for (let attempt = 1; attempt <= 5; attempt++) {
      try {
        fs.rmSync(dataDir, { recursive: true, force: true });
        break;
      } catch (error) {
        if (attempt === 5) {
          console.error(`[cleanup] No se pudo borrar ${dataDir}: ${error.message}`);
          console.error('[cleanup] Usa --keep para conservarlo o bórralo manualmente.');
        } else {
          await new Promise((resolve) => setTimeout(resolve, 500));
        }
      }
    }
  } else {
    console.log(`[keep] Datos conservados en ${dataDir}`);
  }

  process.exitCode = exitCode;
}
