import 'package:carrousel_app/features/horario/domain/entities/horario.dart';

export 'package:carrousel_app/core/utils/horas.dart'
    show normalizarHora, minutosDeHora, horaDeMinutos, validarFranja;

const diasSemanaEtiquetas = <String>[
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];

/// Día ISO (1 = lunes … 7 = domingo) a etiqueta en español.
String nombreDia(int diaSemana) {
  if (diaSemana < 1 || diaSemana > 7) return 'Día $diaSemana';
  return diasSemanaEtiquetas[diaSemana - 1];
}

/// Texto compacto del turno, con aviso de que cruza medianoche.
String describirTurno(Horario horario) {
  final turno = '${horario.horaEntrada} - ${horario.horaSalida}';
  return horario.nocturno ? '$turno (+1 día)' : turno;
}

/// Horas y minutos legibles para la duración del turno.
String duracionTurno(Horario horario) {
  final horas = horario.duracionMinutos ~/ 60;
  final minutos = horario.duracionMinutos % 60;
  if (minutos == 0) return '$horas h';
  return '$horas h ${minutos.toString().padLeft(2, '0')} min';
}
