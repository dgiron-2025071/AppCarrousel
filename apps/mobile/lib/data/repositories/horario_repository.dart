import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/horario.dart';

class HorarioRepository {
  HorarioRepository(this._client);

  final SupabaseClient _client;

  Future<List<Horario>> horariosDe(String empleadoId) async {
    final filas = await _client
        .from('horarios')
        .select(
          'id, dia_semana, hora_entrada, hora_salida, parque_id, tolerancia_minutos',
        )
        .eq('empleado_id', empleadoId)
        .order('dia_semana');
    return filas.map(Horario.fromMap).toList(growable: false);
  }

  /// Guarda la semana completa: crea, cambia o borra cada día según
  /// [semana]. Un día ausente en [semana] queda como descanso.
  Future<void> guardarSemana({
    required String empleadoId,
    required List<Horario> anteriores,
    required Map<int, Horario> semana,
  }) async {
    final porDia = {for (final h in anteriores) h.diaSemana: h};

    for (final anterior in anteriores) {
      if (!semana.containsKey(anterior.diaSemana)) {
        await _client.from('horarios').delete().eq('id', anterior.id!);
      }
    }

    for (final horario in semana.values) {
      final datos = {
        'hora_entrada': horaSql(horario.horaEntrada),
        'hora_salida': horaSql(horario.horaSalida),
        'parque_id': horario.parqueId,
        'tolerancia_minutos': horario.toleranciaMinutos,
      };
      final anterior = porDia[horario.diaSemana];
      if (anterior == null) {
        await _client.from('horarios').insert({
          ...datos,
          'empleado_id': empleadoId,
          'dia_semana': horario.diaSemana,
        });
      } else {
        await _client.from('horarios').update(datos).eq('id', anterior.id!);
      }
    }
  }

  /// Cumplimiento de las jornadas propias desde [desde].
  Future<List<CumplimientoJornada>> cumplimientoPropio({
    required String empleadoId,
    required DateTime desde,
  }) async {
    final filas = await _client
        .from('cumplimiento_jornadas')
        .select()
        .eq('empleado_id', empleadoId)
        .gte('entrada_en', desde.toUtc().toIso8601String())
        .order('entrada_en', ascending: false);
    return filas.map(CumplimientoJornada.fromMap).toList(growable: false);
  }
}
