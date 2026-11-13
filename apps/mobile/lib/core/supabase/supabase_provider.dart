import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cliente único de Supabase para toda la app.
final supabaseProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);
