import 'package:flutter/material.dart';

/// Días ISO: 1 = lunes … 7 = domingo, igual que `extract(isodow)` en la base.
const nombresDias = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];

String nombreDia(int diaSemana) => nombresDias[diaSemana - 1];

TimeOfDay _hora(String valor) {
  final partes = valor.split(':');
  return TimeOfDay(hour: int.parse(partes[0]), minute: int.parse(partes[1]));
}

String horaSql(TimeOfDay hora) => '${hora.hour.toString().padLeft(2, '0')}:'
    '${hora.minute.toString().padLeft(2, '0')}';

/// Horario de un empleado para un día de la semana.
class Horario {
  const Horario({
    required this.diaSemana,
    required this.horaEntrada,
    required this.horaSalida,
    this.id,
    this.parqueId,
    this.toleranciaMinutos = 10,
  });

  final String? id;
  final int diaSemana;
  final TimeOfDay horaEntrada;
  final TimeOfDay horaSalida;
  final String? parqueId;
  final int toleranciaMinutos;

  /// Turno que termina al día siguiente (ej. 22:00 → 06:00).
  bool get nocturno =>
      horaSalida.hour * 60 + horaSalida.minute <
      horaEntrada.hour * 60 + horaEntrada.minute;

  Duration get duracion {
    final entrada = horaEntrada.hour * 60 + horaEntrada.minute;
    var salida = horaSalida.hour * 60 + horaSalida.minute;
    if (salida <= entrada) salida += 24 * 60;
    return Duration(minutes: salida - entrada);
  }

  Horario copyWith({
    TimeOfDay? horaEntrada,
    TimeOfDay? horaSalida,
    String? parqueId,
    bool quitarParque = false,
    int? toleranciaMinutos,
  }) =>
      Horario(
        id: id,
        diaSemana: diaSemana,
        horaEntrada: horaEntrada ?? this.horaEntrada,
        horaSalida: horaSalida ?? this.horaSalida,
        parqueId: quitarParque ? null : (parqueId ?? this.parqueId),
        toleranciaMinutos: toleranciaMinutos ?? this.toleranciaMinutos,
      );

  factory Horario.fromMap(Map<String, dynamic> map) => Horario(
        id: map['id'] as String,
        diaSemana: (map['dia_semana'] as num).toInt(),
        horaEntrada: _hora(map['hora_entrada'] as String),
        horaSalida: _hora(map['hora_salida'] as String),
        parqueId: map['parque_id'] as String?,
        toleranciaMinutos: (map['tolerancia_minutos'] as num?)?.toInt() ?? 10,
      );
}

/// Fila de la vista `cumplimiento_jornadas`.
class CumplimientoJornada {
  const CumplimientoJornada({
    required this.jornadaId,
    required this.parqueId,
    required this.fecha,
    required this.entradaEn,
    this.salidaEn,
    this.salidaProgramada,
    this.minutosTarde,
    this.llegoTarde = false,
    this.minutosExtra,
    this.enParqueProgramado = true,
    this.solicitudId,
  });

  final String jornadaId;
  final String parqueId;
  final DateTime fecha;
  final DateTime entradaEn;
  final DateTime? salidaEn;
  final DateTime? salidaProgramada;
  final int? minutosTarde;
  final bool llegoTarde;

  /// NULL cuando ese día no tiene horario.
  final int? minutosExtra;
  final bool enParqueProgramado;
  final String? solicitudId;

  static DateTime? _fecha(Object? valor) =>
      valor == null ? null : DateTime.parse(valor as String).toLocal();

  factory CumplimientoJornada.fromMap(Map<String, dynamic> map) =>
      CumplimientoJornada(
        jornadaId: map['jornada_id'] as String,
        parqueId: map['parque_id'] as String,
        fecha: DateTime.parse(map['fecha'] as String),
        entradaEn: _fecha(map['entrada_en'])!,
        salidaEn: _fecha(map['salida_en']),
        salidaProgramada: _fecha(map['salida_programada']),
        minutosTarde: (map['minutos_tarde'] as num?)?.toInt(),
        llegoTarde: map['llego_tarde'] as bool? ?? false,
        minutosExtra: (map['minutos_extra'] as num?)?.toInt(),
        enParqueProgramado: map['en_parque_programado'] as bool? ?? true,
        solicitudId: map['solicitud_id'] as String?,
      );
}
