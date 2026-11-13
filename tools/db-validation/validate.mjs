import EmbeddedPostgres from 'embedded-postgres';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { parsearCsv } from '../importar-ceco/lib/csv.mjs';
import { construirPlan, generarSql } from '../importar-ceco/lib/ceco.mjs';

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
  'puestos', 'horarios', 'registros_pendientes', 'parques_centros',
  'incidencias_jornada', 'jornadas_ajustes',
];
eq('12 tablas de negocio', await scalar(`
  select count(*)::int from information_schema.tables
  where table_schema = 'public'
    and table_name = any ($1::text[])
`, [BUSINESS_TABLES]), 12);
eq('RLS habilitada en las 12 tablas', await scalar(`
  select count(*)::int from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = any ($1::text[])
    and c.relrowsecurity
`, [BUSINESS_TABLES]), 12);
eq('extensiones citext y pgcrypto', await scalar(`
  select count(*)::int from pg_extension where extname in ('citext','pgcrypto')
`), 2);
// No se fija el total de políticas para no romper el arnés cada vez que una
// migración agrega una tabla. Se exige que cada tabla de negocio tenga al
// menos una y que no se pierdan las que ya existían (>= 18).
const policyCount = await scalar(`
  select count(*)::int from pg_policies where schemaname = 'public'
`);
ok('se conservan al menos 18 políticas RLS', policyCount >= 18, `actual=${policyCount}`);
eq('toda tabla de negocio tiene al menos una política RLS', await scalar(`
  select count(*)::int
  from unnest($1::text[]) as t(nombre)
  where exists (
    select 1 from pg_policies p
    where p.schemaname = 'public' and p.tablename = t.nombre
  )
`, [BUSINESS_TABLES]), 12);
eq('enum de estado de solicitud', await scalar(`
  select enum_range(null::public.estado_solicitud)::text
`), '{pendiente,aprobada,rechazada,cancelada}');

// Red de seguridad para migraciones futuras: una tabla nueva sin RLS, un grant
// accidental a anon o un SECURITY DEFINER sin search_path fijo debe fallar el
// arnés, aunque ninguna prueba funcional lo toque todavía.
eq('todas las tablas públicas tienen RLS', await scalar(`
  select count(*)::int from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind = 'r'
    and not c.relrowsecurity
`), 0);
eq('anon no tiene escritura en tablas públicas', await scalar(`
  select count(*)::int
  from information_schema.role_table_grants
  where table_schema = 'public'
    and grantee = 'anon'
    and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER')
`), 0);
eq('toda función SECURITY DEFINER fija search_path', await scalar(`
  select count(*)::int
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public','private')
    and p.prosecdef
    and not coalesce(p.proconfig @> array['search_path=""'], false)
`), 0);
eq('ninguna función es ejecutable por PUBLIC/anon', await scalar(`
  select count(*)::int
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public','private')
    and (
      p.proacl is null
      or exists (
        select 1
        from aclexplode(p.proacl) a
        where a.grantee = 0
          and a.privilege_type = 'EXECUTE'
      )
    )
`), 0);

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

