import 'package:carrousel_app/features/catalogo/domain/entities/parque.dart';
import 'package:carrousel_app/features/catalogo/presentation/providers/catalogo_providers.dart';
import 'package:carrousel_app/features/jornada/domain/entities/jornada.dart';
import 'package:carrousel_app/features/jornada/domain/repositories/jornada_repository.dart';
import 'package:carrousel_app/features/jornada/presentation/pages/marcaje_page.dart';
import 'package:carrousel_app/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _lat = 14.6349;
const _lon = -90.5069;

class _RepoFalso implements JornadaRepository {
  String? jornadaId;
  String? parqueId;
  int salidas = 0;
  int entradas = 0;

  @override
  Future<void> marcarEntrada({
    required String parqueId,
    required double latitud,
    required double longitud,
    required double precisionMetros,
  }) async {
    this.parqueId = parqueId;
    entradas++;
  }

  @override
  Future<void> marcarSalida({
    required String jornadaId,
    required double latitud,
    required double longitud,
    required double precisionMetros,
  }) async {
    this.jornadaId = jornadaId;
    salidas++;
  }

  @override
  Stream<List<Jornada>> observarJornadas(String empleadoId) =>
      const Stream.empty();
}

Parque _parque({
  required bool activo,
  double latitud = _lat,
  double longitud = _lon,
  double radioMetros = 100,
}) => Parque(
  id: 'parque-1',
  empresaId: 'empresa-id',
  centroCostoId: 'centro-id',
  codigo: 'P1',
  nombre: 'Parque Central',
  latitud: latitud,
  longitud: longitud,
  radioMetros: radioMetros,
  activo: activo,
);

Jornada _jornadaAbierta() => Jornada(
  id: 'jornada-1',
  empresaId: 'empresa-id',
  empleadoId: 'empleado-id',
  parqueId: 'parque-1',
  entradaEn: DateTime(2026, 11, 17, 8),
  entradaDentroGeocerca: true,
  entradaParqueLat: _lat,
  entradaParqueLon: _lon,
  entradaParqueRadioMetros: 100,
);

void _simularUbicacion(
  WidgetTester tester, {
  double latitud = _lat,
  double longitud = _lon,
}) {
  const canal = MethodChannel('flutter.baseflow.com/geolocator');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(canal, (
    llamada,
  ) async {
    switch (llamada.method) {
      case 'isLocationServiceEnabled':
        return true;
      case 'checkPermission':
        return 2;
      case 'getCurrentPosition':
        return {'latitude': latitud, 'longitude': longitud, 'accuracy': 10.0};
      default:
        return null;
    }
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      canal,
      null,
    ),
  );
}

Future<void> _pumpMarcaje(
  WidgetTester tester, {
  required _RepoFalso repo,
  required List<Jornada> jornadas,
  required List<Parque> parques,
  double latitud = _lat,
  double longitud = _lon,
}) async {
  _simularUbicacion(tester, latitud: latitud, longitud: longitud);
  await tester.binding.setSurfaceSize(const Size(800, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        jornadaRepositoryProvider.overrideWithValue(repo),
        jornadasStreamProvider.overrideWith((ref) => Stream.value(jornadas)),
        parquesProvider.overrideWith((ref) async => parques),
      ],
      child: const MaterialApp(home: MarcajePage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('cierra con el parque desactivado durante el turno', (
    tester,
  ) async {
    final repo = _RepoFalso();
    await _pumpMarcaje(
      tester,
      repo: repo,
      jornadas: [_jornadaAbierta()],
      parques: [_parque(activo: false)],
    );

    expect(find.text('Marcar salida'), findsOneWidget);
    expect(find.text('Parque desactivado'), findsOneWidget);
    expect(find.text('Registrar salida'), findsOneWidget);
    expect(find.text('Registrar entrada'), findsNothing);

    await tester.tap(find.text('Registrar salida'));
    await tester.pumpAndSettle();

    expect(repo.salidas, 1);
    expect(repo.jornadaId, 'jornada-1');
  });

  testWidgets('valida la salida contra la geocerca congelada al entrar', (
    tester,
  ) async {
    final repo = _RepoFalso();
    await _pumpMarcaje(
      tester,
      repo: repo,
      jornadas: [_jornadaAbierta()],
      parques: [
        // El administrador movió el parque 5 km durante el turno.
        _parque(activo: true, latitud: _lat + 0.05, longitud: _lon + 0.05),
      ],
    );

    expect(find.textContaining('Estás dentro de la geocerca'), findsOneWidget);
    await tester.tap(find.text('Registrar salida'));
    await tester.pumpAndSettle();

    expect(repo.salidas, 1);
    expect(repo.jornadaId, 'jornada-1');
  });

  testWidgets('rechaza la salida fuera de la geocerca congelada', (
    tester,
  ) async {
    final repo = _RepoFalso();
    await _pumpMarcaje(
      tester,
      repo: repo,
      jornadas: [_jornadaAbierta()],
      parques: [_parque(activo: true)],
      // El empleado se alejó del parque donde entró.
      latitud: _lat + 0.05,
      longitud: _lon + 0.05,
    );

    expect(find.textContaining('Acércate para poder marcar.'), findsOneWidget);
    final boton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Registrar salida'),
    );
    expect(boton.onPressed, isNull, reason: 'Fuera de geocerca no se habilita');

    await tester.tap(find.text('Registrar salida'));
    await tester.pumpAndSettle();

    expect(repo.salidas, 0);
  });

  testWidgets('sin jornada no ofrece un parque desactivado para entrar', (
    tester,
  ) async {
    final repo = _RepoFalso();
    await _pumpMarcaje(
      tester,
      repo: repo,
      jornadas: const [],
      parques: [_parque(activo: false)],
    );

    expect(find.text('Sin parques activos'), findsOneWidget);
    expect(find.text('Registrar entrada'), findsNothing);
    expect(repo.entradas, 0);
  });
}
