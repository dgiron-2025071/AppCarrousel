import 'package:carrousel_app/core/theme/theme_provider.dart';
import 'package:carrousel_app/features/auth/domain/entities/perfil.dart';
import 'package:carrousel_app/features/auth/domain/entities/rol_usuario.dart';
import 'package:carrousel_app/features/auth/domain/entities/sesion_usuario.dart';
import 'package:carrousel_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:carrousel_app/features/perfil/presentation/pages/perfil_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _admin = Perfil(
  id: 'admin-id',
  empresaId: 'empresa-id',
  centroCostoId: 'centro-id',
  rol: RolUsuario.admin,
  nombreCompleto: 'Ana Pérez',
  centroNombre: 'Centro Central',
);

const _empleado = Perfil(
  id: 'empleado-id',
  empresaId: 'empresa-id',
  centroCostoId: 'centro-id',
  rol: RolUsuario.empleado,
  nombreCompleto: 'Luis Gómez',
);

const _sesion = SesionUsuario(id: 'admin-id', email: 'ana@carrousel.test');

Widget _app(Perfil perfil) {
  return ProviderScope(
    overrides: [
      sesionActualProvider.overrideWithValue(_sesion),
      temaProvider.overrideWith((ref) => ThemeMode.light),
    ],
    child: MaterialApp(
      home: Scaffold(body: PerfilPage(perfil: perfil)),
    ),
  );
}

void main() {
  testWidgets('muestra identidad, centro y correo de la sesión', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_admin));
    await tester.pumpAndSettle();

    expect(find.text('AP'), findsOneWidget);
    expect(find.text('Ana Pérez'), findsOneWidget);
    expect(find.text('Administrador'), findsOneWidget);
    expect(find.text('Centro Central'), findsOneWidget);
    expect(find.text('ana@carrousel.test'), findsOneWidget);
  });

  testWidgets('solo un admin ve la opción de invitar usuarios', (tester) async {
    await tester.pumpWidget(_app(_empleado));
    await tester.pumpAndSettle();

    expect(find.text('Empleado'), findsOneWidget);
    expect(find.text('Invitar usuarios'), findsNothing);
  });
}
