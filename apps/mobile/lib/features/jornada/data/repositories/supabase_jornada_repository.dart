import 'package:carrousel_app/core/errors/error_messages.dart';
import 'package:carrousel_app/features/jornada/data/mappers/jornada_mapper.dart';
import 'package:carrousel_app/features/jornada/domain/entities/jornada.dart';
import 'package:carrousel_app/features/jornada/domain/repositories/jornada_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseJornadaRepository implements JornadaRepository {
  SupabaseJornadaRepository(this._client);

  final SupabaseClient _client;

  @override
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

  @override
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

  @override
  Stream<List<Jornada>> observarJornadas(String empleadoId) {
    return _client
        .from('jornadas')
        .stream(primaryKey: ['id'])
        .eq('empleado_id', empleadoId)
        .order('entrada_en', ascending: false)
        .map((filas) {
      // Realtime agrega las filas nuevas al final; se reordena en cliente
      // para que el último marcaje siempre quede primero.
      final jornadas = filas.map(jornadaDesdeMapa).toList();
      jornadas.sort((a, b) => b.entradaEn.compareTo(a.entradaEn));
      return jornadas;
    });
  }
}
