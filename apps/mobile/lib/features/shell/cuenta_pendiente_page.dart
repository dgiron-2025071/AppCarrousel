import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/error_messages.dart';
import '../../core/widgets/ecosistema.dart';
import '../../providers/app_providers.dart';
import '../auth/auth_controller.dart';

/// Sesión iniciada pero sin perfil: registro pendiente, rechazado o una
/// cuenta que nadie ha asignado todavía.
class CuentaPendientePage extends ConsumerStatefulWidget {
  const CuentaPendientePage({super.key, required this.email});

  final String email;

  @override
  ConsumerState<CuentaPendientePage> createState() =>
      _CuentaPendientePageState();
}

class _CuentaPendientePageState extends ConsumerState<CuentaPendientePage> {
  bool _revisando = false;

  /// Si el admin ya aprobó, el JWT nuevo trae empresa, centro y rol.
  Future<void> _revisar() async {
    setState(() => _revisando = true);
    try {
      await ref.read(authRepositoryProvider).refrescarSesion();
      ref.invalidate(perfilProvider);
      ref.invalidate(miRegistroProvider);
    } catch (error) {
      if (mounted) {
        mostrarAviso(context, mensajeDeError(error), tipo: TipoAviso.danger);
      }
    } finally {
      if (mounted) setState(() => _revisando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final registro = ref.watch(miRegistroProvider).valueOrNull;
    final (TipoAviso tipo, String titulo, String mensaje) = switch (registro) {
      null => (
          TipoAviso.warning,
          'Tu cuenta aún no tiene acceso',
          'Pide a tu administrador que te asigne un parque o área. '
              'Cuenta: ${widget.email}',
        ),
      final r when r.rechazado => (
          TipoAviso.danger,
          'Tu solicitud fue rechazada',
          r.motivo ?? 'Comunícate con tu supervisor.',
        ),
      final r when r.pendiente => (
          TipoAviso.info,
          'Solicitud en revisión',
          'Hola, ${r.nombre}. Tu supervisor debe asignarte centro de costo y '
              'puesto. Te avisaremos aquí cuando esté listo.',
        ),
      _ => (
          TipoAviso.success,
          '¡Tu cuenta fue aprobada!',
          'Toca "Revisar estado" para entrar.',
        ),
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Carrousel'),
        bottom: const FranjaMarca(),
        actions: const [BotonTema()],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const EncabezadoPagina(
              eyebrow: 'Estado de tu cuenta',
              titulo: 'Pendiente de asignación',
            ),
            AvisoEnPagina(tipo: tipo, titulo: titulo, mensaje: mensaje),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _revisando ? null : _revisar,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Revisar estado'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).cerrarSesion(),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Salir'),
            ),
          ],
        ),
      ),
    );
  }
}
