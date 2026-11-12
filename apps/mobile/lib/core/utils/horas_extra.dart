import '../../data/models/horario.dart';

/// Mínimo para sugerir una solicitud: menos de media hora no se registra,
/// igual que las opciones del formulario.
const minutosMinimosExtra = 30;

/// Jornadas cerradas con tiempo extra respaldado por GPS que aún no tienen
/// una solicitud viva. Las más recientes primero.
List<CumplimientoJornada> horasExtraPorSolicitar(
  List<CumplimientoJornada> filas,
) {
  final pendientes = filas
      .where(
        (fila) =>
            fila.salidaProgramada != null &&
            fila.salidaEn != null &&
            (fila.minutosExtra ?? 0) >= minutosMinimosExtra &&
            fila.solicitudId == null,
      )
      .toList();
  pendientes.sort((a, b) => b.entradaEn.compareTo(a.entradaEn));
  return pendientes;
}

/// Redondea hacia abajo a medias horas: 95 min → 1 h 30 min.
Duration extraRedondeado(int minutos) =>
    Duration(minutes: (minutos ~/ 30) * 30);

/// Inicio del tiempo extra: la salida programada, o la entrada si llegó
/// después de esa hora.
DateTime inicioDelExtra(CumplimientoJornada fila) {
  final programada = fila.salidaProgramada!;
  return programada.isBefore(fila.entradaEn) ? fila.entradaEn : programada;
}
