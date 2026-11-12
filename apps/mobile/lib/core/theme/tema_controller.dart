import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Misma clave que las apps web del ecosistema (`localStorage`).
const claveTema = 'carrousel-theme';

/// Tema elegido por el usuario; sigue al sistema hasta que lo cambie.
class TemaController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _cargar();
    return ThemeMode.system;
  }

  Future<void> _cargar() async {
    try {
      final guardado = (await SharedPreferences.getInstance()).getString(claveTema);
      if (guardado == 'dark') state = ThemeMode.dark;
      if (guardado == 'light') state = ThemeMode.light;
    } catch (_) {
      // Sin almacenamiento se usa el tema del sistema.
    }
  }

  /// Alterna claro/oscuro (botón ◐ del ecosistema) y lo recuerda.
  Future<void> alternar(Brightness actual) async {
    state = actual == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
    try {
      await (await SharedPreferences.getInstance())
          .setString(claveTema, state == ThemeMode.dark ? 'dark' : 'light');
    } catch (_) {}
  }
}

final temaProvider =
    NotifierProvider<TemaController, ThemeMode>(TemaController.new);
