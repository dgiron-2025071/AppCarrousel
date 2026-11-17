import 'package:carrousel_app/features/auth/domain/entities/perfil.dart';
import 'package:carrousel_app/features/auth/domain/entities/sesion_usuario.dart';
import 'package:carrousel_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:carrousel_app/features/auth/presentation/pages/login_page.dart';
import 'package:carrousel_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthRepository implements AuthRepository {
  final correos = <String>[];

  @override
  Stream<EventoSesion> get eventosDeSesion => const Stream.empty();

  @override
  SesionUsuario? get sesionActual => null;

  @override
  Future<void> iniciarSesion({
    required String email,
    required String password,
  }) async {
    correos.add(email);
  }

  @override
  Future<ResultadoRegistroCuenta> registrarCuenta({
    required String email,
    required String password,
    required String nombreCompleto,
  }) async => ResultadoRegistroCuenta.confirmarCorreo;

  @override
  Future<bool> iniciarConGoogle() async => true;

  @override
  Future<void> enviarRecuperacion(String email) async {}

  @override
  Future<void> actualizarContrasena(String password) async {}

  @override
  Future<void> cerrarSesion() async {}

  @override
  Future<void> refrescarSesion() async {}

  @override
  Future<Perfil?> obtenerPerfil(String userId) async => null;
}

Widget _app(_FakeAuthRepository repo) {
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(repo)],
    child: const MaterialApp(home: LoginPage()),
  );
}

void main() {
  testWidgets('rechaza un correo inválido antes de llamar a Auth', (
    tester,
  ) async {
    final repo = _FakeAuthRepository();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    final campos = find.byType(TextFormField);
    await tester.enterText(campos.at(0), 'ana@@correo.com');
    await tester.enterText(campos.at(1), 'contrasena123');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(find.text('Escribe un correo válido.'), findsOneWidget);
    expect(repo.correos, isEmpty);
  });

  testWidgets('inicia sesión con un correo válido', (tester) async {
    final repo = _FakeAuthRepository();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    final campos = find.byType(TextFormField);
    await tester.enterText(campos.at(0), 'ana@correo.com');
    await tester.enterText(campos.at(1), 'contrasena123');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(repo.correos, ['ana@correo.com']);
  });
}
