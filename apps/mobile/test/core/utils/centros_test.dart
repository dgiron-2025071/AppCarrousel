import 'package:carrousel_app/core/utils/centros.dart';
import 'package:carrousel_app/data/models/centro_costo.dart';
import 'package:flutter_test/flutter_test.dart';

CentroCosto centro(String id, String nombre, {String? padre}) {
  return CentroCosto(
    id: id,
    codigo: id,
    nombre: nombre,
    padreId: padre,
  );
}

void main() {
  group('subarbolDe', () {
    test('incluye la raíz y todos sus descendientes, sin hermanos', () {
      final centros = [
        centro('empresa', 'Empresa'),
        centro('parque-a', 'Parque A', padre: 'empresa'),
        centro('parque-b', 'Parque B', padre: 'empresa'),
        centro('zona-a1', 'Zona A1', padre: 'parque-a'),
        centro('zona-a2', 'Zona A2', padre: 'parque-a'),
        centro('zona-b1', 'Zona B1', padre: 'parque-b'),
      ];

      final resultado = subarbolDe(centros, 'parque-a');

      expect(
        resultado.map((centro) => centro.id),
        ['parque-a', 'zona-a1', 'zona-a2'],
      );
      expect(resultado.map((centro) => centro.id), isNot(contains('parque-b')));
      expect(resultado.map((centro) => centro.id), isNot(contains('empresa')));
    });

    test('recorre jerarquías profundas y dinámicas', () {
      final centros = [
        centro('raiz', 'Raíz'),
        centro('n1', 'Nivel 1', padre: 'raiz'),
        centro('n2', 'Nivel 2', padre: 'n1'),
        centro('n3', 'Nivel 3', padre: 'n2'),
        centro('n4', 'Nivel 4', padre: 'n3'),
      ];

      final resultado = subarbolDe(centros, 'raiz');

      expect(resultado.map((centro) => centro.id), [
        'n1',
        'n2',
        'n3',
        'n4',
        'raiz',
      ]);
    });

    test('devuelve solo la raíz cuando no tiene hijos', () {
      final centros = [centro('solo', 'Solo')];

      final resultado = subarbolDe(centros, 'solo');

      expect(resultado, hasLength(1));
      expect(resultado.single.id, 'solo');
    });

    test('devuelve vacío si la raíz no existe', () {
      final centros = [centro('otro', 'Otro')];

      expect(subarbolDe(centros, 'inexistente'), isEmpty);
    });

    test('no entra en bucle con referencias cíclicas', () {
      final centros = [
        centro('a', 'A', padre: 'b'),
        centro('b', 'B', padre: 'a'),
      ];

      final resultado = subarbolDe(centros, 'a');

      expect(resultado.map((centro) => centro.id), ['a', 'b']);
    });
  });
}
