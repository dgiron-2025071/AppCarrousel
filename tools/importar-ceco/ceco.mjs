// Normaliza el catálogo de centros de costo (CECO) y arma su jerarquía.
//
// En caja chica el mismo hijo aparece escrito de tres formas: 057.01, 057-01
// y 05701. Todas son el hijo 01 del CECO 057. Aquí se unifican como 057.01.

const PADRE_HIJO_SEPARADO = /^(\d{3})[.-](\d+)$/;
const PADRE_HIJO_PEGADO = /^(\d{3})(\d{2})$/;

/** Devuelve { codigo, padre } con el código canónico, o null si viene vacío. */
export function normalizarCodigo(valor) {
  const crudo = String(valor ?? '').trim();
  if (!crudo || crudo.toUpperCase() === 'NULL') return null;

  const separado = crudo.match(PADRE_HIJO_SEPARADO);
  if (separado) return { codigo: `${separado[1]}.${separado[2]}`, padre: separado[1] };

  const pegado = crudo.match(PADRE_HIJO_PEGADO);
  if (pegado) return { codigo: `${pegado[1]}.${pegado[2]}`, padre: pegado[1] };

  return { codigo: crudo, padre: null };
}

/** Quita espacios dobles y un sufijo "(código)" que repite el CECO. */
export function limpiarNombre(nombre, codigoOriginal) {
  let limpio = String(nombre ?? '').replace(/\s+/g, ' ').trim();
  const sufijo = limpio.match(/^(.*?)\s*\(([^)]*)\)$/);
  if (sufijo && codigoOriginal && normalizarCodigo(sufijo[2])?.codigo === normalizarCodigo(codigoOriginal)?.codigo) {
    limpio = sufijo[1].trim();
  }
  return limpio;
}

// Entre dos nombres para el mismo código se prefiere el que no es genérico
// ("Otro...") y el que no traía el código entre paréntesis.
function puntaje(fila) {
  let valor = 0;
  if (/^otro/i.test(fila.nombre)) valor += 2;
  if (fila.nombreOriginal !== fila.nombre) valor += 1;
  return valor;
}

const ES_PRUEBA = /prueba/i;

// Palabras que indican el tipo de sub-centro y no forman parte del parque.
const TIPOS = /\b(kiddies|cajas?|magicas?|magic|cm|caseta|juegos|eventos)\b/gi;

/** Nombre del parque a partir de los nombres de sus sub-centros. */
export function nombrePadre(nombres) {
  const limpios = nombres.map((n) => n.replace(TIPOS, ' ').replace(/\s+/g, ' ').trim());
  const palabras = limpios.map((n) => n.split(' '));
  const comun = [];
  for (let i = 0; i < Math.min(...palabras.map((p) => p.length)); i++) {
    // Tolera plurales mal escritos ("Encuentro" / "Encuentros"): se queda
    // con la forma más larga si una es prefijo de la otra.
    const formas = palabras.map((p) => p[i]);
    const larga = formas.reduce((a, b) => (b.length > a.length ? b : a));
    if (!formas.every((f) => larga.toLowerCase().startsWith(f.toLowerCase()) && larga.length - f.length <= 1)) break;
    comun.push(larga);
  }
  return comun.join(' ') || limpios.sort((a, b) => a.length - b.length)[0] || '';
}

/**
 * Convierte filas { codigo, nombre } en centros listos para insertar.
 *
 * Devuelve:
 * - centros: [{ codigo, nombre, padre }] ordenados para que cada padre se
 *   inserte antes que sus hijos. padre es null para los de primer nivel.
 * - conflictos: códigos repetidos con nombres distintos (se conservó uno).
 * - sinPadre: parques principales creados porque solo venían sus sub-centros.
 * - descartadas: filas sin código o de prueba.
 */
