import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/errors/error_messages.dart';
import '../../core/utils/duraciones.dart';
import '../../core/utils/reporte_csv.dart';
import '../../providers/app_providers.dart';

/// Pide un rango de fechas, descarga el reporte de horas extras del equipo
/// (la vista respeta RLS) y lo comparte como CSV para abrirlo en Excel.
Future<void> exportarReporteHorasExtras(
  BuildContext context,
  WidgetRef ref,
) async {
  final hoy = DateTime.now();
  final rango = await showDateRangePicker(
    context: context,
    firstDate: DateTime(hoy.year - 2),
    lastDate: DateTime(hoy.year, hoy.month, hoy.day),
    initialDateRange: DateTimeRange(
      start: inicioMes(hoy),
      end: DateTime(hoy.year, hoy.month, hoy.day),
    ),
    helpText: 'Periodo del reporte',
    saveText: 'Exportar',
  );
  if (rango == null || !context.mounted) return;

  final mensajero = ScaffoldMessenger.of(context);
  mensajero.showSnackBar(
    const SnackBar(content: Text('Preparando el reporte...')),
  );

  try {
    final filas = await ref
        .read(solicitudRepositoryProvider)
        .reporte(desde: inicioDelDia(rango.start), hasta: finDelDia(rango.end));
    mensajero.hideCurrentSnackBar();
    if (filas.isEmpty) {
      mensajero.showSnackBar(
        const SnackBar(content: Text('No hay horas extras en ese periodo.')),
      );
      return;
    }

    final formato = DateFormat('yyyyMMdd');
    final nombre = 'horas_extras_${formato.format(rango.start)}_'
        '${formato.format(rango.end)}.csv';
    final bytes = utf8.encode(generarCsvHorasExtras(filas));

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'text/csv', name: nombre)],
        fileNameOverrides: [nombre],
        subject: 'Reporte de horas extras',
        text: '${filas.length} registros · '
            '${horasAprobadas(filas).toStringAsFixed(1)} h aprobadas',
      ),
    );
  } catch (error) {
    mensajero
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensajeDeError(error))));
  }
}
