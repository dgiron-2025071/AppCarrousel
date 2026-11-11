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
eq('políticas RLS creadas (2+4+4+1+3+4)', await scalar(`
  select count(*)::int from pg_policies where schemaname = 'public'
`), 18);
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
eq('las FK de empleado usan ON DELETE RESTRICT', await scalar(`
  select count(*)::int
  from pg_constraint c
  join pg_class t on t.oid = c.conrelid
  join pg_namespace n on n.oid = t.relnamespace
  where n.nspname = 'public'
    and t.relname in ('jornadas', 'solicitudes_horas_extras')
    and c.conname in (
      'jornadas_empleado_id_fkey',
      'solicitudes_horas_extras_empleado_id_fkey'
    )
    and c.contype = 'f'
    and c.confdeltype = 'r'
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
    ['23503', 'jornadas_empleado_id_fkey', 1, 1]);

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
    ['23503', 'solicitudes_horas_extras_empleado_id_fkey', 1, 1]);
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
