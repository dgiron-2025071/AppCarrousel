/**
 * Normalización y planificación de la importación de centros de costo.
 *
 * El código canónico es alfanumérico en mayúsculas, sin separadores. Así
 * `057.01`, `057-01`, `057 01` y `05701` son el mismo centro y la importación
 * puede repetirse sin duplicarlos. Los ceros a la izquierda se conservan porque
 * forman parte del código de negocio.
 */

const SEPARADORES = /[\s._/\\-]+/g;
const LARGO_MAXIMO = 32;

export function normalizarCodigo(valor) {
  if (typeof valor !== 'string') {
    throw new Error('El código debe ser texto');
  }

  const limpio = valor.trim().toUpperCase().replace(SEPARADORES, '');

  if (limpio.length === 0) {
    throw new Error('El código no puede estar vacío');
  }
  if (limpio.length > LARGO_MAXIMO) {
    throw new Error(`El código "${valor}" supera ${LARGO_MAXIMO} caracteres`);
  }
  if (!/^[A-Z0-9]+$/.test(limpio)) {
    throw new Error(`El código "${valor}" contiene caracteres no permitidos`);
  }

  return limpio;
}

export function normalizarNombre(valor) {
  const limpio = String(valor ?? '').replace(/\s+/g, ' ').trim();

  if (limpio.length === 0) {
    throw new Error('El nombre no puede estar vacío');
  }
  if (limpio.length > 160) {
    throw new Error(`El nombre "${limpio}" supera 160 caracteres`);
  }

  return limpio;
}

/**
 * Convierte las filas crudas del CSV en un plan. Devuelve errores (bloquean la
 * importación) y advertencias (padres que no vienen en el archivo y pueden
 * existir ya en la base).
 */
export function construirPlan(filas) {
  const errores = [];
  const advertencias = [];
  const nodos = [];
  const porCodigo = new Map();

  for (const fila of filas) {
    let codigo;
    let padre = null;

    try {
      codigo = normalizarCodigo(fila.codigo);
    } catch (error) {
      errores.push(`Línea ${fila.linea}: ${error.message}`);
      continue;
    }

    let nombre;
    try {
      nombre = normalizarNombre(fila.nombre);
    } catch (error) {
      errores.push(`Línea ${fila.linea}: ${error.message}`);
      continue;
    }

    if (fila.padre !== null && fila.padre !== undefined && String(fila.padre).trim() !== '') {
      try {
        padre = normalizarCodigo(fila.padre);
      } catch (error) {
        errores.push(`Línea ${fila.linea}: padre inválido: ${error.message}`);
        continue;
      }
    }

    if (padre === codigo) {
      errores.push(`Línea ${fila.linea}: el centro ${codigo} no puede ser su propio padre`);
      continue;
    }

    if (porCodigo.has(codigo)) {
      errores.push(
        `Línea ${fila.linea}: el código ${codigo} ya apareció en la línea ${porCodigo.get(codigo).linea}`,
      );
      continue;
    }

    const nodo = { codigo, nombre, padre, linea: fila.linea };
    porCodigo.set(codigo, nodo);
    nodos.push(nodo);
  }

  for (const nodo of nodos) {
    if (nodo.padre !== null && !porCodigo.has(nodo.padre)) {
      advertencias.push(
        `Línea ${nodo.linea}: el padre ${nodo.padre} no viene en el archivo; debe existir en la base`,
      );
    }
  }

  const ciclos = detectarCiclos(nodos);
  for (const ciclo of ciclos) {
    errores.push(`Ciclo de centros de costo: ${ciclo.join(' → ')}`);
  }

  return { nodos, errores, advertencias };
}

function detectarCiclos(nodos) {
  const porCodigo = new Map(nodos.map((nodo) => [nodo.codigo, nodo]));
  const ciclos = [];
  const visitados = new Set();

  for (const nodo of nodos) {
    if (visitados.has(nodo.codigo)) continue;

    const camino = [];
    const enCamino = new Set();
    let actual = nodo;

    while (actual) {
      if (enCamino.has(actual.codigo)) {
        const inicio = camino.indexOf(actual.codigo);
        ciclos.push([...camino.slice(inicio), actual.codigo]);
        break;
      }
      if (visitados.has(actual.codigo)) break;

      camino.push(actual.codigo);
      enCamino.add(actual.codigo);
      visitados.add(actual.codigo);
      actual = actual.padre ? porCodigo.get(actual.padre) : null;
    }
  }

  return ciclos;
}

function comilla(valor) {
  return `'${String(valor).replaceAll("'", "''")}'`;
}

/**
 * Genera SQL idempotente para una empresa. Se ejecuta con `service_role` porque
 * mover centros y crear raíces está reservado a ese rol. El bloque valida la
 * empresa y los padres antes de enlazar, para no dejar una jerarquía a medias.
 */
