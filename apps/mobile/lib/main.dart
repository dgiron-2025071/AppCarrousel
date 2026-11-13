import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:carrousel_app/app/carrousel_app.dart';
import 'package:carrousel_app/core/config/env.dart';

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
