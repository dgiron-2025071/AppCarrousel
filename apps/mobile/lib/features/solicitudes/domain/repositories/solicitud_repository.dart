import 'package:carrousel_app/features/solicitudes/domain/entities/solicitud_horas_extras.dart';

/// Contrato de solicitudes de horas extras.
abstract class SolicitudRepository {
  Future<void> crear({
    required String centroCostoId,
    required DateTime inicio,
    required DateTime fin,
    required String justificacion,
  });

  Future<void> revisar({
    required String solicitudId,
    required EstadoSolicitud decision,
    String? comentario,
  });

  /// Retira una solicitud propia mientras siga pendiente. La base de datos
  /// conserva el historial y rechaza la operación si ya fue revisada.
  Future<void> cancelar({required String solicitudId});

  /// Stream en vivo de solicitudes visibles por RLS.
  Stream<List<SolicitudHorasExtras>> observarSolicitudes();
}
