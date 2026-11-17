import 'package:carrousel_app/features/shell/presentation/pages/root_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sin credenciales muestra la configuración y no intenta Auth', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: RootGate(initError: 'error de prueba')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Configura Carrousel'), findsOneWidget);
    expect(find.textContaining('No se incluyen credenciales'), findsOneWidget);
    // La guarda de configuración se evalúa antes que initError.
    expect(
      find.textContaining('No se pudo conectar con Supabase'),
      findsNothing,
    );
    expect(find.text('Control de jornadas y horas extras'), findsNothing);
  });
}
