import 'package:carrousel_app/features/jornada/domain/utils/parques.dart';
import 'package:carrousel_app/features/jornada/domain/entities/jornada.dart';
import 'package:carrousel_app/features/catalogo/domain/entities/parque.dart';
import 'package:flutter_test/flutter_test.dart';

Parque parque(String id, {bool activo = true}) {
  return Parque(
    id: id,
    empresaId: 'empresa',
    centroCostoId: 'centro',
    codigo: id,
    nombre: 'Parque $id',
    latitud: 14.635,
    longitud: -90.507,
    radioMetros: 100,
    activo: activo,
  );
}

Jornada jornadaAbierta(String parqueId) {
  return Jornada(
    id: 'jornada',
    empresaId: 'empresa',
    empleadoId: 'empleado',
    parqueId: parqueId,
    entradaEn: DateTime(2026, 11, 10, 8),
    entradaDentroGeocerca: true,
  );
}

void main() {
  group('parquesParaEntrada', () {
    test('solo incluye parques activos', () {
      final parques = [
        parque('activo'),
        parque('inactivo', activo: false),
      ];

      expect(
        parquesParaEntrada(parques).map((p) => p.id),
        ['activo'],
      );
    });
  });

  group('parquesVisibles', () {
    test('al cerrar conserva el parque desactivado de la jornada', () {
      final parques = [
        parque('activo'),
        parque('inactivo', activo: false),
        parque('otro-inactivo', activo: false),
      ];

      final visibles = parquesVisibles(parques, jornadaAbierta('inactivo'));

      expect(visibles.map((p) => p.id), ['activo', 'inactivo']);
    });

    test('sin jornada abierta solo muestra activos', () {
      final parques = [
        parque('activo'),
        parque('inactivo', activo: false),
      ];

      expect(parquesVisibles(parques, null).map((p) => p.id), ['activo']);
    });
  });

  group('parqueDeJornada', () {
    test('encuentra el parque aunque esté desactivado', () {
      final parques = [
        parque('activo'),
        parque('inactivo', activo: false),
      ];

      expect(parqueDeJornada(parques, jornadaAbierta('inactivo'))?.id,
          'inactivo');
    });

    test('devuelve null sin jornada o si el parque no está en la lista', () {
      final parques = [parque('activo')];

      expect(parqueDeJornada(parques, null), isNull);
      expect(parqueDeJornada(parques, jornadaAbierta('otro')), isNull);
    });
  });
}
