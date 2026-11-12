import 'package:flutter/material.dart';

/// Paleta del Ecosistema Carrousel v1.5.0 (misma que helpdesk-carrousel y
/// el resto de aplicaciones web), llevada a Material 3.
class Marca {
  const Marca._();

  static const brand = Color(0xFF213A8F);
  static const brandDark = Color(0xFF15255D);
  static const brand2 = Color(0xFF2D4DB1);
  static const blue = Color(0xFF0D6EFD);
  static const violet = Color(0xFF6B46C1);
  static const pink = Color(0xFFE62E7C);
  static const orange = Color(0xFFF28B24);
  static const yellow = Color(0xFFF4C430);

  /// Fondo del panel de marca del acceso (`.auth-brand-v2`).
  static const authPanel = Color(0xFF123563);
  static const authPrimary = Color(0xFF173D75);

  /// Degradado corporativo de la franja superior (`--gradient`).
  static const gradiente = LinearGradient(
    colors: [brand, violet, pink, orange, yellow],
    stops: [0, .28, .52, .76, 1],
  );
}

/// Colores de estado y superficies que Material no trae con este nombre.
@immutable
class ColoresCarrousel extends ThemeExtension<ColoresCarrousel> {
  const ColoresCarrousel({
    required this.ink,
    required this.muted,
    required this.border,
    required this.danger,
    required this.dangerBg,
    required this.success,
    required this.successBg,
    required this.warning,
    required this.warningBg,
    required this.info,
    required this.infoBg,
  });

  final Color ink;
  final Color muted;
  final Color border;
  final Color danger;
  final Color dangerBg;
  final Color success;
  final Color successBg;
  final Color warning;
  final Color warningBg;
  final Color info;
  final Color infoBg;

  static const claro = ColoresCarrousel(
    ink: Color(0xFF1F2937),
    muted: Color(0xFF667085),
    border: Color(0xFFD0D5DD),
    danger: Color(0xFFB42318),
    dangerBg: Color(0xFFFEF3F2),
    success: Color(0xFF067647),
    successBg: Color(0xFFECFDF3),
    warning: Color(0xFF9A6700),
    warningBg: Color(0xFFFFFAEB),
    info: Color(0xFF175CD3),
    infoBg: Color(0xFFEFF8FF),
  );

  static const oscuro = ColoresCarrousel(
    ink: Color(0xFFF5F7FB),
    muted: Color(0xFFAEB8CA),
    border: Color(0xFF2C3850),
    danger: Color(0xFFF97066),
    dangerBg: Color(0xFF351B20),
    success: Color(0xFF47CD89),
    successBg: Color(0xFF113226),
    warning: Color(0xFFFDB022),
    warningBg: Color(0xFF332B17),
    info: Color(0xFF84CAFF),
    infoBg: Color(0xFF142743),
  );

  static ColoresCarrousel of(BuildContext context) =>
      Theme.of(context).extension<ColoresCarrousel>() ?? claro;

  @override
  ColoresCarrousel copyWith() => this;

  @override
  ColoresCarrousel lerp(ColoresCarrousel? other, double t) =>
      t < .5 ? this : (other ?? this);
}

class AppTheme {
  const AppTheme._();

  static ThemeData get light => _tema(
        brillo: Brightness.light,
        fondo: const Color(0xFFEEF2F7),
        tarjeta: Colors.white,
        primario: Marca.brand,
        colores: ColoresCarrousel.claro,
      );

  static ThemeData get dark => _tema(
        brillo: Brightness.dark,
        fondo: const Color(0xFF0E1526),
        tarjeta: const Color(0xFF172033),
        primario: const Color(0xFF7FA7FF),
        colores: ColoresCarrousel.oscuro,
      );

  static ThemeData _tema({
    required Brightness brillo,
    required Color fondo,
    required Color tarjeta,
    required Color primario,
    required ColoresCarrousel colores,
  }) {
    final oscuro = brillo == Brightness.dark;
    final esquema = ColorScheme.fromSeed(
      seedColor: Marca.brand,
      brightness: brillo,
    ).copyWith(
      primary: primario,
      onPrimary: oscuro ? const Color(0xFF0E1526) : Colors.white,
      primaryContainer: oscuro ? const Color(0xFF1E2C55) : const Color(0xFFE3E9FB),
      onPrimaryContainer: oscuro ? const Color(0xFFDCE4FF) : Marca.brandDark,
      secondary: Marca.violet,
      tertiary: Marca.pink,
      secondaryContainer: colores.infoBg,
      onSecondaryContainer: colores.info,
      error: colores.danger,
      errorContainer: colores.dangerBg,
      onErrorContainer: colores.danger,
      surface: tarjeta,
      onSurface: colores.ink,
      onSurfaceVariant: colores.muted,
      surfaceContainerHighest: oscuro ? const Color(0xFF1D283E) : const Color(0xFFF2F4F7),
      outline: colores.border,
      outlineVariant: colores.border,
    );

    final radio10 = BorderRadius.circular(10);
    final borde = OutlineInputBorder(
      borderRadius: radio10,
      borderSide: BorderSide(color: colores.border),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brillo,
      colorScheme: esquema,
      scaffoldBackgroundColor: fondo,
      extensions: [colores],
      textTheme: ThemeData(brightness: brillo).textTheme.apply(
            bodyColor: colores.ink,
            displayColor: colores.ink,
          ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: tarjeta,
        foregroundColor: colores.ink,
        surfaceTintColor: Colors.transparent,
        shape: Border(bottom: BorderSide(color: colores.border)),
        titleTextStyle: TextStyle(
          color: colores.ink,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        color: tarjeta,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colores.border),
        ),
      ),
      dividerTheme: DividerThemeData(color: colores.border, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tarjeta,
        border: borde,
        enabledBorder: borde,
        focusedBorder: OutlineInputBorder(
          borderRadius: radio10,
          borderSide: BorderSide(color: primario, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radio10,
          borderSide: BorderSide(color: colores.danger, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radio10,
          borderSide: BorderSide(color: colores.danger, width: 1.6),
        ),
        // 48 px de alto, igual que .form-control.
        constraints: const BoxConstraints(minHeight: 48),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          backgroundColor: primario,
          foregroundColor: esquema.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: radio10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          foregroundColor: primario,
          side: BorderSide(color: primario.withAlpha(140)),
          shape: RoundedRectangleBorder(borderRadius: radio10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primario,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (estados) => estados.contains(WidgetState.selected) ? primario : null,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: tarjeta,
        surfaceTintColor: Colors.transparent,
        indicatorColor: esquema.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colores.ink),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: oscuro ? const Color(0xFF1D283E) : Marca.brandDark,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tarjeta,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: Marca.brand,
        foregroundColor: Colors.white,
      ),
    );
  }
}
