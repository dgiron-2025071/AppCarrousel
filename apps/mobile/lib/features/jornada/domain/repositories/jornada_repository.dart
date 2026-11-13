import 'package:carrousel_app/features/jornada/domain/entities/jornada.dart';

/// Operaciones de marcaje y observación de jornadas.
abstract class JornadaRepository {
  Future<void> marcarEntrada({
    required String parqueId,
    required double latitud,
    required double longitud,
    required double precisionMetros,
  });

  Future<void> marcarSalida({
    required String jornadaId,
    required double latitud,
    required double longitud,
    required double precisionMetros,
  });

  /// Stream en vivo de las jornadas del empleado, más recientes primero.
  Stream<List<Jornada>> observarJornadas(String empleadoId);
}
