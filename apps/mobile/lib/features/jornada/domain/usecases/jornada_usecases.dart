import 'package:carrousel_app/features/jornada/domain/entities/jornada.dart';
import 'package:carrousel_app/features/jornada/domain/repositories/jornada_repository.dart';

class MarcarEntrada {
  const MarcarEntrada(this._repo);

  final JornadaRepository _repo;

  Future<void> call({
    required String parqueId,
    required double latitud,
    required double longitud,
    required double precisionMetros,
  }) =>
      _repo.marcarEntrada(
        parqueId: parqueId,
        latitud: latitud,
        longitud: longitud,
        precisionMetros: precisionMetros,
      );
}

class MarcarSalida {
  const MarcarSalida(this._repo);

  final JornadaRepository _repo;

  Future<void> call({
    required String jornadaId,
    required double latitud,
    required double longitud,
    required double precisionMetros,
  }) =>
      _repo.marcarSalida(
        jornadaId: jornadaId,
        latitud: latitud,
        longitud: longitud,
        precisionMetros: precisionMetros,
      );
}

class ObservarJornadas {
  const ObservarJornadas(this._repo);

  final JornadaRepository _repo;

  Stream<List<Jornada>> call(String empleadoId) =>
      _repo.observarJornadas(empleadoId);
}
