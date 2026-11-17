import 'package:carrousel_app/features/auth/domain/entities/perfil.dart';
import 'package:carrousel_app/features/auth/domain/entities/rol_usuario.dart';
import 'package:carrousel_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:carrousel_app/features/horario/domain/entities/horario.dart';
import 'package:carrousel_app/features/horario/presentation/pages/mi_horario_page.dart';
import 'package:carrousel_app/features/horario/presentation/providers/horario_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _empleado = Perfil(
  id: 'empleado-id',
  empresaId: 'empresa-id',
  centroCostoId: 'centro-id',
  rol: RolUsuario.empleado,
  nombreCompleto: 'Ana Pérez',
);

Horario _horario({
  required int dia,
  required String entrada,
  required String salida,
}) {
  return Horario(
    id: 'h$dia',
    empresaId: 'empresa-id',
    empleadoId: _empleado.id,
    diaSemana: dia,
    horaEntrada: entrada,
    horaSalida: salida,
    toleranciaEntradaMin: 10,
    toleranciaSalidaMin: 15,
    activo: true,
  );
}

Widget _app(List<Horario> horarios) {
  return ProviderScope(
    overrides: [
      perfilProvider.overrideWith((ref) async => _empleado),
      horariosEmpleadoProvider.overrideWith((ref, _) async => horarios),
    ],
    child: const MaterialApp(home: Scaffold(body: MiHorarioPage())),
  );
}

void main() {
  testWidgets('muestra el turno nocturno cruzando medianoche', (tester) async {
    await tester.pumpWidget(
      _app([
        _horario(dia: 1, entrada: '22:00', salida: '06:00'),
        _horario(dia: 2, entrada: '09:00', salida: '18:00'),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mi horario'), findsOneWidget);
    expect(find.text('Nocturno'), findsOneWidget);
    expect(find.text('22:00 - 06:00 (+1 día) · 8 h'), findsOneWidget);
    expect(find.text('09:00 - 18:00 · 9 h'), findsOneWidget);
    expect(
      find.text('Tu horario vigente tiene 2 días laborales.'),
      findsOneWidget,
    );
    expect(find.text('Descanso'), findsWidgets);
  });
}