export function generarSql({ empresa, nodos, advertencias = [] }) {
  const codigoEmpresa = String(empresa ?? '').trim();
  if (!codigoEmpresa) {
    throw new Error('Falta el código de empresa');
  }
  if (!Array.isArray(nodos) || nodos.length === 0) {
    throw new Error('No hay centros de costo para importar');
  }

  const valoresAltas = nodos
    .map((nodo) => `    (${comilla(nodo.codigo)}, ${comilla(nodo.nombre)})`)
    .join(',\n');

  const conPadre = nodos.filter((nodo) => nodo.padre !== null);
  const valoresPadres = conPadre
    .map((nodo) => `    (${comilla(nodo.codigo)}, ${comilla(nodo.padre)})`)
    .join(',\n');

  const raices = nodos
    .filter((nodo) => nodo.padre === null)
    .map((nodo) => comilla(nodo.codigo))
    .join(', ');

  const lineas = [
    '-- Generado por tools/importar-ceco.',
    `-- Empresa: ${codigoEmpresa}`,
    '-- Ejecutar con service_role: crea raíces y mueve centros de costo.',
    '-- La importación es idempotente: se puede repetir sin duplicar filas.',
    '',
  ];

  for (const advertencia of advertencias) {
    lineas.push(`-- ADVERTENCIA: ${String(advertencia).replaceAll(/\s+/g, ' ')}`);
  }
  if (advertencias.length > 0) {
    lineas.push('');
  }

  lineas.push(
    'begin;',
    '',
    '-- 1. La empresa debe existir.',
    'do $$',
    'begin',
    '  if not exists (',
    `    select 1 from public.empresas where codigo = ${comilla(codigoEmpresa)}`,
    '  ) then',
    `    raise exception 'La empresa % no existe', ${comilla(codigoEmpresa)};`,
    '  end if;',
    'end',
    '$$;',
    '',
    '-- 2. Alta o renombrado idempotente de los centros.',
    'with empresa as (',
    `  select id from public.empresas where codigo = ${comilla(codigoEmpresa)}`,
    '), datos (codigo, nombre) as (',
    '  values',
    valoresAltas,
    ')',
    'insert into public.centros_costo (empresa_id, codigo, nombre)',
    'select e.id, d.codigo, d.nombre',
    'from datos d',
    'cross join empresa e',
    'on conflict (empresa_id, codigo) do update',
    '  set nombre = excluded.nombre',
    '  where public.centros_costo.nombre is distinct from excluded.nombre;',
    '',
  );

  if (conPadre.length > 0) {
    lineas.push(
      '-- 3. Todos los padres deben existir antes de enlazar.',
      'do $$',
      'declare',
      '  v_faltantes text;',
      'begin',
      '  select string_agg(distinct d.padre_codigo, \', \')',
      '    into v_faltantes',
      '  from (values',
      valoresPadres,
      '  ) as d (codigo, padre_codigo)',
      '  where not exists (',
      '    select 1',
      '    from public.centros_costo c',
      '    join public.empresas e on e.id = c.empresa_id',
      `    where e.codigo = ${comilla(codigoEmpresa)}`,
      '      and c.codigo = d.padre_codigo',
      '  );',
      '',
      '  if v_faltantes is not null then',
      `    raise exception 'Padres no encontrados en la empresa %: %', ${comilla(codigoEmpresa)}, v_faltantes;`,
      '  end if;',
      'end',
      '$$;',
      '',
      '-- 4. Enlace de cada centro con su padre.',
      'with empresa as (',
      `  select id from public.empresas where codigo = ${comilla(codigoEmpresa)}`,
      '), datos (codigo, padre_codigo) as (',
      '  values',
      valoresPadres,
      ')',
      'update public.centros_costo c',
      '   set padre_id = p.id',
      '  from datos d',
      '  join empresa e on true',
      '  join public.centros_costo p',
      '    on p.empresa_id = e.id',
      '   and p.codigo = d.padre_codigo',
      ' where c.empresa_id = e.id',
      '   and c.codigo = d.codigo',
      '   and c.padre_id is distinct from p.id;',
      '',
    );
  }

  if (raices.length > 0) {
    lineas.push(
      '-- 5. Los centros sin padre declarado quedan como raíz.',
      'with empresa as (',
      `  select id from public.empresas where codigo = ${comilla(codigoEmpresa)}`,
      ')',
      'update public.centros_costo c',
      '   set padre_id = null',
      '  from empresa e',
      ' where c.empresa_id = e.id',
      `   and c.codigo in (${raices})`,
      '   and c.padre_id is not null;',
      '',
    );
  }

  lineas.push('commit;', '');
  return `${lineas.join('\n')}\n`;
}
