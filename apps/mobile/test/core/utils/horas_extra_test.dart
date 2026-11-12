import 'package:carrousel_app/core/utils/horas_extra.dart';
import 'package:carrousel_app/data/models/horario.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CumplimientoJornada _fila(
  String id, {
  int? minutosExtra = 90,
  String? solicitudId,
  DateTime? entrada,
  DateTime? salidaProgramada,
}) {
  final inicio = entrada ?? DateTime(2026, 11, 9, 8, 20);
  return CumplimientoJornada(
    jornadaId: id,
    parqueId: 'p1',
    fecha: DateTime(inicio.year, inicio.month, inicio.day),
    entradaEn: inicio,
    salidaEn: inicio.add(const Duration(hours: 10)),
    salidaProgramada: salidaProgramada ?? DateTime(2026, 11, 9, 17),
    minutosExtra: minutosExtra,
    solicitudId: solicitudId,
  );
}

void main() {
  group('horasExtraPorSolicitar', () {
    test('solo jornadas con al menos 30 min extra y sin solicitud', () {
      final resultado = horasExtraPorSolicitar([
        _fila('ok'),
        _fila('poco', minutosExtra: 20),
        _fila('ya-solicitada', solicitudId: 's1'),
        _fila('sin-horario', minutosExtra: null),
      ]);
      expect(resultado.map((f) => f.jornadaId), ['ok']);
    });

    test('las más recientes primero', () {
      final resultado = horasExtraPorSolicitar([
        _fila('lunes', entrada: DateTime(2026, 11, 9, 8)),
        _fila('martes', entrada: DateTime(2026, 11, 10, 8)),
      ]);
      expect(resultado.map((f) => f.jornadaId), ['martes', 'lunes']);
    });
  });

  test('redondea hacia abajo a medias horas', () {
    expect(extraRedondeado(95), const Duration(minutes: 90));
    expect(extraRedondeado(29), Duration.zero);
    expect(extraRedondeado(120), const Duration(hours: 2));
  });

  test(
      'el extra empieza en la salida programada o en la entrada si fue después',
      () {
    expect(inicioDelExtra(_fila('a')), DateTime(2026, 11, 9, 17));
    expect(
      inicioDelExtra(_fila(
        'b',
        entrada: DateTime(2026, 11, 9, 18),
        salidaProgramada: DateTime(2026, 11, 9, 17),
      )),
      DateTime(2026, 11, 9, 18),
    );
  });

  group('Horario', () {
    test('lee la fila de la base', () {
      final horario = Horario.fromMap({
        'id': 'h1',
        'dia_semana': 1,
        'hora_entrada': '08:00:00',
        'hora_salida': '17:30:00',
        'parque_id': null,
        'tolerancia_minutos': 15,
      });
      expect(horario.horaEntrada, const TimeOfDay(hour: 8, minute: 0));
      expect(horario.horaSalida, const TimeOfDay(hour: 17, minute: 30));
      expect(horario.duracion, const Duration(hours: 9, minutes: 30));
      expect(horario.nocturno, isFalse);
      expect(nombreDia(horario.diaSemana), 'Lunes');
    });

    test('un turno nocturno cruza la medianoche', () {
      const horario = Horario(
        diaSemana: 5,
        horaEntrada: TimeOfDay(hour: 22, minute: 0),
        horaSalida: TimeOfDay(hour: 6, minute: 0),
      );
      expect(horario.nocturno, isTrue);
      expect(horario.duracion, const Duration(hours: 8));
      expect(horaSql(horario.horaSalida), '06:00');
    });
  });
}
