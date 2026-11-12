import 'package:carrousel_app/core/utils/centros.dart';
import 'package:carrousel_app/data/models/centro_costo.dart';
import 'package:flutter_test/flutter_test.dart';

CentroCosto centro(String id, String nombre, {String? padre}) {
  return CentroCosto(id: id, codigo: id, nombre: nombre, padreId: padre);
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

      expect(resultado.map((centro) => centro.id), [
        'parque-a',
        'zona-a1',
        'zona-a2',
      ]);
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

  group('filtrarCentros', () {
    final catalogo = [
      const CentroCosto(id: '1', codigo: '057', nombre: 'Andaria'),
      const CentroCosto(
        id: '2',
        codigo: '057.01',
        nombre: 'Andaria Kiddies',
        padreId: '1',
      ),
      const CentroCosto(id: '3', codigo: '106', nombre: 'Mantenimiento'),
      const CentroCosto(id: '4', codigo: '105', nombre: 'Administración'),
    ];

    test('sin consulta devuelve todo ordenado por código', () {
      expect(filtrarCentros(catalogo, '  ').map((c) => c.codigo), [
        '057',
        '057.01',
        '105',
        '106',
      ]);
    });

    test('busca por código', () {
      expect(filtrarCentros(catalogo, '057.0').map((c) => c.id), ['2']);
    });

    test('todas las palabras deben coincidir, sin importar mayúsculas', () {
      expect(filtrarCentros(catalogo, 'ANDARIA kid').map((c) => c.id), ['2']);
    });

    test('ignora tildes en la consulta y en el nombre', () {
      expect(filtrarCentros(catalogo, 'administracion').map((c) => c.id), [
        '4',
      ]);
      expect(filtrarCentros(catalogo, 'mantenimiénto').map((c) => c.id), ['3']);
    });
  });

  test('la etiqueta muestra código y nombre', () {
    expect(
      const CentroCosto(
        id: '2',
        codigo: '057.01',
        nombre: 'Andaria Kiddies',
      ).etiqueta,
      '057.01 · Andaria Kiddies',
    );
    expect(
      const CentroCosto(id: 'x', codigo: '', nombre: 'Sin código').etiqueta,
      'Sin código',
    );
  });

  test('solo ofrece parques y áreas principales', () {
    final catalogo = [
      const CentroCosto(id: 'raiz', codigo: 'OPS', nombre: 'Corporación'),
      const CentroCosto(id: '1', codigo: '057', nombre: 'Andaria', padreId: 'raiz'),
      const CentroCosto(
          id: '2', codigo: '057.01', nombre: 'Andaria Kiddies', padreId: '1'),
      const CentroCosto(id: '3', codigo: '106', nombre: 'Mantenimiento', padreId: 'raiz'),
    ];
    expect(centrosPrincipales(catalogo).map((c) => c.codigo), ['057', '106']);
  });

  test('un lugar ofrece su centro, sus sub-centros y los agregados', () {
    final catalogo = [
      const CentroCosto(id: 'raiz', codigo: 'OPS', nombre: 'Corporación'),
      const CentroCosto(
          id: 'adm', codigo: '105', nombre: 'Administración', padreId: 'raiz'),
      const CentroCosto(
          id: 'rh', codigo: '105.02', nombre: 'Recursos Humanos', padreId: 'adm'),
      const CentroCosto(
          id: 'ger', codigo: '104', nombre: 'Gerencia', padreId: 'raiz'),
      const CentroCosto(id: 'and', codigo: '057', nombre: 'Andaria', padreId: 'raiz'),
    ];
    expect(
      centrosDeLugar(centroDelLugar: 'adm', extras: {'ger'}, centros: catalogo)
          .map((c) => c.codigo),
      ['105', '104', '105.02'],
    );
  });
}
