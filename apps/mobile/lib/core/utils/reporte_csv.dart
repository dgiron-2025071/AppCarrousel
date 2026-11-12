import 'package:intl/intl.dart';

import '../../data/models/fila_reporte_horas_extras.dart';
import '../../data/models/solicitud_horas_extras.dart';

/// Encabezados en el mismo orden que el formulario "Formato de horas Extras"
/// para que el reporte reemplace la hoja de respuestas sin reacomodar columnas.
const encabezadosReporteHorasExtras = [
  'Marca temporal',
  'Nombre del técnico',
  'Puesto',
  'Fecha de actividad',
  'Hora de inicio',
  'Hora de fin',
  'Actividad realizada',
  'Cantidad de horas Extras',
  'Código centro de costo',
  'Centro de costo',
  'Persona que autoriza',
  'Estado',
  'Revisado por',
  'Fecha de revisión',
  'Comentario',
];

String _campo(String? valor) {
  final texto = (valor ?? '').replaceAll('\r\n', '\n');
  final necesitaComillas = texto.contains(RegExp(r'[",\n]')) ||
      texto.startsWith(' ') ||
      texto.endsWith(' ');
  // Evita que Excel interprete el texto como fórmula.
  final seguro = RegExp(r'^[=+\-@]').hasMatch(texto) ? "'$texto" : texto;
  return necesitaComillas || seguro != texto
      ? '"${seguro.replaceAll('"', '""')}"'
      : seguro;
}

/// CSV con BOM UTF-8 (Excel respeta las tildes) y fin de línea CRLF.
String generarCsvHorasExtras(List<FilaReporteHorasExtras> filas) {
  final fechaHora = DateFormat('dd/MM/yyyy HH:mm');
  final fecha = DateFormat('dd/MM/yyyy');
  final hora = DateFormat('HH:mm');
  final horas = NumberFormat('0.##', 'en_US');

  final lineas = <String>[
    encabezadosReporteHorasExtras.map(_campo).join(','),
    for (final fila in filas)
      [
        fechaHora.format(fila.creadoEn),
        fila.empleado,
        fila.puesto,
        fecha.format(fila.inicio),
        hora.format(fila.inicio),
        hora.format(fila.fin),
        fila.actividadRealizada,
        horas.format(fila.horas),
        fila.cecoCodigo,
        fila.cecoNombre,
        fila.personaQueAutoriza,
        fila.estado.etiqueta,
        fila.revisadoPor,
        fila.revisadoEn == null ? null : fechaHora.format(fila.revisadoEn!),
        fila.comentarioAdmin,
      ].map(_campo).join(','),
  ];
  return '\uFEFF${lineas.join('\r\n')}\r\n';
}

/// Total de horas de las filas aprobadas, para el resumen antes de exportar.
double horasAprobadas(List<FilaReporteHorasExtras> filas) => filas
    .where((fila) => fila.estado == EstadoSolicitud.aprobada)
    .fold(0, (total, fila) => total + fila.horas);
