import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env.dart';
import 'core/theme/app_theme.dart';
import 'features/shell/root_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');

  Object? initError;

  // Sin credenciales la app muestra una pantalla de configuración; no se debe
  // intentar inicializar Supabase con una URL vacía.
  if (Env.isConfigured) {
    try {
      await Supabase.initialize(
        url: Env.supabaseUrl,
        publishableKey: Env.supabaseAnonKey,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
        ),
      );
    } catch (error) {
      initError = error;
    }
  }

  runApp(
    ProviderScope(
      child: CarrouselApp(initError: initError),
    ),
  );
}

class CarrouselApp extends StatelessWidget {
  const CarrouselApp({super.key, this.initError});

  final Object? initError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Carrousel',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('es'),
      supportedLocales: const [Locale('es'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: RootGate(initError: initError),
    );
  }
}
