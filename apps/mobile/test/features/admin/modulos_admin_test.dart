import 'package:carrousel_app/core/theme/app_theme.dart';
import 'package:carrousel_app/core/widgets/ecosistema.dart';
import 'package:carrousel_app/data/models/admin_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lee un registro pendiente', () {
    final registro = Registro.fromMap({
      'id': 'r1',
      'email': 'nuevo@carrousel.com.gt',
      'nombre': 'Técnico Nuevo',
      'telefono': '5555-0000',
      'estado': 'pendiente',
      'motivo': null,
      'creado_en': '2026-11-12T15:00:00Z',
    });
    expect(registro.pendiente, isTrue);
    expect(registro.rechazado, isFalse);
  });

  test('lee una incidencia y traduce su tipo', () {
    final incidencia = Incidencia.fromMap({
      'id': 'i1',
      'jornada_id': 'j1',
      'empleado_id': 'u1',
      'tipo': 'salida_temprana',
      'severidad': 'alta',
      'descripcion': 'Salió 120 min antes de lo programado (17:00).',
      'estado': 'abierta',
      'resolucion': null,
      'creado_en': '2026-11-12T21:00:00Z',
      'resuelto_en': null,
    });
    expect(incidencia.tipo, TipoIncidencia.salidaTemprana);
    expect(incidencia.tipo.etiqueta, 'Salida temprana');
    expect(incidencia.abierta, isTrue);
  });

  testWidgets('una confirmación destructiva usa rojo y se cancela por defecto',
      (tester) async {
    bool? resultado;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => resultado = await confirmar(
                context,
                pregunta: '¿Rechazar el registro?',
                aceptar: 'Rechazar',
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    final boton = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(
      boton.style?.backgroundColor?.resolve({}),
      ColoresCarrousel.claro.danger,
    );
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(resultado, isFalse);
  });

  testWidgets('el tema oscuro usa la paleta del ecosistema', (tester) async {
    final tema = AppTheme.dark;
    expect(tema.scaffoldBackgroundColor, const Color(0xFF0E1526));
    expect(tema.extension<ColoresCarrousel>(), ColoresCarrousel.oscuro);
    expect(AppTheme.light.colorScheme.primary, Marca.brand);
  });
}
