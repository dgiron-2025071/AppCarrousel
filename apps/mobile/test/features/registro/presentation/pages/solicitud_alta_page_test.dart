import 'package:carrousel_app/core/errors/error_messages.dart';
import 'package:carrousel_app/features/auth/domain/entities/perfil.dart';
import 'package:carrousel_app/features/auth/domain/entities/sesion_usuario.dart';
import 'package:carrousel_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:carrousel_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:carrousel_app/features/registro/domain/entities/mi_registro.dart';
import 'package:carrousel_app/features/registro/domain/repositories/registro_repository.dart';
import 'package:carrousel_app/features/registro/presentation/pages/solicitud_alta_page.dart';
import 'package:carrousel_app/features/registro/presentation/providers/registro_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeRegistroRepository implements RegistroRepository {
  _FakeRegistroRepository({this.error});

  final Object? error;
  MiRegistro? registro;
  final solicitudes = <Map<String, String>>[];

  @override
  Future<MiRegistro?> miRegistro() async => registro;

  @override
  Future<String> solicitar({
    required String codigoEmpresa,
    required String nombreCompleto,
    required String puesto,
  }) async {
    solicitudes.add({
      'codigo': codigoEmpresa,
      'nombre': nombreCompleto,
      'puesto': puesto,
    });
    if (error != null) throw error!;

    registro = MiRegistro(
      id: 'r1',
      empresaId: 'e1',
      email: 'ana@carrousel.test',
      nombreCompleto: nombreCompleto,
      puesto: puesto,
      estado: EstadoMiRegistro.pendiente,
      creadoEn: DateTime(2026, 11, 16),
    );
    return 'r1';
  }
}

class _FakeAuthRepository implements AuthRepository {
  const _FakeAuthRepository({this.error});

  final Object? error;

  @override
  Stream<EventoSesion> get eventosDeSesion => const Stream.empty();

  @override
  SesionUsuario? get sesionActual =>
      const SesionUsuario(id: 'empleado-id', email: 'ana@carrousel.test');

  @override
  Future<void> iniciarSesion({
    required String email,
    required String password,
  }) async {}

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
  Future<void> refrescarSesion() async {
    if (error != null) throw error!;
  }

  @override
  Future<Perfil?> obtenerPerfil(String userId) async => null;
}

Widget _app(_FakeRegistroRepository repo, {_FakeAuthRepository? auth}) {
  return ProviderScope(
    overrides: [
      registroRepositoryProvider.overrideWithValue(repo),
      if (auth != null) authRepositoryProvider.overrideWithValue(auth),
    ],
    child: const MaterialApp(
      home: SolicitudAltaPage(
        email: 'ana@carrousel.test',
        nombreInicial: 'Ana Pérez',
      ),
    ),
  );
}

void main() {
  testWidgets('envía el alta y muestra el estado pendiente', (tester) async {
    final repo = _FakeRegistroRepository();

    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    expect(find.text('Completa tu registro'), findsOneWidget);
    expect(find.text('Ana Pérez'), findsOneWidget);

    final campos = find.byType(TextFormField);
    await tester.enterText(campos.at(1), 'CARROUSEL');
    await tester.ensureVisible(find.text('Enviar solicitud'));
    await tester.tap(find.text('Enviar solicitud'));
    await tester.pumpAndSettle();

    expect(repo.solicitudes, hasLength(1));
    expect(repo.solicitudes.single['codigo'], 'CARROUSEL');
    expect(repo.solicitudes.single['nombre'], 'Ana Pérez');
    expect(repo.solicitudes.single['puesto'], 'Especialista');
    expect(
      find.textContaining('Puesto declarado: Especialista.'),
      findsOneWidget,
    );
    expect(find.text('Solicitud en revisión'), findsOneWidget);
  });

  testWidgets('permite escribir un puesto distinto de Especialista', (
    tester,
  ) async {
    final repo = _FakeRegistroRepository();

    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Otro'));
    await tester.pumpAndSettle();

    final campos = find.byType(TextFormField);
    await tester.enterText(campos.at(1), 'Técnico de juegos');
    await tester.enterText(campos.at(2), 'CARROUSEL');
    await tester.ensureVisible(find.text('Enviar solicitud'));
    await tester.tap(find.text('Enviar solicitud'));
    await tester.pumpAndSettle();

    expect(repo.solicitudes, hasLength(1));
    expect(repo.solicitudes.single['puesto'], 'Técnico de juegos');
    expect(
      find.textContaining('Puesto declarado: Técnico de juegos.'),
      findsOneWidget,
    );
  });

  testWidgets('Otro exige escribir el puesto', (tester) async {
    final repo = _FakeRegistroRepository();

    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Otro'));
    await tester.pumpAndSettle();

    final campos = find.byType(TextFormField);
    await tester.enterText(campos.at(2), 'CARROUSEL');
    await tester.ensureVisible(find.text('Enviar solicitud'));
    await tester.tap(find.text('Enviar solicitud'));
    await tester.pumpAndSettle();

    expect(find.text('Escribe tu puesto.'), findsOneWidget);
    expect(repo.solicitudes, isEmpty);
  });

  testWidgets('traduce el código de empresa inválido', (tester) async {
    final repo = _FakeRegistroRepository(
      error: const PostgrestException(
        message: 'El código de empresa no existe o la empresa está suspendida',
        code: '23503',
      ),
    );

    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    final campos = find.byType(TextFormField);
    await tester.enterText(campos.at(1), 'NOEXISTE');
    await tester.tap(find.text('Enviar solicitud'));
    await tester.pumpAndSettle();

    expect(
      find.text('El código de empresa no existe o la empresa está suspendida.'),
      findsOneWidget,
    );
  });

  testWidgets('rehabilita Actualizar acceso aunque falle la renovación', (
    tester,
  ) async {
    final repo = _FakeRegistroRepository()
      ..registro = MiRegistro(
        id: 'r1',
        empresaId: 'e1',
        email: 'ana@carrousel.test',
        nombreCompleto: 'Ana Pérez',
        estado: EstadoMiRegistro.aprobado,
        creadoEn: DateTime(2026, 11, 16),
      );
    final auth = _FakeAuthRepository(
      error: const AppException('No se pudo refrescar la sesión.'),
    );

    await tester.pumpWidget(_app(repo, auth: auth));
    await tester.pumpAndSettle();

    expect(find.text('Actualizar acceso'), findsOneWidget);
    await tester.ensureVisible(find.text('Actualizar acceso'));
    await tester.tap(find.text('Actualizar acceso'));
    await tester.pumpAndSettle();

    expect(find.text('No se pudo refrescar la sesión.'), findsOneWidget);
    final boton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Actualizar acceso'),
    );
    expect(boton.onPressed, isNotNull, reason: 'Debe poder reintentar');
  });
}
