import 'package:carrousel_app/core/supabase/supabase_provider.dart';
import 'package:carrousel_app/features/admin/data/repositories/supabase_invitacion_repository.dart';
import 'package:carrousel_app/features/admin/domain/repositories/invitacion_repository.dart';
import 'package:carrousel_app/features/admin/presentation/controllers/invitacion_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final invitacionRepositoryProvider = Provider<InvitacionRepository>(
  (ref) => SupabaseInvitacionRepository(ref.watch(supabaseProvider)),
);

final invitacionControllerProvider =
    StateNotifierProvider<InvitacionController, AsyncValue<void>>(
  (ref) => InvitacionController(ref.watch(invitacionRepositoryProvider)),
);
