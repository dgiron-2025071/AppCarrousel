/**
 * Parser CSV mínimo y sin dependencias para la importación de centros de costo.
 *
 * Acepta coma, punto y coma o tabulador como delimitador, campos entre comillas
 * con comillas dobles escapadas (`""`), saltos de línea dentro de un campo,
 * BOM de Excel, CRLF y líneas de comentario que empiezan con `#`.
 *
 * Devuelve las filas ya mapeadas a `codigo`, `nombre` y `padre`, conservando la
 * línea física del archivo para que los errores sean accionables.
 */

const ALIAS = {
  codigo: ['codigo', 'code', 'ceco', 'centro', 'centro_costo', 'centro_de_costo'],
  nombre: ['nombre', 'name', 'descripcion', 'nombre_centro', 'nombre_del_centro'],
  padre: ['padre', 'padre_codigo', 'parent', 'parent_code', 'ceco_padre'],
};

const DELIMITADORES = [',', ';', '\t'];

export function normalizarEncabezado(valor) {
  return String(valor ?? '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

function detectarDelimitador(texto) {
  const primeraLinea = texto
    .split(/\r?\n/)
    .find((linea) => linea.trim() !== '' && !linea.trimStart().startsWith('#'));

  if (!primeraLinea) return ',';

  let mejor = ',';
  let mejorCuenta = -1;

  for (const delimitador of DELIMITADORES) {
    let cuenta = 0;
    let enComillas = false;

    for (let i = 0; i < primeraLinea.length; i++) {
      const caracter = primeraLinea[i];
      if (caracter === '"') {
        if (enComillas && primeraLinea[i + 1] === '"') {
          i++;
        } else {
          enComillas = !enComillas;
        }
      } else if (!enComillas && caracter === delimitador) {
        cuenta++;
      }
    }

    if (cuenta > mejorCuenta) {
      mejor = delimitador;
      mejorCuenta = cuenta;
    }
  }

  return mejor;
}

/** Devuelve registros crudos: `{ campos, linea }` con la línea inicial. */
export function leerRegistros(texto, { delimitador } = {}) {
  const limpio = String(texto ?? '').replace(/^\uFEFF/, '');
  const separador = delimitador ?? detectarDelimitador(limpio);

  if (!DELIMITADORES.includes(separador)) {
    throw new Error(`Delimitador no soportado: ${JSON.stringify(separador)}`);
  }

  const registros = [];
  let campos = [];
  let campo = '';
  let enComillas = false;
  let comentario = false;
  let alInicio = true;
  let linea = 1;
  let lineaRegistro = 1;

  const cerrarRegistro = () => {
    campos.push(campo);
    registros.push({ campos, linea: lineaRegistro });
    campos = [];
    campo = '';
  };

  for (let i = 0; i < limpio.length; i++) {
    const caracter = limpio[i];

    if (comentario) {
      if (caracter === '\n') {
        comentario = false;
        alInicio = true;
        linea++;
        lineaRegistro = linea;
      }
      continue;
    }

    if (enComillas) {
      if (caracter === '"') {
        if (limpio[i + 1] === '"') {
          campo += '"';
          i++;
        } else {
          enComillas = false;
        }
      } else if (caracter === '\n') {
        campo += '\n';
        linea++;
      } else if (caracter !== '\r') {
        campo += caracter;
      }
      continue;
    }

    if (caracter === '"' && campo === '') {
      enComillas = true;
      alInicio = false;
      continue;
    }

    if (caracter === separador) {
      campos.push(campo);
      campo = '';
      alInicio = false;
      continue;
    }

    if (caracter === '\n') {
      cerrarRegistro();
      linea++;
      lineaRegistro = linea;
      alInicio = true;
      continue;
    }

    if (caracter === '\r') {
      continue;
    }

    if (alInicio && caracter === '#') {
      comentario = true;
      continue;
    }

    campo += caracter;
    alInicio = false;
  }

  if (enComillas) {
    throw new Error(`El archivo tiene comillas sin cerrar cerca de la línea ${lineaRegistro}`);
  }

  if (campo !== '' || campos.length > 0) {
    cerrarRegistro();
  }

  return registros;
}

function resolverIndices(encabezados) {
  const indices = {};

  for (const [clave, alias] of Object.entries(ALIAS)) {
    const indice = encabezados.findIndex((encabezado) => alias.includes(encabezado));
    if (indice !== -1) indices[clave] = indice;
  }

  return indices;
}

/**
 * Parsea el CSV completo y devuelve `{ encabezados, filas }`. Las filas vacías
 * se descartan y cada fila conserva su número de línea físico.
 */
export function parsearCsv(texto, opciones = {}) {
  const registros = leerRegistros(texto, opciones).filter(
    (registro) => registro.campos.some((valor) => String(valor).trim() !== ''),
  );

  if (registros.length === 0) {
    throw new Error('El CSV está vacío');
  }

  const encabezados = registros[0].campos.map(normalizarEncabezado);
  const indices = resolverIndices(encabezados);

  const faltantes = ['codigo', 'nombre'].filter((clave) => indices[clave] === undefined);
  if (faltantes.length > 0) {
    throw new Error(
      `Faltan columnas obligatorias: ${faltantes.join(', ')}. ` +
        `Encabezados encontrados: ${encabezados.join(', ') || '(ninguno)'}`,
    );
  }

  const filas = [];

  for (const registro of registros.slice(1)) {
    if (registro.campos.every((valor) => String(valor).trim() === '')) continue;

    const valor = (clave) => {
      const indice = indices[clave];
      return indice === undefined ? '' : String(registro.campos[indice] ?? '').trim();
    };

    filas.push({
      linea: registro.linea,
      codigo: valor('codigo'),
      nombre: valor('nombre'),
      padre: valor('padre'),
    });
  }

  return { encabezados, filas };
}
