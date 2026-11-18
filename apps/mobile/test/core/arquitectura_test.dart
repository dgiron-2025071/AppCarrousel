import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Las dependencias entre capas solo pueden apuntar hacia dentro:
/// `presentation -> domain <- data`. Los providers son el composition root y
/// pueden instanciar repositorios concretos, pero el resto de `presentation`
/// no debe conocer `data`.
void main() {
  test('las capas no importan dependencias prohibidas', () {
    final violaciones = <String>[];
    final dominio = RegExp(
      r"package:flutter|package:flutter_riverpod|package:supabase_flutter|features/[^']+/(data|presentation)/",
    );
    final datos = RegExp(
      r"features/[^']+/presentation/|package:flutter/(material|widgets|foundation)|package:flutter_riverpod",
    );
    final presentacion = RegExp(r"features/[^']+/data/");

    for (final entidad in Directory('lib').listSync(recursive: true)) {
      if (entidad is! File || !entidad.path.endsWith('.dart')) continue;

      final ruta = entidad.path.replaceAll(r'\', '/');
      final contenido = entidad.readAsStringSync();

      if (ruta.contains('/domain/') && dominio.hasMatch(contenido)) {
        violaciones.add('domain  $ruta');
      }
      if (ruta.contains('/data/') && datos.hasMatch(contenido)) {
        violaciones.add('data    $ruta');
      }
      if (ruta.contains('/presentation/') &&
          !ruta.contains('/presentation/providers/') &&
          presentacion.hasMatch(contenido)) {
        violaciones.add('pres    $ruta');
      }
      if (ruta.startsWith('lib/core/') && contenido.contains('features/')) {
        violaciones.add('core    $ruta');
      }
    }

    expect(
      violaciones,
      isEmpty,
      reason: 'Dependencias de capas no permitidas:\n${violaciones.join('\n')}',
    );
  });
}
