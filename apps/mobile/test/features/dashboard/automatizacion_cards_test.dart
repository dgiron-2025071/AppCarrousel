import 'package:carrousel_app/core/theme/app_theme.dart';
import 'package:carrousel_app/data/models/horario.dart';
import 'package:carrousel_app/data/models/parque.dart';
import 'package:carrousel_app/features/dashboard/widgets/automatizacion_cards.dart';
import 'package:carrousel_app/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es');
  });

  testWidgets('muestra las horas extra detectadas y el botón Solicitar',
      (tester) async {
    final fila = CumplimientoJornada(
      jornadaId: 'j1',
      parqueId: 'p1',
      fecha: DateTime(2026, 11, 10),
      entradaEn: DateTime(2026, 11, 10, 7, 55),
      salidaEn: DateTime(2026, 11, 10, 18, 40),
      salidaProgramada: DateTime(2026, 11, 10, 17),
      minutosExtra: 100,
    );
    const parque = Parque(
      id: 'p1',
      empresaId: 'e1',
      centroCostoId: 'c1',
      codigo: '045',
      nombre: 'Pradera Zona 10',
      latitud: 14.6,
      longitud: -90.51,
      radioMetros: 150,
      activo: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          horasExtraPorSolicitarProvider.overrideWith((ref) async => [fila]),
          parquesProvider.overrideWith((ref) async => [parque]),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: HorasExtraDetectadasCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Horas extra detectadas por GPS'), findsOneWidget);
    expect(find.textContaining('1 h 30 min'), findsOneWidget);
    expect(find.textContaining('Pradera Zona 10'), findsOneWidget);
    expect(find.text('Solicitar'), findsOneWidget);
  });

  testWidgets('no ocupa espacio si no hay horas extra', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          horasExtraPorSolicitarProvider.overrideWith((ref) async => []),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: HorasExtraDetectadasCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Horas extra detectadas por GPS'), findsNothing);
  });

  testWidgets('aparece dentro de una lista cuando los datos llegan tarde',
      (tester) async {
    final fila = CumplimientoJornada(
      jornadaId: 'j1',
      parqueId: 'p1',
      fecha: DateTime(2026, 11, 10),
      entradaEn: DateTime(2026, 11, 10, 7, 55),
      salidaEn: DateTime(2026, 11, 10, 18, 40),
      salidaProgramada: DateTime(2026, 11, 10, 17),
      minutosExtra: 100,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          horasExtraPorSolicitarProvider.overrideWith((ref) async {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            return [fila];
          }),
          parquesProvider.overrideWith((ref) async => []),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ListView(
              children: const [
                SizedBox(height: 200),
                HorasExtraDetectadasCard(),
                Text('Últimos marcajes'),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('Horas extra detectadas por GPS'), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Horas extra detectadas por GPS'), findsOneWidget);
  });
}