// Retirar el alcance debe cortar el acceso de un token ya emitido.
await q('begin');
try {
  const revocable = randomUUID();
  await q(`insert into auth.users (id, email, raw_app_meta_data) values ($1,'revocable@example.com',$2::jsonb)`,
    [revocable, appMeta(A.empresa, A.child, 'empleado')]);
  await q(`update auth.users set raw_app_meta_data = '{}'::jsonb where id = $1`, [revocable]);
  eq('quitar los claims desactiva el perfil existente',
    await scalar('select activo from public.perfiles where id = $1', [revocable]), false);
  await q(`update auth.users set raw_app_meta_data = $1::jsonb where id = $2`,
    [appMeta(A.empresa, A.grand, 'empleado'), revocable]);
  eq('restaurar los claims no reactiva una baja',
    await scalar('select activo from public.perfiles where id = $1', [revocable]), false);
  eq('restaurar los claims sí actualiza el alcance',
    await scalar('select centro_costo_id from public.perfiles where id = $1', [revocable]), A.grand);
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
// Coherencia de revisión y solicitudes sin solape
// -----------------------------------------------------------------------------
group('Coherencia de revisión y solicitudes sin solape');

eq('la restricción de exclusión por empleado y rango existe', await scalar(`
  select count(*)::int
  from pg_constraint c
  join pg_class t on t.oid = c.conrelid
  join pg_namespace n on n.oid = t.relnamespace
  where n.nspname = 'public'
    and t.relname = 'solicitudes_horas_extras'
    and c.conname = 'solicitudes_sin_solape'
    and c.contype = 'x'
    and pg_get_constraintdef(c.oid) like '%tstzrange(inicio, fin, ''[)''::text)%'
`), 1);

await expectError('una solicitud aprobada exige revisor',
  `insert into public.solicitudes_horas_extras (
     empresa_id, empleado_id, centro_costo_id, inicio, fin,
     justificacion, estado, revisado_en
   ) values (
     $1, $2, $3, now() + interval '30 days', now() + interval '30 days' + interval '1 hour',
     'Aprobada sin la firma del revisor', 'aprobada', now()
   )`,
  [A.empresa, U.empA, A.child], '23514');

await expectError('una solicitud cancelada no conserva revisor',
  `insert into public.solicitudes_horas_extras (
     empresa_id, empleado_id, centro_costo_id, inicio, fin,
     justificacion, estado, revisado_por, revisado_en
   ) values (
     $1, $2, $3, now() + interval '31 days', now() + interval '31 days' + interval '1 hour',
     'Cancelada con un revisor que no participó', 'cancelada', $4, now()
   )`,
  [A.empresa, U.empA, A.child, U.gerA], '23514');

await expectError('una solicitud pendiente no nace con comentario del admin',
  `insert into public.solicitudes_horas_extras (
     empresa_id, empleado_id, centro_costo_id, inicio, fin,
     justificacion, estado, comentario_admin
   ) values (
     $1, $2, $3, now() + interval '32 days', now() + interval '32 days' + interval '1 hour',
     'Pendiente con comentario anticipado', 'pendiente', 'comentario fuera de lugar'
   )`,
  [A.empresa, U.empA, A.child], '23514');

await q('begin');
try {
  const base = { empresa: A.empresa, empleado: U.empGrand, centro: A.grand };

  const primera = await q(`
    insert into public.solicitudes_horas_extras (
      empresa_id, empleado_id, centro_costo_id, inicio, fin, justificacion
    ) values (
      $1, $2, $3, now() + interval '40 days', now() + interval '40 days' + interval '1 hour',
      'Primera solicitud viva en el rango'
    )
  `, [base.empresa, base.empleado, base.centro]);
  eq('la primera solicitud del rango se crea', primera.rowCount, 1);

  await q('savepoint solape_pendiente');
  let errorPendiente = null;
  try {
    await q(`
      insert into public.solicitudes_horas_extras (
        empresa_id, empleado_id, centro_costo_id, inicio, fin, justificacion
      ) values (
        $1, $2, $3, now() + interval '40 days' + interval '30 minutes',
        now() + interval '40 days' + interval '90 minutes',
        'Solicitud pendiente solapada con la primera'
      )
    `, [base.empresa, base.empleado, base.centro]);
  } catch (error) {
    errorPendiente = error;
  }
  await q('rollback to savepoint solape_pendiente');
  eq('dos solicitudes pendientes solapadas se rechazan',
    errorPendiente?.code, '23P01');

  await q('savepoint solape_aprobada');
  let errorAprobada = null;
  try {
    await q(`
      insert into public.solicitudes_horas_extras (
        empresa_id, empleado_id, centro_costo_id, inicio, fin, justificacion,
        estado, revisado_por, revisado_en
      ) values (
        $1, $2, $3, now() + interval '40 days' + interval '15 minutes',
        now() + interval '40 days' + interval '45 minutes',
        'Aprobada solapada con una solicitud viva', 'aprobada', $4, now()
      )
    `, [base.empresa, base.empleado, base.centro, U.gerA]);
  } catch (error) {
    errorAprobada = error;
  }
  await q('rollback to savepoint solape_aprobada');
  eq('una solicitud aprobada tampoco se solapa con una viva',
    errorAprobada?.code, '23P01');

  const contigua = await q(`
    insert into public.solicitudes_horas_extras (
      empresa_id, empleado_id, centro_costo_id, inicio, fin, justificacion
    ) values (
      $1, $2, $3, now() + interval '40 days' + interval '1 hour',
      now() + interval '40 days' + interval '2 hours',
      'Solicitud contigua sin solape'
    )
  `, [base.empresa, base.empleado, base.centro]);
  eq('dos rangos contiguos no se consideran solape', contigua.rowCount, 1);

  const rechazada = await q(`
    insert into public.solicitudes_horas_extras (
      empresa_id, empleado_id, centro_costo_id, inicio, fin, justificacion,
      estado, revisado_por, revisado_en
    ) values (
      $1, $2, $3, now() + interval '50 days', now() + interval '50 days' + interval '1 hour',
      'Solicitud rechazada que libera el rango', 'rechazada', $4, now()
    )
  `, [base.empresa, base.empleado, base.centro, U.gerA]);
  eq('una solicitud rechazada se registra', rechazada.rowCount, 1);

  const sobreRechazada = await q(`
    insert into public.solicitudes_horas_extras (
      empresa_id, empleado_id, centro_costo_id, inicio, fin, justificacion
    ) values (
      $1, $2, $3, now() + interval '50 days', now() + interval '50 days' + interval '1 hour',
      'Solicitud corregida sobre un rango rechazado'
    )
  `, [base.empresa, base.empleado, base.centro]);
  eq('una rechazada libera el rango para reenviar', sobreRechazada.rowCount, 1);

  const cancelada = await q(`
    insert into public.solicitudes_horas_extras (
      empresa_id, empleado_id, centro_costo_id, inicio, fin, justificacion,
      estado, revisado_en
    ) values (
      $1, $2, $3, now() + interval '60 days', now() + interval '60 days' + interval '1 hour',
      'Solicitud cancelada que libera el rango', 'cancelada', now()
    )
  `, [base.empresa, base.empleado, base.centro]);
  eq('una solicitud cancelada se registra sin revisor', cancelada.rowCount, 1);

  const sobreCancelada = await q(`
    insert into public.solicitudes_horas_extras (
      empresa_id, empleado_id, centro_costo_id, inicio, fin, justificacion
    ) values (
      $1, $2, $3, now() + interval '60 days', now() + interval '60 days' + interval '1 hour',
      'Solicitud corregida sobre un rango cancelado'
    )
  `, [base.empresa, base.empleado, base.centro]);
  eq('una cancelada libera el rango para reenviar', sobreCancelada.rowCount, 1);
} finally {
  await q('rollback');
}

// -----------------------------------------------------------------------------
// Revisor administrador
// -----------------------------------------------------------------------------
group('Revisor administrador');

await expectError('un empleado no puede quedar como revisor',
  `insert into public.solicitudes_horas_extras (
     empresa_id, empleado_id, centro_costo_id, inicio, fin,
     justificacion, estado, revisado_por, revisado_en
   ) values (
     $1, $2, $3, now() + interval '70 days', now() + interval '70 days' + interval '1 hour',
     'Revisión firmada por un empleado', 'aprobada', $4, now()
   )`,
  [A.empresa, U.empA, A.child, U.empGrand], '23514');

await expectError('el especialista no puede figurar como su propio revisor',
  `insert into public.solicitudes_horas_extras (
     empresa_id, empleado_id, centro_costo_id, inicio, fin,
     justificacion, estado, revisado_por, revisado_en
   ) values (
     $1, $2, $3, now() + interval '71 days', now() + interval '71 days' + interval '1 hour',
     'Autoaprobación fuera de RLS', 'aprobada', $2, now()
   )`,
  [A.empresa, U.empA, A.child], '23514');

await q('begin');
try {
  const firmada = await q(`
    insert into public.solicitudes_horas_extras (
      empresa_id, empleado_id, centro_costo_id, inicio, fin,
      justificacion, estado, revisado_por, revisado_en
    ) values (
      $1, $2, $3, now() + interval '72 days', now() + interval '72 days' + interval '1 hour',
      'Revisión firmada por un administrador', 'aprobada', $4, now()
    )
  `, [A.empresa, U.empA, A.child, U.gerA]);
  eq('un administrador de la empresa sí puede firmar la revisión',
    firmada.rowCount, 1);
} finally {
  await q('rollback');
}

await q('begin');
try {
  await q('update public.perfiles set activo = false where id = $1', [U.gerRoot]);

  await q('savepoint revisor_inactivo');
  let errorInactivo = null;
  try {
    await q(`
      insert into public.solicitudes_horas_extras (
        empresa_id, empleado_id, centro_costo_id, inicio, fin,
        justificacion, estado, revisado_por, revisado_en
      ) values (
        $1, $2, $3, now() + interval '73 days', now() + interval '73 days' + interval '1 hour',
        'Revisión firmada por un administrador inactivo', 'aprobada', $4, now()
      )
    `, [A.empresa, U.empA, A.child, U.gerRoot]);
  } catch (error) {
    errorInactivo = error;
  }
  await q('rollback to savepoint revisor_inactivo');
  eq('un administrador inactivo no puede firmar una revisión nueva',
    errorInactivo?.code, '23514');

  eq('desactivar al revisor no invalida la revisión que ya firmó',
    await scalar(`
      select count(*)::int
      from public.solicitudes_horas_extras
      where revisado_por = $1
        and estado in ('aprobada', 'rechazada')
    `, [U.gerRoot]),
    1);
} finally {
  await q('rollback');
}

await q('begin');
try {
  const reasignable = (await q(`
    insert into public.solicitudes_horas_extras (
      empresa_id, empleado_id, centro_costo_id, inicio, fin,
      justificacion, estado, revisado_por, revisado_en
    ) values (
      $1, $2, $3, now() + interval '80 days', now() + interval '80 days' + interval '1 hour',
      'Solicitud reasignable con un revisor válido', 'aprobada', $4, now()
    ) returning id
  `, [A.empresa, U.empA, A.child, U.gerA])).rows[0].id;

  await q('savepoint reasignacion_invalida');
  let errorAutoRevision = null;
  try {
    await q(
      'update public.solicitudes_horas_extras set empleado_id = $1 where id = $2',
      [U.gerA, reasignable],
    );
  } catch (error) {
    errorAutoRevision = error;
  }
  await q('rollback to savepoint reasignacion_invalida');
  eq('reasignar la solicitud al revisor se rechaza',
    errorAutoRevision?.code, '23514');

  eq('reasignar a otro especialista revalida al revisor',
    (await q(
      'update public.solicitudes_horas_extras set empleado_id = $1 where id = $2',
      [U.empGrand, reasignable],
    )).rowCount,
    1);
} finally {
  await q('rollback');
}

// =============================================================================
// MT-02: puestos, autorizador, horarios, registro, CECO por lugar,
// incidencias/ajustes y reportes (migraciones 0023–0028)
// =============================================================================
const T = {
  puestoOps: 'a2000000-0000-4000-8000-000000000001',
  puestoSupervisor: 'a2000000-0000-4000-8000-000000000002',
  puestoB: 'a2000000-0000-4000-8000-000000000003',
  cecoExtra: 'c2000000-0000-4000-8000-000000000001',
  cecoB: 'c2000000-0000-4000-8000-000000000002',
  reg1: 'e2000000-0000-4000-8000-000000000001',
  reg2: 'e2000000-0000-4000-8000-000000000002',
  regB: 'e2000000-0000-4000-8000-000000000003',
  jLate: 'd2000000-0000-4000-8000-000000000001',
  jGps: 'd2000000-0000-4000-8000-000000000002',
  jPark: 'd2000000-0000-4000-8000-000000000003',
  jAdjust: 'd2000000-0000-4000-8000-000000000004',
  ajuste: 'f2000000-0000-4000-8000-000000000001',
};

// Fixtures persistidas. Se crean después de todas las pruebas anteriores para
// no alterar sus conteos y se usan en los grupos siguientes.
await q(`
  insert into public.puestos (id, empresa_id, codigo, nombre) values
    ($1, $4, 'OPS', 'Operador'),
    ($2, $4, 'SUP', 'Supervisor'),
    ($3, $5, 'OPS', 'Operador B');
`, [T.puestoOps, T.puestoSupervisor, T.puestoB, A.empresa, B.empresa]);

await q(`
  insert into public.centros_costo (id, empresa_id, padre_id, codigo, nombre) values
    ($1, $3, $4, 'A-EXTRA', 'Centro extra A'),
    ($2, $5, $6, 'B-EXTRA', 'Centro extra B');
`, [T.cecoExtra, T.cecoB, A.empresa, A.child, B.empresa, B.root]);

await q('update public.centros_costo set jefe_id = $1 where id = $2',
  [U.gerA, A.child]);

const isodowHoy =
  `extract(isodow from (now() at time zone 'America/Guatemala'))::smallint`;
const otroDia =
  `(case when extract(isodow from (now() at time zone 'America/Guatemala'))::int = 7
         then 1::smallint else 7::smallint end)`;

await q(`
  insert into public.horarios (
    empresa_id, empleado_id, dia_semana, hora_entrada, hora_salida,
    tolerancia_entrada_min, tolerancia_salida_min
  ) values
    ($1, $2, ${isodowHoy}, '08:00', '17:00', 10, 10),
    ($1, $3, ${isodowHoy}, '08:00', '17:00', 10, 10),
    ($4, $5, ${isodowHoy}, '08:00', '17:00', 10, 10);
`, [A.empresa, U.empA, U.empGrand, B.empresa, U.empB]);

await q(`
  insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data) values
    ($1, 'reg.uno@example.com', '{}'::jsonb, '{"nombre_completo":"Registro Uno"}'::jsonb),
    ($2, 'reg.dos@example.com', '{}'::jsonb, '{"nombre_completo":"Registro Dos"}'::jsonb),
    ($3, 'reg.b@example.com',   '{}'::jsonb, '{"nombre_completo":"Registro B"}'::jsonb);
`, [T.reg1, T.reg2, T.regB]);

const localHora = (hhmm) =>
  `((date_trunc('day', now() at time zone 'America/Guatemala') + interval '${hhmm}') at time zone 'America/Guatemala')`;

await q(`
  insert into public.jornadas (
    id, empresa_id, empleado_id, parque_id, entrada_en, salida_en,
    entrada_lat, entrada_lon, entrada_precision_metros, entrada_dentro_geocerca,
    salida_lat, salida_lon, salida_precision_metros, salida_dentro_geocerca
  ) values
    ($1, $2, $3, $4, ${localHora('09:15')}, ${localHora('16:30')},
     14.6350, -90.5070, 5, true, 14.6350, -90.5070, 5, true),
    ($5, $2, $3, $4, ${localHora('08:00')}, ${localHora('17:00')},
     14.6350, -90.5070, 150, true, 14.6350, -90.5070, 150, true),
    ($6, $2, $3, $7, ${localHora('08:00')}, ${localHora('17:00')},
     14.6352, -90.5072, 5, true, 14.6352, -90.5072, 5, true),
    ($8, $2, $3, $4, ${localHora('09:15')}, ${localHora('16:30')},
     14.6350, -90.5070, 5, true, 14.6350, -90.5070, 5, true);
`, [T.jLate, A.empresa, U.empA, P.child, T.jGps, T.jPark, P.sibling, T.jAdjust]);

// Historial de ajuste previo, para probar su inmutabilidad.
await q(`
  insert into public.jornadas_ajustes (
    id, empresa_id, jornada_id, empleado_id, ajustado_por, motivo,
    entrada_en_anterior, salida_en_anterior,
    entrada_en_nueva, salida_en_nueva
  ) values (
    $1, $2, $3, $4, $5, 'Corrección inicial de prueba',
    now() - interval '10 hours', now() - interval '2 hours',
    now() - interval '10 hours', now() - interval '3 hours'
  );
`, [T.ajuste, A.empresa, J.aCerrada, U.empA, U.gerA]);

// -----------------------------------------------------------------------------
// Puestos y autorizador jerárquico
// -----------------------------------------------------------------------------
group('Puestos y autorizador jerárquico');

eq('el empleado ve solo los puestos de su empresa',
  await withRole('authenticated', claims(U.empA, A.empresa, A.child, 'empleado'), async () =>
    (await q('select count(*)::int from public.puestos')).rows[0].count), 2);

eq('el admin ve solo los puestos de su empresa',
  await withRole('authenticated', claims(U.gerA, A.empresa, A.child, 'admin'), async () =>
    (await q('select count(*)::int from public.puestos')).rows[0].count), 2);

eq('un admin activo crea puestos en su empresa',
  await withRole('authenticated', claims(U.gerA, A.empresa, A.child, 'admin'), async () =>
    (await q(`
      insert into public.puestos (empresa_id, codigo, nombre)
      values ($1, 'TMP', 'Temporal')
    `, [A.empresa])).rowCount), 1);

eq('un empleado no crea puestos',
  await (async () => {
    let code = null;
    try {
      await withRole('authenticated', claims(U.empA, A.empresa, A.child, 'empleado'), async () =>
        q(`insert into public.puestos (empresa_id, codigo, nombre)
           values ($1, 'NO', 'No permitido')`, [A.empresa]));
    } catch (error) {
      code = error.code;
    }
    return code;
  })(), '42501');

await expectRoleError('un admin no crea puestos en otra empresa',
  'authenticated', claims(U.gerA, A.empresa, A.child, 'admin'),
  `insert into public.puestos (empresa_id, codigo, nombre)
   values ($1, 'CROSS', 'Cruce')`, [B.empresa], '42501');

await expectRoleError('el código de puesto es único por empresa',
  'authenticated', claims(U.gerA, A.empresa, A.child, 'admin'),
  `insert into public.puestos (empresa_id, codigo, nombre)
   values ($1, 'OPS', 'Duplicado')`, [A.empresa], '23505');

await expectRoleError('el nombre del puesto no puede quedar vacío',
  'authenticated', claims(U.gerA, A.empresa, A.child, 'admin'),
  `insert into public.puestos (empresa_id, codigo, nombre)
   values ($1, 'EMPTY', '   ')`, [A.empresa], '23514');

eq('el jefe del centro se hereda del ancestro más cercano',
  await withRole('authenticated', claims(U.gerA, A.empresa, A.child, 'admin'), async () =>
    scalar('select private.jefe_de_centro($1)', [A.grand])), U.gerA);

eq('un centro sin jefe propio ni ancestro devuelve NULL',
  await withRole('authenticated', claims(U.gerRoot, A.empresa, A.root, 'admin'), async () =>
    scalar('select private.jefe_de_centro($1)', [A.sibling])), null);

eq('el jefe designado es autorizador de su subárbol',
  await withRole('authenticated', claims(U.gerA, A.empresa, A.child, 'admin'), async () =>
    scalar('select private.es_autorizador($1)', [A.grand])), true);

eq('otro admin no es autorizador del centro',
  await withRole('authenticated', claims(U.gerRoot, A.empresa, A.root, 'admin'), async () =>
    scalar('select private.es_autorizador($1)', [A.grand])), false);

await expectError('el jefe del centro debe ser administrador',
  'update public.centros_costo set jefe_id = $1 where id = $2',
  [U.empA, A.child], '23514');

await expectError('el jefe del centro debe ser de la misma empresa',
  'update public.centros_costo set jefe_id = $1 where id = $2',
  [U.empB, A.child], '23503');

await q('begin');
try {
  await q('update public.perfiles set activo = false where id = $1', [U.gerA]);
  await q('savepoint jefe_inactivo');
  let errorInactivo = null;
  try {
    await q('update public.centros_costo set jefe_id = $1 where id = $2',
      [U.gerA, A.sibling]);
  } catch (error) {
    errorInactivo = error;
  }
  ok('un administrador inactivo no puede ser jefe del centro',
    errorInactivo?.code === '23514',
    `code=${errorInactivo?.code}`);
} finally {
  await q('rollback');
}

eq('el admin asigna el jefe de un centro de su alcance',
  await withRole('authenticated', claims(U.gerRoot, A.empresa, A.root, 'admin'), async () =>
    (await q('update public.centros_costo set jefe_id = $1 where id = $2',
      [U.gerA, A.sibling])).rowCount), 1);

await q('begin');
try {
  await q(`insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data)
    values ($1, 'puesto.ok@example.com', $2::jsonb,
            '{"nombre_completo":"Puesto OK"}'::jsonb)`, [
    'e2000000-0000-4000-8000-000000000010',
    JSON.stringify({
      empresa_id: A.empresa,
      centro_costo_id: A.child,
      rol: 'empleado',
      puesto_id: T.puestoOps,
    }),
  ]);
  eq('la sincronización materializa el puesto del claim',
    await scalar('select puesto_id from public.perfiles where id = $1',
      ['e2000000-0000-4000-8000-000000000010']),
    T.puestoOps);
} finally {
  await q('rollback');
}

await expectRoleError('la sincronización rechaza un puesto de otra empresa',
  'service_role', {},
  `insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data)
   values ($1, 'puesto.bad@example.com', $2::jsonb, '{}'::jsonb)`, [
    'e2000000-0000-4000-8000-000000000011',
    JSON.stringify({
      empresa_id: A.empresa,
      centro_costo_id: A.child,
      rol: 'empleado',
      puesto_id: T.puestoB,
    }),
  ], '23503');

await expectRoleError('el cliente no escribe el puesto del perfil',
  'authenticated', claims(U.empA, A.empresa, A.child, 'empleado'),
  'update public.perfiles set puesto_id = $1 where id = $2',
  [T.puestoOps, U.empA], '42501');

// -----------------------------------------------------------------------------
// Horarios, zona horaria y GPS
// -----------------------------------------------------------------------------
group('Horarios, zona horaria y GPS');

eq('el empleado ve su propio horario',
  await withRole('authenticated', claims(U.empA, A.empresa, A.child, 'empleado'), async () =>
    (await q('select count(*)::int from public.horarios')).rows[0].count), 1);

eq('el admin ve el horario de su subárbol y no el de otra empresa',
  await withRole('authenticated', claims(U.gerA, A.empresa, A.child, 'admin'), async () =>
    (await q('select count(*)::int from public.horarios')).rows[0].count), 2);

eq('el empleado de otra empresa ve solo su horario',
  await withRole('authenticated', claims(U.empB, B.empresa, B.root, 'empleado'), async () =>
    (await q('select count(*)::int from public.horarios')).rows[0].count), 1);

eq('un admin activo crea el horario de su subárbol',
  await withRole('authenticated', claims(U.gerA, A.empresa, A.child, 'admin'), async () =>
    (await q(`
      insert into public.horarios (
        empresa_id, empleado_id, dia_semana, hora_entrada, hora_salida
      ) values ($1, $2, ${otroDia}, '07:00', '15:00')
    `, [A.empresa, U.empGrand])).rowCount), 1);

await expectRoleError('un empleado no crea horarios',
  'authenticated', claims(U.empA, A.empresa, A.child, 'empleado'),
  `insert into public.horarios (
     empresa_id, empleado_id, dia_semana, hora_entrada, hora_salida
   ) values ($1, $2, ${otroDia}, '07:00', '15:00')`,
  [A.empresa, U.empA], '42501');

await expectRoleError('un admin no crea horarios fuera de su empresa',
  'authenticated', claims(U.gerA, A.empresa, A.child, 'admin'),
  `insert into public.horarios (
     empresa_id, empleado_id, dia_semana, hora_entrada, hora_salida
   ) values ($1, $2, ${otroDia}, '07:00', '15:00')`,
  [B.empresa, U.empB], '42501');

await expectRoleError('no se repite el horario del mismo día',
  'authenticated', claims(U.gerA, A.empresa, A.child, 'admin'),
  `insert into public.horarios (
     empresa_id, empleado_id, dia_semana, hora_entrada, hora_salida
   ) values ($1, $2, ${isodowHoy}, '09:00', '18:00')`,
  [A.empresa, U.empA], '23505');

await expectRoleError('el día ISO debe estar entre 1 y 7',
  'authenticated', claims(U.gerA, A.empresa, A.child, 'admin'),
  `insert into public.horarios (
     empresa_id, empleado_id, dia_semana, hora_entrada, hora_salida
   ) values ($1, $2, 0, '09:00', '18:00')`,
  [A.empresa, U.empA], '23514');

await expectRoleError('la entrada y la salida no pueden ser iguales',
  'authenticated', claims(U.gerA, A.empresa, A.child, 'admin'),
  `insert into public.horarios (
     empresa_id, empleado_id, dia_semana, hora_entrada, hora_salida
   ) values ($1, $2, ${otroDia}, '09:00', '09:00')`,
  [A.empresa, U.empA], '23514');

await expectRoleError('la tolerancia tiene un máximo de 240 minutos',
  'authenticated', claims(U.gerA, A.empresa, A.child, 'admin'),
  `insert into public.horarios (
     empresa_id, empleado_id, dia_semana, hora_entrada, hora_salida,
     tolerancia_entrada_min
   ) values ($1, $2, ${otroDia}, '09:00', '18:00', 300)`,
  [A.empresa, U.empA], '23514');

eq('un admin activo corrige el horario de su subárbol',
  await withRole('authenticated', claims(U.gerA, A.empresa, A.child, 'admin'), async () => {
    const id = await scalar(`
      select id from public.horarios
      where empleado_id = $1
        and dia_semana = extract(isodow from (now() at time zone 'America/Guatemala'))::smallint
    `, [U.empA]);
    return (await q('update public.horarios set hora_entrada = $1 where id = $2',
      ['07:30', id])).rowCount;
  }), 1);

eq('un empleado no edita su horario',
  await withRole('authenticated', claims(U.empA, A.empresa, A.child, 'empleado'), async () =>
    (await q('update public.horarios set hora_entrada = $1', ['07:00'])).rowCount), 0);

await expectError('la zona horaria debe existir en PostgreSQL',
  'update public.empresas set zona_horaria = $1 where id = $2',
  ['No/Existe', A.empresa], '23514');

await expectError('el umbral de GPS tiene un mínimo de 10 metros',
  'update public.empresas set gps_precision_maxima_metros = 5 where id = $1',
  [A.empresa], '23514');

eq('la zona horaria por defecto es la de Guatemala',
  await scalar('select zona_horaria from public.empresas where id = $1', [A.empresa]),
  'America/Guatemala');

eq('fecha_local usa la zona de la empresa',
  await scalar(`select private.fecha_local($1, '2026-01-15T03:00:00Z'::timestamptz)::text`,
    [A.empresa]),
  '2026-01-14');

eq('horario_del_dia devuelve el horario del día ISO',
  await scalar(`
    select count(*)::int
    from private.horario_del_dia($1, (now() at time zone 'America/Guatemala')::date)
  `, [U.empA]),
  1);

// -----------------------------------------------------------------------------
// Registro propio con código de empresa
// -----------------------------------------------------------------------------
group('Registro propio con código de empresa');

eq('el código de empresa crea una solicitud pendiente',
  await withRole('authenticated', { sub: T.reg1 }, async () => {
    await q(`select public.solicitar_registro('EMPRESA-A', 'Registro Uno')`);
    return scalar(`select estado from public.registros_pendientes where usuario_id = $1`,
      [T.reg1]);
  }), 'pendiente');

await expectRoleError('un código inexistente no crea la solicitud',
  'authenticated', { sub: T.reg1 },
  `select public.solicitar_registro('NO-EXISTE', 'Registro Uno')`, [], '23503');

await expectRoleError('un usuario con perfil no se vuelve a registrar',
  'authenticated', { sub: U.empA },
  `select public.solicitar_registro('EMPRESA-A', 'Empleado A')`, [], '23514');

eq('no se acumulan dos solicitudes pendientes',
  await withRole('authenticated', { sub: T.reg1 }, async () => {
    await q(`select public.solicitar_registro('EMPRESA-A', 'Registro Uno')`);
    try {
      await q(`select public.solicitar_registro('EMPRESA-A', 'Registro Uno')`);
      return null;
    } catch (error) {
      return error.code;
    }
  }), '23505');

eq('el solicitante solo ve su propio registro',
  await withRole('authenticated', { sub: T.reg1 }, async () => {
    await q(`select public.solicitar_registro('EMPRESA-A', 'Registro Uno')`);
    return {
      propio: (await q('select count(*)::int from public.registros_pendientes')).rows[0].count,
      ajeno: await (async () => {
        await q(`select set_config('request.jwt.claims', $1, true)`,
          [JSON.stringify({ sub: T.reg2 })]);
        return (await q('select count(*)::int from public.registros_pendientes')).rows[0].count;
      })(),
    };
  }).then((r) => [r.propio, r.ajeno]), [1, 0]);

await expectRoleError('un empleado no aprueba registros',
  'authenticated', claims(U.empA, A.empresa, A.child, 'empleado'),
  'select public.aprobar_registro($1, $2, $3)',
  [randomUUID(), A.child, T.puestoOps], '42501');

await q('begin');
try {
  await q('set local role authenticated');
  await q(`select set_config('request.jwt.claims', $1, true)`,
    [JSON.stringify({ sub: T.reg1 })]);
  const registro = (await q(
    `select public.solicitar_registro('EMPRESA-A', 'Registro Uno') as id`,
  )).rows[0].id;

  await q(`select set_config('request.jwt.claims', $1, true)`,
    [JSON.stringify(claims(U.gerA, A.empresa, A.child, 'admin'))]);
  const aprobado = await scalar('select public.aprobar_registro($1, $2, $3)',
    [registro, A.grand, T.puestoOps]);

  eq('el admin aprueba el registro y devuelve la cuenta', aprobado, T.reg1);
  eq('el registro aprobado queda resuelto',
    await scalar('select estado from public.registros_pendientes where id = $1',
      [registro]), 'aprobado');
  eq('el alta siempre crea un empleado',
    await scalar(`select rol::text from public.perfiles
                  where id = $1 and centro_costo_id = $2 and puesto_id = $3`,
      [T.reg1, A.grand, T.puestoOps]), 'empleado');
  eq('los claims del alta dicen empleado',
    await (async () => {
      await q('reset role');
      return scalar(`select raw_app_meta_data ->> 'rol' from auth.users where id = $1`,
        [T.reg1]);
    })(), 'empleado');
} finally {
  await q('rollback');
}

await q('begin');
try {
  await q('set local role authenticated');
  await q(`select set_config('request.jwt.claims', $1, true)`,
    [JSON.stringify({ sub: T.regB })]);
  await q(`select public.solicitar_registro('EMPRESA-B', 'Registro B')`);
  const registroB = await scalar(
    'select id from public.registros_pendientes where usuario_id = $1', [T.regB]);

  await q(`select set_config('request.jwt.claims', $1, true)`,
    [JSON.stringify(claims(U.gerA, A.empresa, A.child, 'admin'))]);
  await q('savepoint aprobar_ajeno');
  let errorAjeno = null;
  try {
    await q('select public.aprobar_registro($1, $2, $3)',
      [registroB, A.child, T.puestoOps]);
  } catch (error) {
    errorAjeno = error;
  }
  ok('un admin no aprueba registros de otra empresa',
    errorAjeno?.code === '23503', `code=${errorAjeno?.code}`);
} finally {
  await q('rollback');
}

await q('begin');
try {
  await q('set local role authenticated');
  await q(`select set_config('request.jwt.claims', $1, true)`,
    [JSON.stringify({ sub: T.reg2 })]);
  await q(`select public.solicitar_registro('EMPRESA-A', 'Registro Dos')`);
  const registro = await scalar(
    'select id from public.registros_pendientes where usuario_id = $1', [T.reg2]);

  await q(`select set_config('request.jwt.claims', $1, true)`,
    [JSON.stringify(claims(U.gerA, A.empresa, A.child, 'admin'))]);
  await q('savepoint motivo_corto');
  let errorCorto = null;
  try {
    await q('select public.rechazar_registro($1, $2)', [registro, 'No']);
  } catch (error) {
    errorCorto = error;
  }
  ok('el rechazo exige un motivo de al menos 5 caracteres',
    errorCorto?.code === '23514', `code=${errorCorto?.code}`);

  await q('rollback to savepoint motivo_corto');
  await q('select public.rechazar_registro($1, $2)',
    [registro, 'No corresponde al centro solicitado']);
  eq('el rechazo deja el registro resuelto',
    await scalar('select estado from public.registros_pendientes where id = $1',
      [registro]), 'rechazado');

  await q(`select set_config('request.jwt.claims', $1, true)`,
    [JSON.stringify({ sub: T.reg2 })]);
  const nuevo = await scalar(
    `select public.solicitar_registro('EMPRESA-A', 'Registro Dos')::text`);
  ok('un rechazo permite volver a solicitar el alta', !!nuevo && nuevo !== registro);
} finally {
  await q('rollback');
}

await expectRoleError('el cliente no inserta registros directamente',
  'authenticated', claims(U.gerA, A.empresa, A.child, 'admin'),
  `insert into public.registros_pendientes (empresa_id, usuario_id, email, nombre_completo)
   values ($1, $2, 'x@example.com', 'Directo')`,
  [A.empresa, T.reg1], '42501');

// -----------------------------------------------------------------------------
// CECO por lugar
// -----------------------------------------------------------------------------
group('CECO por lugar');

eq('cada parque tiene exactamente un CECO principal',
  await scalar(`
    select count(*)::int from (
      select parque_id from public.parques_centros
      where principal group by parque_id having count(*) = 1
    ) x
  `), 5);

eq('el principal coincide con el centro del parque',
  await scalar(`
    select count(*)::int
    from public.parques p
    join public.parques_centros pc
      on pc.parque_id = p.id and pc.principal
    where pc.centro_costo_id <> p.centro_costo_id
  `), 0);

eq('el admin agrega un CECO adicional a un lugar de su alcance',
  await withRole('authenticated', claims(U.gerA, A.empresa, A.child, 'admin'), async () =>
    (await q(`
      insert into public.parques_centros
        (empresa_id, parque_id, centro_costo_id, principal, activo)
      values ($1, $2, $3, false, true)
    `, [A.empresa, P.child, T.cecoExtra])).rowCount), 1);

await expectRoleError('no se repite el CECO en el mismo lugar',
  'authenticated', claims(U.gerA, A.empresa, A.child, 'admin'),
  `insert into public.parques_centros
     (empresa_id, parque_id, centro_costo_id, principal, activo)
   values ($1, $2, $3, false, true)`,
  [A.empresa, P.child, A.child], '23505');

await expectRoleError('un empleado no agrega CECOs a un lugar',
  'authenticated', claims(U.empA, A.empresa, A.child, 'empleado'),
  `insert into public.parques_centros
     (empresa_id, parque_id, centro_costo_id, principal, activo)
   values ($1, $2, $3, false, true)`,
  [A.empresa, P.child, T.cecoExtra], '42501');

await expectError('un CECO de otra empresa no se habilita en el lugar',
  `insert into public.parques_centros
     (empresa_id, parque_id, centro_costo_id, principal, activo)
   values ($1, $2, $3, false, true)`,
  [A.empresa, P.child, T.cecoB], '23503');

await expectError('el principal debe coincidir con el centro del parque',
  `insert into public.parques_centros
     (empresa_id, parque_id, centro_costo_id, principal, activo)
   values ($1, $2, $3, true, true)`,
  [A.empresa, P.child, T.cecoExtra], '23514');

await expectRoleError('el CECO principal no se elimina a mano',
  'authenticated', claims(U.gerRoot, A.empresa, A.root, 'admin'),
  'delete from public.parques_centros where parque_id = $1 and principal',
  [P.child], '23514');

await expectError('el CECO principal no cambia de centro a mano',
  'update public.parques_centros set centro_costo_id = $1 where parque_id = $2 and principal',
  [T.cecoExtra, P.child], '23514');

await q('begin');
try {
  await q('update public.parques set centro_costo_id = $1 where id = $2',
    [A.grand, P.sibling]);
  eq('mover el parque desactiva el principal anterior',
    await scalar(`select count(*)::int from public.parques_centros
                  where parque_id = $1 and centro_costo_id = $2
                    and not principal and not activo`,
      [P.sibling, A.sibling]), 1);
  eq('mover el parque activa el nuevo principal',
    await scalar(`select count(*)::int from public.parques_centros
                  where parque_id = $1 and centro_costo_id = $2
                    and principal and activo`,
      [P.sibling, A.grand]), 1);
} finally {
  await q('rollback');
}

eq('el empleado ve los CECOs de los lugares de su empresa',
  await withRole('authenticated', claims(U.empA, A.empresa, A.child, 'empleado'), async () => ({
    a: (await q(`select count(*)::int from public.parques_centros
                 where empresa_id = $1`, [A.empresa])).rows[0].count,
    b: (await q(`select count(*)::int from public.parques_centros
                 where empresa_id = $1`, [B.empresa])).rows[0].count,
  })).then((r) => [r.a > 0, r.b]), [true, 0]);

eq('la solicitud guarda el lugar y el CECO habilitado',
  await withRole('authenticated', claims(U.empA, A.empresa, A.child, 'empleado'), async () =>
    (await q(`
      insert into public.solicitudes_horas_extras (
        centro_costo_id, parque_id, inicio, fin, justificacion
      ) values ($1, $2, now() + interval '300 days',
                now() + interval '300 days' + interval '2 hours', 'Apoyo en lugar')
    `, [A.child, P.child])).rowCount), 1);

await expectRoleError('la solicitud rechaza un CECO no habilitado en el lugar',
  'authenticated', claims(U.empA, A.empresa, A.child, 'empleado'),
  `insert into public.solicitudes_horas_extras (
     centro_costo_id, parque_id, inicio, fin, justificacion
   ) values ($1, $2, now() + interval '310 days',
             now() + interval '310 days' + interval '2 hours', 'Lugar inválido')`,
  [A.root, P.grand], '23514');

await expectError('la solicitud no acepta un lugar de otra empresa',
  `insert into public.solicitudes_horas_extras (
     empresa_id, empleado_id, centro_costo_id, parque_id, inicio, fin, justificacion
   ) values ($1, $2, $3, $4, now() + interval '320 days',
             now() + interval '320 days' + interval '2 hours', 'Cruce de empresa')`,
  [A.empresa, U.empA, A.child, P.b], '23514');

eq('las solicitudes históricas sin lugar siguen siendo válidas',
  await scalar(`select count(*)::int from public.solicitudes_horas_extras
                where parque_id is null`), 6);

// -----------------------------------------------------------------------------
// Incidencias y ajustes de jornada
// -----------------------------------------------------------------------------
group('Incidencias y ajustes de jornada');

eq('cerrar con retraso y salida temprana genera dos incidencias',
  (await q(`select tipo::text, minutos from public.incidencias_jornada
            where jornada_id = $1 order by tipo::text`, [T.jLate])).rows
    .map((r) => [r.tipo, r.minutos]),
  [['llegada_tarde', 75], ['salida_temprana', 30]]);

eq('un GPS con precisión mayor al umbral genera incidencia',
  (await q(`select tipo::text from public.incidencias_jornada
            where jornada_id = $1`, [T.jGps])).rows.map((r) => r.tipo),
  ['gps_impreciso']);

eq('marcar en un parque de otro centro genera incidencia',
  (await q(`select tipo::text from public.incidencias_jornada
            where jornada_id = $1`, [T.jPark])).rows.map((r) => r.tipo),
  ['parque_distinto']);

eq('el empleado ve sus propias incidencias',
  await withRole('authenticated', claims(U.empA, A.empresa, A.child, 'empleado'), async () => ({
    propias: (await q('select count(*)::int from public.incidencias_jornada')).rows[0].count,
    ajenas: (await q(`select count(*)::int from public.incidencias_jornada
                      where empleado_id <> $1`, [U.empA])).rows[0].count,
  })).then((r) => [r.propias > 0, r.ajenas]), [true, 0]);

eq('el empleado de otra empresa no ve las incidencias ajenas',
  await withRole('authenticated', claims(U.empB, B.empresa, B.root, 'empleado'), async () =>
    (await q('select count(*)::int from public.incidencias_jornada')).rows[0].count), 0);

eq('el admin ve las incidencias de su subárbol y no las de otra empresa',
  await withRole('authenticated', claims(U.gerA, A.empresa, A.child, 'admin'), async () => ({
    propias: (await q('select count(*)::int from public.incidencias_jornada')).rows[0].count,
    ajenas: (await q(`select count(*)::int from public.incidencias_jornada
                      where empleado_id = $1`, [U.empB])).rows[0].count,
  })).then((r) => [r.propias > 0, r.ajenas]), [true, 0]);

await expectRoleError('el cliente no inserta incidencias',
  'authenticated', claims(U.empA, A.empresa, A.child, 'empleado'),
  `insert into public.incidencias_jornada
     (empresa_id, jornada_id, empleado_id, tipo)
   values ($1, $2, $3, 'llegada_tarde')`,
  [A.empresa, T.jLate, U.empA], '42501');

await expectRoleError('el cliente no inserta ajustes de jornada',
  'authenticated', claims(U.gerA, A.empresa, A.child, 'admin'),
  `insert into public.jornadas_ajustes (
     empresa_id, jornada_id, empleado_id, ajustado_por, motivo,
     entrada_en_anterior, salida_en_anterior, entrada_en_nueva, salida_en_nueva
   ) values ($1, $2, $3, $4, 'Intento directo', now(), now(),
             now(), now() + interval '1 hour')`,
  [A.empresa, T.jLate, U.empA, U.gerA], '42501');

await expectError('el historial de ajustes no se edita',
  `update public.jornadas_ajustes set motivo = 'Otro motivo' where id = $1`,
  [T.ajuste], '23514');

await expectError('el historial de ajustes no se borra',
  'delete from public.jornadas_ajustes where id = $1', [T.ajuste], '23514');

eq('el empleado ve los ajustes de sus jornadas',
  await withRole('authenticated', claims(U.empA, A.empresa, A.child, 'empleado'), async () =>
    (await q('select count(*)::int from public.jornadas_ajustes where jornada_id = $1',
      [J.aCerrada])).rows[0].count), 1);

await expectRoleError('un empleado no ajusta jornadas',
  'authenticated', claims(U.empA, A.empresa, A.child, 'empleado'),
  'select public.ajustar_jornada($1, $2, $3, $4)',
  [T.jAdjust, new Date(Date.now() - 9 * 3600e3), new Date(Date.now() - 1 * 3600e3),
    'Corrección solicitada por el empleado'], '42501');

await expectRoleError('el ajuste exige un motivo suficiente',
  'authenticated', claims(U.gerA, A.empresa, A.child, 'admin'),
  'select public.ajustar_jornada($1, $2, $3, $4)',
  [T.jAdjust, new Date(Date.now() - 9 * 3600e3), new Date(Date.now() - 1 * 3600e3),
    'Corto'], '23514');

await expectRoleError('el ajuste exige un rango coherente',
  'authenticated', claims(U.gerA, A.empresa, A.child, 'admin'),
  'select public.ajustar_jornada($1, $2, $3, $4)',
  [T.jAdjust, new Date(Date.now() - 1 * 3600e3), new Date(Date.now() - 9 * 3600e3),
    'Rango de prueba inválido'], '23514');

await expectRoleError('una jornada abierta no se ajusta',
  'authenticated', claims(U.gerRoot, A.empresa, A.root, 'admin'),
  'select public.ajustar_jornada($1, $2, $3, $4)',
  [J.grandAbierta, new Date(Date.now() - 9 * 3600e3), new Date(Date.now() - 1 * 3600e3),
    'Jornada todavía abierta'], '23514');

await expectRoleError('no se ajusta una jornada de otra empresa',
  'authenticated', claims(U.gerRoot, A.empresa, A.root, 'admin'),
  'select public.ajustar_jornada($1, $2, $3, $4)',
  [J.bCerrada, new Date(Date.now() - 9 * 3600e3), new Date(Date.now() - 1 * 3600e3),
    'Jornada de otra empresa'], '23503');

await q('begin');
try {
  await q('set local role authenticated');
  await q(`select set_config('request.jwt.claims', $1, true)`,
    [JSON.stringify(claims(U.gerA, A.empresa, A.child, 'admin'))]);

  const original = (await q(
    'select entrada_en, salida_en from public.jornadas where id = $1',
    [T.jAdjust])).rows[0];
  const entrada = await scalar(
    `select ${localHora('08:00')}`
  );
  const salida = await scalar(
    `select ${localHora('17:00')}`
  );
  const ajuste = await scalar(
    'select public.ajustar_jornada($1, $2, $3, $4)::text',
    [T.jAdjust, entrada, salida, 'Corrección de horario autorizada']);

  ok('el admin ajusta una jornada cerrada', !!ajuste);
  eq('el ajuste conserva los tiempos anteriores y los nuevos',
    (await q(`select entrada_en_anterior = $1::timestamptz as antes,
                     salida_en_anterior = $2::timestamptz as salida_antes,
                     entrada_en_nueva = $3::timestamptz as despues,
                     salida_en_nueva = $4::timestamptz as salida
              from public.jornadas_ajustes where id = $5`,
      [original.entrada_en, original.salida_en, entrada, salida, ajuste])).rows[0],
    { antes: true, salida_antes: true, despues: true, salida: true });
  eq('el ajuste actualiza la jornada',
    (await q(`select entrada_en = $1::timestamptz as entrada,
                     salida_en = $2::timestamptz as salida
              from public.jornadas where id = $3`,
      [entrada, salida, T.jAdjust])).rows[0],
    { entrada: true, salida: true });
  eq('el ajuste recalcula y limpia las incidencias',
    await scalar('select count(*)::int from public.incidencias_jornada where jornada_id = $1',
      [T.jAdjust]),
    0);
} finally {
  await q('rollback');
}

// -----------------------------------------------------------------------------
// Reportes
// -----------------------------------------------------------------------------
group('Reportes');

eq('las vistas de reporte heredan la RLS del consultante',
  await scalar(`
    select count(*)::int from pg_class
    where relname in ('reporte_horas_extras', 'cumplimiento_jornadas')
      and coalesce(reloptions, '{}') @> array['security_invoker=true']
  `), 2);

eq('el empleado solo ve sus horas extras en el reporte',
  await withRole('authenticated', claims(U.empA, A.empresa, A.child, 'empleado'), async () => ({
    propias: (await q(`select count(*)::int from public.reporte_horas_extras
                       where empleado_id = $1`, [U.empA])).rows[0].count,
    ajenas: (await q(`select count(*)::int from public.reporte_horas_extras
                      where empleado_id <> $1`, [U.empA])).rows[0].count,
  })).then((r) => [r.propias > 0, r.ajenas]), [true, 0]);

eq('el admin ve el reporte de su subárbol y no el de otra empresa',
  await withRole('authenticated', claims(U.gerA, A.empresa, A.child, 'admin'), async () => ({
    propias: (await q('select count(*)::int from public.reporte_horas_extras')).rows[0].count,
    ajenas: (await q(`select count(*)::int from public.reporte_horas_extras
                      where empleado_id = $1`, [U.empB])).rows[0].count,
  })).then((r) => [r.propias > 0, r.ajenas]), [true, 0]);

eq('el reporte calcula las horas del rango',
  await (async () => {
    await q('begin');
    try {
      const id = randomUUID();
      await q(`
        insert into public.solicitudes_horas_extras (
          id, empresa_id, empleado_id, centro_costo_id, inicio, fin, justificacion
        ) values ($1, $2, $3, $4, now() + interval '400 days',
                  now() + interval '400 days' + interval '2 hours', 'Reporte de horas')
      `, [id, A.empresa, U.empA, A.child]);
      await q('set local role authenticated');
      await q(`select set_config('request.jwt.claims', $1, true)`,
        [JSON.stringify(claims(U.empA, A.empresa, A.child, 'empleado'))]);
      return await scalar('select horas::float8 from public.reporte_horas_extras where id = $1', [id]);
    } finally {
      await q('rollback');
    }
  })(), 2);

eq('el reporte de cumplimiento cruza horario e incidencias',
  await withRole('authenticated', claims(U.empA, A.empresa, A.child, 'empleado'), async () => {
    const fila = (await q(`
      select minutos_tarde, minutos_temprano, incidencias,
             entrada_programada is not null as programada
      from public.cumplimiento_jornadas where id = $1
    `, [T.jLate])).rows[0];
    return [fila.minutos_tarde, fila.minutos_temprano, fila.incidencias, fila.programada];
  }), [75, 30, ['llegada_tarde', 'salida_temprana'], true]);

eq('el reporte marca la jornada abierta',
  await withRole('authenticated', claims(U.gerA, A.empresa, A.child, 'admin'), async () => {
    const fila = (await q(`
      select abierta, salida_en, horas >= 0 as horas_ok
      from public.cumplimiento_jornadas where id = $1
    `, [J.grandAbierta])).rows[0];
    return [fila.abierta, fila.salida_en, fila.horas_ok];
  }), [true, null, true]);

// -----------------------------------------------------------------------------
// Importación de centros de costo (tools/importar-ceco)
// -----------------------------------------------------------------------------
group('Importación de centros de costo');

const csvCentros = [
  'codigo,nombre,padre',
  'IMP100,Parque Importado,',
  'IMP110,Operaciones Importadas,IMP100',
  'IMP120,Mantenimiento Importado,IMP110',
].join('\n');
const planImport = construirPlan(parsearCsv(csvCentros).filas);

eq('el plan del CSV no tiene errores ni advertencias',
  [planImport.errores, planImport.advertencias], [[], []]);

await q(generarSql({ empresa: 'EMPRESA-A', nodos: planImport.nodos }));

eq('la importación crea los tres centros',
  await scalar(`
    select count(*)::int
    from public.centros_costo c
    join public.empresas e on e.id = c.empresa_id
    where e.codigo = 'EMPRESA-A'
      and c.codigo in ('IMP100', 'IMP110', 'IMP120')
  `), 3);

eq('la importación arma la jerarquía',
  await scalar(`
    select count(*)::int
    from public.centros_costo c
    join public.empresas e on e.id = c.empresa_id
    join public.centros_costo p on p.id = c.padre_id
    where e.codigo = 'EMPRESA-A'
      and (c.codigo, p.codigo) in (('IMP110', 'IMP100'), ('IMP120', 'IMP110'))
  `), 2);

await q(generarSql({ empresa: 'EMPRESA-A', nodos: planImport.nodos }));
eq('repetir la importación no duplica centros',
  await scalar(`
    select count(*)::int
    from public.centros_costo c
    join public.empresas e on e.id = c.empresa_id
    where e.codigo = 'EMPRESA-A'
      and c.codigo like 'IMP%'
  `), 3);

const planRenombrado = construirPlan([
  { linea: 2, codigo: 'IMP100', nombre: 'Parque Importado', padre: '' },
  { linea: 3, codigo: 'IMP110', nombre: 'Operaciones Renombradas', padre: 'IMP100' },
  { linea: 4, codigo: 'IMP120', nombre: 'Mantenimiento Importado', padre: 'IMP110' },
]);
await q(generarSql({ empresa: 'EMPRESA-A', nodos: planRenombrado.nodos }));
eq('repetir la importación actualiza el nombre',
  await scalar(`
    select c.nombre::text
    from public.centros_costo c
    join public.empresas e on e.id = c.empresa_id
    where e.codigo = 'EMPRESA-A' and c.codigo = 'IMP110'
  `), 'Operaciones Renombradas');

const planHuerfano = construirPlan([
  { linea: 2, codigo: 'IMP900', nombre: 'Huérfano', padre: 'NOEXISTE' },
]);
let errorImport = null;
try {
  await q(generarSql({
    empresa: 'EMPRESA-A',
    nodos: planHuerfano.nodos,
    advertencias: planHuerfano.advertencias,
  }));
} catch (error) {
  errorImport = error;
}
if (errorImport) await q('rollback');

ok('la importación se aborta si el padre no existe',
  /Padres no encontrados/.test(errorImport?.message ?? ''),
  `message=${errorImport?.message}`);
eq('el centro huérfano no queda creado',
  await scalar(`select count(*)::int from public.centros_costo where codigo = 'IMP900'`), 0);

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

for (const vista of ['reporte_horas_extras', 'cumplimiento_jornadas']) {
  await expectRoleError(`anon sin acceso a ${vista}`, 'anon', {},
    `select count(*) from public.${vista}`, [], '42501');
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
