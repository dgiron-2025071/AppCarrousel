import 'package:carrousel_app/features/catalogo/domain/entities/centro_costo.dart';

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
