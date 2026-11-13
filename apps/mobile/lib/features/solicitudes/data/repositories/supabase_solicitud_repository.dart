import 'package:carrousel_app/core/errors/error_messages.dart';
import 'package:carrousel_app/features/solicitudes/data/mappers/solicitud_mapper.dart';
import 'package:carrousel_app/features/solicitudes/domain/entities/solicitud_horas_extras.dart';
import 'package:carrousel_app/features/solicitudes/domain/repositories/solicitud_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseSolicitudRepository implements SolicitudRepository {
  SupabaseSolicitudRepository(this._client);

  final SupabaseClient _client;

  @override
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

  @override
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

  @override
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

  @override
  Stream<List<SolicitudHorasExtras>> observarSolicitudes() {
    return _client
        .from('solicitudes_horas_extras')
        .stream(primaryKey: ['id'])
        .order('creado_en', ascending: false)
        .map((filas) {
      final solicitudes = filas.map(solicitudDesdeMapa).toList();
      solicitudes.sort((a, b) => b.creadoEn.compareTo(a.creadoEn));
      return solicitudes;
    });
  }
}
