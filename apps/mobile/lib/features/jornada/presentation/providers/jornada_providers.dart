import 'package:carrousel_app/core/supabase/supabase_provider.dart';
import 'package:carrousel_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:carrousel_app/features/jornada/data/repositories/supabase_jornada_repository.dart';
import 'package:carrousel_app/features/jornada/domain/entities/jornada.dart';
import 'package:carrousel_app/features/jornada/domain/repositories/jornada_repository.dart';
import 'package:carrousel_app/features/jornada/domain/usecases/jornada_usecases.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final jornadaRepositoryProvider = Provider<JornadaRepository>(
  (ref) => SupabaseJornadaRepository(ref.watch(supabaseProvider)),
);

final marcarEntradaProvider = Provider<MarcarEntrada>(
  (ref) => MarcarEntrada(ref.watch(jornadaRepositoryProvider)),
);

final marcarSalidaProvider = Provider<MarcarSalida>(
  (ref) => MarcarSalida(ref.watch(jornadaRepositoryProvider)),
);

final jornadasStreamProvider =
    StreamProvider.autoDispose<List<Jornada>>((ref) {
  final sesion = ref.watch(sesionActualProvider);
  if (sesion == null) return const Stream.empty();
  return ObservarJornadas(ref.watch(jornadaRepositoryProvider))(sesion.id);
});
