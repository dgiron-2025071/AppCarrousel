import 'package:carrousel_app/features/solicitudes/domain/entities/solicitud_horas_extras.dart';
import 'package:carrousel_app/features/solicitudes/domain/repositories/solicitud_repository.dart';

class CrearSolicitud {
  const CrearSolicitud(this._repo);

  final SolicitudRepository _repo;

  Future<void> call({
    required String centroCostoId,
    required DateTime inicio,
    required DateTime fin,
    required String justificacion,
  }) =>
      _repo.crear(
        centroCostoId: centroCostoId,
        inicio: inicio,
        fin: fin,
        justificacion: justificacion,
      );
}

class RevisarSolicitud {
  const RevisarSolicitud(this._repo);

  final SolicitudRepository _repo;

  Future<void> call({
    required String solicitudId,
    required EstadoSolicitud decision,
    String? comentario,
  }) =>
      _repo.revisar(
        solicitudId: solicitudId,
        decision: decision,
        comentario: comentario,
      );
}

class CancelarSolicitud {
  const CancelarSolicitud(this._repo);

  final SolicitudRepository _repo;

  Future<void> call(String solicitudId) =>
      _repo.cancelar(solicitudId: solicitudId);
}

class ObservarSolicitudes {
  const ObservarSolicitudes(this._repo);

  final SolicitudRepository _repo;

  Stream<List<SolicitudHorasExtras>> call() => _repo.observarSolicitudes();
}