export function construirJerarquia(filas) {
  const porCodigo = new Map();
  const conflictos = [];
  const descartadas = [];

  for (const fila of filas) {
    const normal = normalizarCodigo(fila.codigo);
    if (!normal) {
      descartadas.push(fila);
      continue;
    }
    const candidato = {
      codigo: normal.codigo,
      padre: normal.padre,
      nombre: limpiarNombre(fila.nombre, fila.codigo),
      nombreOriginal: String(fila.nombre ?? '').replace(/\s+/g, ' ').trim(),
    };
    if (!candidato.nombre) candidato.nombre = normal.codigo;

    const actual = porCodigo.get(normal.codigo);
    if (!actual) {
      porCodigo.set(normal.codigo, candidato);
      continue;
    }
    if (actual.nombre.toLowerCase() !== candidato.nombre.toLowerCase()) {
      const elegido = puntaje(candidato) < puntaje(actual) ? candidato : actual;
      const descartado = elegido === actual ? candidato : actual;
      conflictos.push({ codigo: normal.codigo, conservado: elegido.nombre, descartado: descartado.nombre });
      porCodigo.set(normal.codigo, elegido);
    }
  }

  // Registros de prueba que no son centros de costo reales.
  for (const [codigo, centro] of porCodigo) {
    if (ES_PRUEBA.test(centro.nombre) || /^0+(\.|$)/.test(codigo)) {
      descartadas.push({ codigo, nombre: centro.nombre });
      porCodigo.delete(codigo);
    }
  }

  // Si falta el parque principal (ej. 060), se crea con el nombre común de
  // sus hijos ("Cinestar Kiddies" + "Cinestar Cajas Magicas" → "Cinestar").
  // Así cada parque aparece una sola vez en el primer nivel.
  const huerfanos = new Map();
  for (const centro of porCodigo.values()) {
    if (centro.padre && !porCodigo.has(centro.padre)) {
      if (!huerfanos.has(centro.padre)) huerfanos.set(centro.padre, []);
      huerfanos.get(centro.padre).push(centro.nombre);
    }
  }
  const sinPadre = [];
  for (const [codigo, nombres] of huerfanos) {
    const nombre = nombrePadre(nombres) || codigo;
    porCodigo.set(codigo, { codigo, nombre, padre: null });
    sinPadre.push({ codigo, nombre, hijos: nombres.length });
  }

  const ordenar = (a, b) => a.codigo.localeCompare(b.codigo, 'es', { numeric: true });
  const primerNivel = [...porCodigo.values()].filter((c) => !c.padre).sort(ordenar);
  const hijos = [...porCodigo.values()].filter((c) => c.padre).sort(ordenar);

  const centros = [...primerNivel, ...hijos].map(({ codigo, nombre, padre }) => ({ codigo, nombre, padre }));
  return { centros, conflictos, sinPadre, descartadas };
}

/** Lee TSV (exportación de MySQL) o CSV simple con encabezado codigo,nombre. */
export function leerListado(texto) {
  const lineas = texto.replace(/^\uFEFF/, '').split(/\r?\n/).filter((l) => l.trim());
  if (lineas.length === 0) return [];
  const separador = lineas[0].includes('\t') ? '\t' : ',';
  const encabezado = lineas[0].split(separador).map((c) => c.trim().toLowerCase());
  const iCodigo = encabezado.indexOf('codigo');
  const iNombre = encabezado.indexOf('nombre');
  if (iCodigo < 0 || iNombre < 0) {
    throw new Error('El listado debe tener las columnas "codigo" y "nombre".');
  }
  return lineas.slice(1).map((linea) => {
    const columnas = linea.split(separador);
    return { codigo: columnas[iCodigo], nombre: columnas[iNombre] };
  });
}

const sql = (texto) => `'${String(texto).replace(/'/g, "''")}'`;

/**
 * SQL idempotente: crea la raíz si falta y hace upsert de cada CECO bajo su
 * padre. Re-ejecutarlo actualiza nombres y padres sin duplicar centros.
 */
export function generarSql({ centros, empresaCodigo, raizCodigo, raizNombre }) {
  const partes = [
    '-- Generado por tools/importar-ceco. No editar a mano.',
    'begin;',
    `insert into public.centros_costo (empresa_id, padre_id, codigo, nombre)
select e.id, null, ${sql(raizCodigo)}, ${sql(raizNombre)}
from public.empresas e
where e.codigo = ${sql(empresaCodigo)}
on conflict (empresa_id, codigo) do nothing;`,
  ];

  for (const centro of centros) {
    const padre = centro.padre ?? raizCodigo;
    partes.push(`insert into public.centros_costo (empresa_id, padre_id, codigo, nombre)
select e.id, p.id, ${sql(centro.codigo)}, ${sql(centro.nombre)}
from public.empresas e
join public.centros_costo p on p.empresa_id = e.id and p.codigo = ${sql(padre)}
where e.codigo = ${sql(empresaCodigo)}
on conflict (empresa_id, codigo) do update
  set nombre = excluded.nombre,
      padre_id = excluded.padre_id;`);
  }

  partes.push('commit;');
  return `${partes.join('\n\n')}\n`;
}
