import 'package:carrousel_app/data/models/solicitud_horas_extras.dart';
import 'package:carrousel_app/features/solicitudes/widgets/solicitud_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

SolicitudDetalle detalleCancelada() {
  return SolicitudDetalle(
    solicitud: SolicitudHorasExtras(
      id: 's1',
      empresaId: 'e1',
      empleadoId: 'u1',
      centroCostoId: 'c1',
      inicio: DateTime(2026, 11, 10, 9),
      fin: DateTime(2026, 11, 10, 11),
      justificacion: 'Apoyo en el parque central durante el evento',
      estado: EstadoSolicitud.cancelada,
      creadoEn: DateTime(2026, 11, 10, 8),
      revisadoEn: DateTime(2026, 11, 10, 12),
    ),
    empleadoNombre: 'Empleado Uno',
    centroNombre: 'Parque Central',
  );
}

Future<void> mostrar(WidgetTester tester, Widget widget) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: widget),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es');
  });

  testWidgets('la tarjeta muestra una solicitud retirada', (tester) async {
    await mostrar(tester, SolicitudCard(detalle: detalleCancelada()));

    expect(find.text('Cancelada'), findsOneWidget);
    expect(find.textContaining('Retirada'), findsOneWidget);
    expect(find.text('Comentario del administrador'), findsNothing);
    expect(find.text('Revisada'), findsNothing);
  });

  testWidgets('la tarjeta muestra el comentario del admin al rechazar',
      (tester) async {
    final detalle = detalleCancelada();
    final rechazada = SolicitudDetalle(
      solicitud: SolicitudHorasExtras(
        id: detalle.solicitud.id,
        empresaId: detalle.solicitud.empresaId,
        empleadoId: detalle.solicitud.empleadoId,
        centroCostoId: detalle.solicitud.centroCostoId,
        inicio: detalle.solicitud.inicio,
        fin: detalle.solicitud.fin,
        justificacion: detalle.solicitud.justificacion,
        estado: EstadoSolicitud.rechazada,
        creadoEn: detalle.solicitud.creadoEn,
        comentarioAdmin: 'El rango no coincide con el marcaje.',
        revisadoPor: 'admin1',
        revisadoEn: DateTime(2026, 11, 10, 12),
      ),
      empleadoNombre: 'Empleado Uno',
      centroNombre: 'Parque Central',
    );

    await mostrar(tester, SolicitudCard(detalle: rechazada));

    expect(find.text('Rechazada'), findsOneWidget);
    expect(find.text('Comentario del administrador'), findsOneWidget);
    expect(find.textContaining('Revisada'), findsOneWidget);
  });
}
