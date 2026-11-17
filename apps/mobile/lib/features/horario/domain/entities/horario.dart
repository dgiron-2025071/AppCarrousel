import 'package:carrousel_app/core/utils/horas.dart';

/// Horario semanal de un empleado para un día ISO.
///
/// `horaEntrada` y `horaSalida` usan el formato `HH:mm`. Una salida menor que
/// la entrada representa un turno nocturno que cruza medianoche; la base
/// rechaza que sean iguales (`horarios_franja_distinta`).
class Horario {
  const Horario({
    required this.id,
    required this.empresaId,
    required this.empleadoId,
    required this.diaSemana,
    required this.horaEntrada,
    required this.horaSalida,
    required this.toleranciaEntradaMin,
    required this.toleranciaSalidaMin,
    required this.activo,
  });

  final String id;
  final String empresaId;
  final String empleadoId;

  /// Día ISO: 1 = lunes … 7 = domingo.
  final int diaSemana;
  final String horaEntrada;
  final String horaSalida;
  final int toleranciaEntradaMin;
  final int toleranciaSalidaMin;
  final bool activo;

  int get minutosEntrada => minutosDeHora(horaEntrada);

  int get minutosSalida => minutosDeHora(horaSalida);

  bool get franjaValida => validarFranja(horaEntrada, horaSalida) == null;

  bool get nocturno => franjaValida && minutosSalida < minutosEntrada;

  int get duracionMinutos => nocturno
      ? 1440 - minutosEntrada + minutosSalida
      : (minutosSalida - minutosEntrada).clamp(0, 1440);

  Duration get duracion => Duration(minutes: duracionMinutos);
}
