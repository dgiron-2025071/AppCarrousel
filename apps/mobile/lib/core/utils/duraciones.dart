import 'package:intl/intl.dart';

DateTime inicioDelDia(DateTime fecha) =>
    DateTime(fecha.year, fecha.month, fecha.day);

DateTime inicioSemana(DateTime fecha) {
  final dia = inicioDelDia(fecha);
  return dia.subtract(Duration(days: dia.weekday - DateTime.monday));
}

DateTime inicioMes(DateTime fecha) => DateTime(fecha.year, fecha.month);

DateTime finDelDia(DateTime fecha) => inicioDelDia(fecha).add(const Duration(days: 1));

String formatearHora(DateTime fecha) => DateFormat('HH:mm').format(fecha);

String formatearFecha(DateTime fecha) =>
    DateFormat("EEE d 'de' MMM", 'es').format(fecha);

String formatearFechaHora(DateTime fecha) =>
    DateFormat("EEE d 'de' MMM, HH:mm", 'es').format(fecha);

String formatearDuracion(Duration duracion) {
  final horas = duracion.inHours;
  final minutos = duracion.inMinutes.remainder(60);
  if (horas == 0) return '$minutos min';
  return '$horas h ${minutos.toString().padLeft(2, '0')} min';
}

String formatearHorasDecimales(Duration duracion) {
  final horas = duracion.inMinutes / 60;
  return horas.toStringAsFixed(horas >= 10 ? 0 : 1);
}
