import 'package:carrousel_app/core/errors/error_messages.dart';
import 'package:carrousel_app/data/models/centro_costo.dart';
import 'package:carrousel_app/data/models/invitacion_usuario.dart';
import 'package:carrousel_app/data/models/perfil.dart';
import 'package:carrousel_app/data/repositories/invitacion_repository.dart';
import 'package:carrousel_app/features/admin/invitar_usuario_page.dart';
import 'package:carrousel_app/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _admin = Perfil(
  id: 'admin-id',
  empresaId: 'empresa-id',
  centroCostoId: 'centro-admin',
  rol: 'admin',
  nombreCompleto: 'Admin Carrousel',
);

const _empleado = Perfil(
  id: 'empleado-id',
  empresaId: 'empresa-id',
  centroCostoId: 'centro-admin',
  rol: 'empleado',
  nombreCompleto: 'Empleado Carrousel',
);

const _centros = [
  CentroCosto(id: 'centro-admin', codigo: 'CA', nombre: 'Centro Admin'),
  CentroCosto(
    id: 'centro-hijo',
    codigo: 'CH',
    nombre: 'Centro Hijo',
    padreId: 'centro-admin',
  ),
  CentroCosto(id: 'centro-otro', codigo: 'CO', nombre: 'Centro Otro'),
];

class _FakeInvitacionGateway implements InvitacionGateway {
  _FakeInvitacionGateway({this.error});

  final Object? error;
  final llamadas = <Map<String, String>>[];

  @override
  Future<InvitacionUsuario> invitar({
    required String email,
    required String nombreCompleto,
    required String rol,
    required String centroCostoId,
  }) async {
    llamadas.add({
      'email': email,
      'nombre_completo': nombreCompleto,
      'rol': rol,
      'centro_costo_id': centroCostoId,
    });
    if (error != null) throw error!;
    return InvitacionUsuario(
      id: 'nuevo-id',
      email: email,
      rol: rol,
      empresaId: 'empresa-id',
      centroCostoId: centroCostoId,
      nombreCompleto: nombreCompleto,
      invitacionEnviada: true,
    );
  }
}

Widget _app({
  required Perfil perfil,
  required _FakeInvitacionGateway gateway,
}) {
  return ProviderScope(
    overrides: [
      perfilProvider.overrideWith((ref) async => perfil),
      centrosProvider.overrideWith((ref) async => _centros),
      invitacionRepositoryProvider.overrideWithValue(gateway),
    ],
    child: const MaterialApp(home: InvitarUsuarioPage()),
  );
}

Future<void> _pulsarEnviar(WidgetTester tester) async {
  final boton = find.text('Enviar invitación');
  await tester.ensureVisible(boton);
  await tester.pumpAndSettle();
  await tester.tap(boton);
  // No se usa pumpAndSettle: el indicador de progreso del botón anima sin
  // parar mientras el diálogo de éxito está abierto.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('un admin ve el formulario y envía la invitación', (
    tester,
  ) async {
    final gateway = _FakeInvitacionGateway();

    await tester.pumpWidget(_app(perfil: _admin, gateway: gateway));
    await tester.pumpAndSettle();

    expect(find.text('Suma a alguien a tu equipo'), findsOneWidget);

    final centroDropdown = tester
        .widgetList<DropdownButton<String>>(
          find.byType(DropdownButton<String>),
        )
        .last;
    final centrosVisibles =
        centroDropdown.items!.map((item) => item.value).toList();
    expect(centrosVisibles, containsAll(['centro-admin', 'centro-hijo']));
    expect(centrosVisibles, isNot(contains('centro-otro')));

    final campos = find.byType(TextFormField);
    await tester.enterText(campos.at(0), 'Ana Pérez');
    await tester.enterText(campos.at(1), 'ana@carrousel.test');

    await _pulsarEnviar(tester);

    expect(gateway.llamadas, hasLength(1));
    expect(gateway.llamadas.single['email'], 'ana@carrousel.test');
    expect(gateway.llamadas.single['nombre_completo'], 'Ana Pérez');
    expect(gateway.llamadas.single['rol'], 'empleado');
    expect(gateway.llamadas.single['centro_costo_id'], 'centro-admin');
    expect(find.text('Invitación enviada'), findsOneWidget);
  });

  testWidgets('un empleado no puede abrir el formulario', (tester) async {
    await tester.pumpWidget(
      _app(perfil: _empleado, gateway: _FakeInvitacionGateway()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Solo administradores'), findsOneWidget);
    expect(find.text('Enviar invitación'), findsNothing);
  });

  testWidgets('muestra el error de la Edge Function', (tester) async {
    final gateway = _FakeInvitacionGateway(
      error: const AppException('Ese correo ya tiene una cuenta en Carrousel.'),
    );

    await tester.pumpWidget(_app(perfil: _admin, gateway: gateway));
    await tester.pumpAndSettle();

    final campos = find.byType(TextFormField);
    await tester.enterText(campos.at(0), 'Ana Pérez');
    await tester.enterText(campos.at(1), 'ana@carrousel.test');

    await _pulsarEnviar(tester);

    expect(
      find.text('Ese correo ya tiene una cuenta en Carrousel.'),
      findsOneWidget,
    );
  });

  testWidgets('valida el correo antes de invocar la función', (tester) async {
    final gateway = _FakeInvitacionGateway();

    await tester.pumpWidget(_app(perfil: _admin, gateway: gateway));
    await tester.pumpAndSettle();

    final campos = find.byType(TextFormField);
    await tester.enterText(campos.at(0), 'Ana Pérez');
    await tester.enterText(campos.at(1), 'correo-invalido');

    await _pulsarEnviar(tester);

    expect(find.text('Escribe un correo válido.'), findsOneWidget);
    expect(gateway.llamadas, isEmpty);
  });
}
