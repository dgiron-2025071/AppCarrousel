import 'package:carrousel_app/features/auth/domain/entities/perfil.dart';
import 'package:carrousel_app/features/auth/domain/entities/rol_usuario.dart';
import 'package:carrousel_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:carrousel_app/features/configuracion/domain/entities/configuracion_empresa.dart';
import 'package:carrousel_app/features/configuracion/domain/repositories/configuracion_repository.dart';
import 'package:carrousel_app/features/configuracion/presentation/pages/configuracion_empresa_page.dart';
import 'package:carrousel_app/features/configuracion/presentation/providers/configuracion_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _admin = Perfil(
  id: 'admin-id',
  empresaId: 'empresa-id',
  centroCostoId: 'centro-id',
  rol: RolUsuario.admin,
  nombreCompleto: 'Admin Carrousel',
);

class _FakeConfiguracion implements ConfiguracionRepository {
  _FakeConfiguracion();

  ConfiguracionEmpresa config = const ConfiguracionEmpresa(
    id: 'empresa-id',
    nombre: 'Carrousel',
    zonaHoraria: 'America/Guatemala',
    gpsPrecisionMaximaMetros: 100,
  );
  String? zonaGuardada;
  int? gpsGuardado;

  void actualizar({
    required String zonaHoraria,
    required int gpsPrecisionMaximaMetros,
  }) {
    config = ConfiguracionEmpresa(
      id: config.id,
      nombre: config.nombre,
      zonaHoraria: zonaHoraria,
      gpsPrecisionMaximaMetros: gpsPrecisionMaximaMetros,
    );
  }

  @override
  Future<ConfiguracionEmpresa> cargar(String empresaId) async => config;

  @override
  Future<void> guardar({
    required String empresaId,
    required String zonaHoraria,
    required int gpsPrecisionMaximaMetros,
  }) async {
    zonaGuardada = zonaHoraria;
    gpsGuardado = gpsPrecisionMaximaMetros;
  }
}

Widget _app(_FakeConfiguracion repo) {
  return ProviderScope(
    overrides: [
      perfilProvider.overrideWith((ref) async => _admin),
      configuracionRepositoryProvider.overrideWithValue(repo),
    ],
    child: const MaterialApp(home: Scaffold(body: ConfiguracionEmpresaPage())),
  );
}

void main() {
  testWidgets('carga la configuración actual de la empresa', (tester) async {
    final repo = _FakeConfiguracion();

    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    expect(find.text('Configuración de la empresa'), findsOneWidget);
    expect(find.text('Carrousel'), findsOneWidget);
    expect(find.text('America/Guatemala'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
  });

  testWidgets('guarda zona horaria y umbral de GPS', (tester) async {
    final repo = _FakeConfiguracion();

    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    final campos = find.byType(TextFormField);
    await tester.enterText(campos.at(0), 'America/Mexico_City');
    await tester.enterText(campos.at(1), '50');
    await tester.tap(find.text('Guardar configuración'));
    await tester.pumpAndSettle();

    expect(repo.zonaGuardada, 'America/Mexico_City');
    expect(repo.gpsGuardado, 50);
  });

  testWidgets('valida el mínimo del umbral antes de guardar', (tester) async {
    final repo = _FakeConfiguracion();

    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(1), '5');
    await tester.tap(find.text('Guardar configuración'));
    await tester.pumpAndSettle();

    expect(find.text('Usa un valor entre 10 y 1000 metros.'), findsOneWidget);
    expect(repo.zonaGuardada, isNull);
  });

  testWidgets('valida el máximo del umbral antes de guardar', (tester) async {
    final repo = _FakeConfiguracion();

    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(1), '1001');
    await tester.tap(find.text('Guardar configuración'));
    await tester.pumpAndSettle();

    expect(find.text('Usa un valor entre 10 y 1000 metros.'), findsOneWidget);
    expect(repo.zonaGuardada, isNull);
  });

  testWidgets('rechaza una zona IANA inexistente', (tester) async {
    final repo = _FakeConfiguracion();

    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Zona/Invalida');
    await tester.tap(find.text('Guardar configuración'));
    await tester.pumpAndSettle();

    expect(
      find.text('Usa una zona IANA válida, por ejemplo America/Guatemala.'),
      findsOneWidget,
    );
    expect(repo.zonaGuardada, isNull);
  });

  testWidgets('los controladores siguen al provider al recargarse', (
    tester,
  ) async {
    final repo = _FakeConfiguracion();

    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    repo.actualizar(
      zonaHoraria: 'America/Mexico_City',
      gpsPrecisionMaximaMetros: 50,
    );
    final contexto = tester.element(find.byType(ConfiguracionEmpresaPage));
    ProviderScope.containerOf(contexto)
        .invalidate(configuracionEmpresaProvider(_admin.empresaId));
    await tester.pumpAndSettle();

    final campos = tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .toList();
    expect(campos[0].controller?.text, 'America/Mexico_City');
    expect(campos[1].controller?.text, '50');
  });
}
