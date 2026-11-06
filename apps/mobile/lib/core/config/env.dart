class Env {
  const Env._();

  /// Se inyectan con `--dart-define`; nunca se versionan credenciales.
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Debe coincidir con el redirect configurado en Supabase Auth y con el
  /// intent-filter de Android.
  static const oauthRedirect = 'io.supabase.carrousel://login-callback';

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
