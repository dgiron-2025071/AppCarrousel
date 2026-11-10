import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/error_messages.dart';
import '../models/solicitud_horas_extras.dart';

class SolicitudRepository {
  SolicitudRepository(this._client);

  final SupabaseClient _client;

  Future<void> crear({
    required String centroCostoId,
    required DateTime inicio,
    required DateTime fin,
    required String justificacion,
  }) async {
    await _client.from('solicitudes_horas_extras').insert({
      'centro_costo_id': centroCostoId,
      'inicio': inicio.toUtc().toIso8601String(),
      'fin': fin.toUtc().toIso8601String(),
      'justificacion': justificacion.trim(),
    });
  }

  Future<void> revisar({
    required String solicitudId,
    required EstadoSolicitud decision,
    String? comentario,
  }) async {
    if (decision != EstadoSolicitud.aprobada &&
        decision != EstadoSolicitud.rechazada) {
      throw const AppException('La decisión debe ser aprobar o rechazar.');
    }
    final texto = comentario?.trim() ?? '';
    final filas = await _client
        .from('solicitudes_horas_extras')
        .update({
          'estado': decision.name,
          'comentario_admin': texto.isEmpty ? null : texto,
        })
        .eq('id', solicitudId)
        .select('id');
    if (filas.isEmpty) {
      throw const AppException(
        'La solicitud ya no está pendiente o no tienes permiso para revisarla.',
      );
    }
  }

  /// Retira una solicitud propia mientras siga pendiente. La base de datos
  /// conserva el historial y rechaza la operación si ya fue revisada.
  Future<void> cancelar({required String solicitudId}) async {
    final filas = await _client
        .from('solicitudes_horas_extras')
        .update({'estado': EstadoSolicitud.cancelada.name})
        .eq('id', solicitudId)
        .eq('estado', EstadoSolicitud.pendiente.name)
        .select('id');
    if (filas.isEmpty) {
      throw const AppException(
        'La solicitud ya no está pendiente o no puedes retirarla.',
      );
    }
  }
}
