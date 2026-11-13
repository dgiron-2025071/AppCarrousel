import 'package:carrousel_app/features/catalogo/domain/entities/centro_costo.dart';
import 'package:carrousel_app/features/catalogo/domain/entities/parque.dart';
import 'package:carrousel_app/features/catalogo/domain/repositories/catalogo_repository.dart';

class ListarCentros {
  const ListarCentros(this._repo);

  final CatalogoRepository _repo;

  Future<List<CentroCosto>> call() => _repo.centros();
}

class ListarParques {
  const ListarParques(this._repo);

  final CatalogoRepository _repo;

  Future<List<Parque>> call() => _repo.parques();
}

class ListarNombresDePerfiles {
  const ListarNombresDePerfiles(this._repo);

  final CatalogoRepository _repo;

  Future<Map<String, String>> call() => _repo.nombresDePerfiles();
}
