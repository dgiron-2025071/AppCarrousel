import 'package:carrousel_app/features/catalogo/domain/entities/centro_costo.dart';
import 'package:carrousel_app/features/catalogo/domain/entities/parque.dart';

/// Catálogos visibles para el usuario según RLS.
abstract class CatalogoRepository {
  Future<List<CentroCosto>> centros();

  Future<List<Parque>> parques();

  Future<Map<String, String>> nombresDePerfiles();
}
