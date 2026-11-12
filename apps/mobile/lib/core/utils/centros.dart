import '../../data/models/centro_costo.dart';

/// Centros del subárbol cuya raíz es [raizId], incluida la propia raíz.
///
/// Se calcula con `padre_id` porque el catálogo visible por RLS abarca toda la
/// empresa. Así el selector del administrador coincide con la validación de la
/// Edge Function `invitar-usuario`.
List<CentroCosto> subarbolDe(List<CentroCosto> centros, String raizId) {
  final hijos = <String?, List<CentroCosto>>{};
  for (final centro in centros) {
    hijos.putIfAbsent(centro.padreId, () => []).add(centro);
  }

  final resultado = <CentroCosto>[];
  final pendientes = <String>[raizId];
  final vistos = <String>{};

  while (pendientes.isNotEmpty) {
    final actual = pendientes.removeLast();
    if (!vistos.add(actual)) continue;
    final propios = hijos[actual] ?? const <CentroCosto>[];
    for (final centro in propios) {
      if (vistos.contains(centro.id)) continue;
      resultado.add(centro);
      pendientes.add(centro.id);
    }
  }

  final raiz = centros.where((centro) => centro.id == raizId);
  final subarbol = <CentroCosto>[...raiz, ...resultado];
  subarbol.sort((a, b) => a.nombre.compareTo(b.nombre));
  return subarbol;
}

String _sinTildes(String texto) {
  const con = 'áéíóúüñÁÉÍÓÚÜÑ';
  const sin = 'aeiouunAEIOUUN';
  final buffer = StringBuffer();
  for (final letra in texto.split('')) {
    final i = con.indexOf(letra);
    buffer.write(i < 0 ? letra : sin[i]);
  }
  return buffer.toString().toLowerCase();
}

/// Busca por código o nombre, sin importar tildes ni mayúsculas. Con varias
/// palabras, todas deben aparecer ("andaria kid" encuentra 057.01).
/// Ordena por código para que cada parque quede junto a sus hijos.
List<CentroCosto> filtrarCentros(List<CentroCosto> centros, String consulta) {
  final palabras = _sinTildes(consulta.trim())
      .split(RegExp(r'\s+'))
      .where((palabra) => palabra.isNotEmpty)
      .toList(growable: false);
  final resultado = centros.where((centro) {
    final texto = _sinTildes('${centro.codigo} ${centro.nombre}');
    return palabras.every(texto.contains);
  }).toList();
  resultado.sort((a, b) {
    final porCodigo = a.codigo.compareTo(b.codigo);
    return porCodigo != 0 ? porCodigo : a.nombre.compareTo(b.nombre);
  });
  return resultado;
}

/// Parques y áreas principales: los hijos directos de la raíz de la empresa.
/// Los sub-centros (Kiddies, Cajas Mágicas, Caseta) quedan para contabilidad
/// pero no se ofrecen en la app, para que cada parque aparezca una sola vez.
List<CentroCosto> centrosPrincipales(List<CentroCosto> centros) {
  final raices = {
    for (final c in centros)
      if (c.padreId == null) c.id,
  };
  return centros.where((c) => raices.contains(c.padreId)).toList();
}

/// Centros que se pueden cargar en un lugar: el suyo con sus sub-centros y
/// los agregados en `parques_centros` (también con sus sub-centros).
/// Sin repetidos; el centro propio del lugar va primero y el resto por código.
List<CentroCosto> centrosDeLugar({
  required String centroDelLugar,
  required Set<String> extras,
  required List<CentroCosto> centros,
}) {
  final vistos = <String>{};
  final resultado = <CentroCosto>[];
  for (final raiz in [centroDelLugar, ...extras]) {
    for (final c in subarbolDe(centros, raiz)) {
      if (vistos.add(c.id)) resultado.add(c);
    }
  }
  final propio = resultado.where((c) => c.id == centroDelLugar);
  final resto = resultado.where((c) => c.id != centroDelLugar).toList()
    ..sort((a, b) => a.codigo.compareTo(b.codigo));
  return [...propio, ...resto];
}
