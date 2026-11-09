import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/error_messages.dart';

class JornadaRepository {
  JornadaRepository(this._client);

  final SupabaseClient _client;

  Future<void> marcarEntrada({
    required String parqueId,
    required double latitud,
    required double longitud,
    required double precisionMetros,
  }) async {
    await _client.from('jornadas').insert({
      'parque_id': parqueId,
      'entrada_lat': latitud,
      'entrada_lon': longitud,
      'entrada_precision_metros': precisionMetros,
    });
  }

  Future<void> marcarSalida({
    required String jornadaId,
    required double latitud,
    required double longitud,
    required double precisionMetros,
  }) async {
    final filas = await _client
        .from('jornadas')
        .update({
          'salida_lat': latitud,
          'salida_lon': longitud,
          'salida_precision_metros': precisionMetros,
        })
        .eq('id', jornadaId)
        .select('id');
    if (filas.isEmpty) {
      throw const AppException(
        'No se pudo cerrar la jornada. Puede que ya esté cerrada o no tengas permiso.',
      );
    }
  }
}
