import 'package:carrousel_app/core/theme/app_theme.dart';
import 'package:carrousel_app/core/theme/theme_provider.dart';
import 'package:carrousel_app/features/auth/domain/entities/perfil.dart';
import 'package:carrousel_app/features/auth/domain/entities/rol_usuario.dart';
import 'package:carrousel_app/features/auth/domain/entities/sesion_usuario.dart';
import 'package:carrousel_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:carrousel_app/features/catalogo/domain/entities/centro_costo.dart';
import 'package:carrousel_app/features/catalogo/domain/entities/parque.dart';
import 'package:carrousel_app/features/catalogo/presentation/providers/catalogo_providers.dart';
import 'package:carrousel_app/features/horario/domain/entities/horario.dart';
import 'package:carrousel_app/features/horario/presentation/providers/horario_providers.dart';
import 'package:carrousel_app/features/jornada/domain/entities/jornada.dart';
import 'package:carrousel_app/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:carrousel_app/features/shell/presentation/pages/home_shell.dart';
import 'package:carrousel_app/features/solicitudes/domain/entities/solicitud_horas_extras.dart';
import 'package:carrousel_app/features/solicitudes/presentation/providers/solicitud_providers.dart';
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

const _sesion = SesionUsuario(id: 'empleado-id', email: 'ana@carrousel.test');

/// Las páginas del shell se construyen todas juntas en un `IndexedStack`, así
/// que se aíslan sus providers de datos para que la prueba no toque Supabase.
Widget _app({ThemeMode tema = ThemeMode.light, bool? esWeb}) {
  return ProviderScope(
    overrides: [
      temaProvider.overrideWith((ref) => tema),
      perfilProvider.overrideWith((ref) async => _empleado),
      sesionActualProvider.overrideWithValue(_sesion),
      jornadasStreamProvider.overrideWith(
        (ref) => Stream.value(const <Jornada>[]),
      ),
      parquesProvider.overrideWith((ref) async => const <Parque>[]),
      centrosProvider.overrideWith((ref) async => const <CentroCosto>[]),
      nombresPerfilesProvider.overrideWith(
        (ref) async => const <String, String>{},
      ),
      horariosEmpleadoProvider.overrideWith(
        (ref, _) async => const <Horario>[],
      ),
      solicitudesStreamProvider.overrideWith(
        (ref) => Stream.value(const <SolicitudHorasExtras>[]),
      ),
    ],
    child: Consumer(
      builder: (context, ref, _) {
        final modo = ref.watch(temaProvider);
        return MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: modo,
          home: Column(
            children: [
              Text(modo.name, key: const Key('tema-actual')),
              Expanded(
                child: HomeShell(perfil: _empleado, esWeb: esWeb),
              ),
            ],
          ),
        );
      },
    ),
  );
}

void main() {
  testWidgets('muestra el menú lateral en pantallas anchas', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
      isTrue,
    );

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Horario'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Mi horario'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('en web mantiene el menú lateral en una ventana estrecha', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(480, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(esWeb: true));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
      isFalse,
    );

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Horario'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Mi horario'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('muestra navegación inferior en pantallas estrechas', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('alterna el tema desde la barra superior', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    String temaActual() =>
        tester.widget<Text>(find.byKey(const Key('tema-actual'))).data!;

    expect(temaActual(), 'light');

    await tester.tap(find.byTooltip('Cambiar a tema oscuro'));
    await tester.pumpAndSettle();
    expect(temaActual(), 'dark');

    await tester.tap(find.byTooltip('Cambiar a tema claro'));
    await tester.pumpAndSettle();
    expect(temaActual(), 'light');
  });
}
