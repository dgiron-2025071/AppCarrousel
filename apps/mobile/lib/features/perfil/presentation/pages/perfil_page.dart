import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:carrousel_app/features/auth/domain/entities/perfil.dart';
import 'package:carrousel_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:carrousel_app/features/admin/presentation/pages/invitar_usuario_page.dart';
import 'package:carrousel_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:carrousel_app/features/auth/presentation/pages/reset_password_page.dart';

class PerfilPage extends ConsumerWidget {
  const PerfilPage({super.key, required this.perfil});

  final Perfil perfil;

  String get _iniciales {
    final partes = perfil.nombreCompleto
        .trim()
        .split(RegExp(r'\s+'))
        .where((parte) => parte.isNotEmpty)
        .toList();
    if (partes.isEmpty) return '?';
    if (partes.length == 1) {
      return partes.first.substring(0, 1).toUpperCase();
    }
    return (partes[0].substring(0, 1) + partes[1].substring(0, 1))
        .toUpperCase();
  }

  Future<void> _cerrarSesion(BuildContext context, WidgetRef ref) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text(
          '¿Quieres salir de Carrousel en este dispositivo?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogo).pop(true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );

    if (confirmado == true) {
      await ref.read(authControllerProvider.notifier).cerrarSesion();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colores = Theme.of(context).colorScheme;
    final email = ref.watch(sesionActualProvider)?.email ?? '';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [colores.primary, colores.primary.withAlpha(215)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: colores.onPrimary.withAlpha(40),
                foregroundColor: colores.onPrimary,
                child: Text(
                  _iniciales,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      perfil.nombreCompleto,
                      style: TextStyle(
                        color: colores.onPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: colores.onPrimary.withAlpha(45),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        perfil.rolEtiqueta,
                        style: TextStyle(
                          color: colores.onPrimary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _Dato(
          icono: Icons.attractions_outlined,
          etiqueta: 'Centro de costo',
          valor: perfil.centroNombre ?? 'Centro asignado',
        ),
        _Dato(
          icono: Icons.mail_outline_rounded,
          etiqueta: 'Correo electrónico',
          valor: email.isEmpty ? 'No disponible' : email,
        ),
        if (perfil.esAdmin) ...[
          const SizedBox(height: 18),
          Text(
            'Administración',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: colores.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colores.outlineVariant, width: 0.7),
            ),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              leading: const Icon(Icons.person_add_alt_1_rounded),
              title: const Text('Invitar usuarios'),
              subtitle: const Text(
                'Da acceso a un empleado o administrador de tu subárbol.',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const InvitarUsuarioPage(),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        Text(
          'Seguridad',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: colores.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colores.outlineVariant, width: 0.7),
          ),
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            leading: const Icon(Icons.lock_reset_rounded),
            title: const Text('Cambiar contraseña'),
            subtitle: const Text(
              'Actualiza la clave con la que entras a Carrousel.',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ResetPasswordPage(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colores.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.verified_user_outlined, color: colores.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Tu rol, empresa y centro de costo los asigna el administrador '
                  'desde una invitación segura. No puedes cambiarlos desde la app.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colores.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: () => _cerrarSesion(context, ref),
          style: OutlinedButton.styleFrom(
            foregroundColor: colores.error,
            side: BorderSide(color: colores.error.withAlpha(120)),
          ),
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Cerrar sesión'),
        ),
        const SizedBox(height: 24),
        Center(
          child: Text(
            'Carrousel',
            style: TextStyle(
              color: colores.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({
    required this.icono,
    required this.etiqueta,
    required this.valor,
  });

  final IconData icono;
  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colores.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colores.outlineVariant, width: 0.7),
      ),
      child: Row(
        children: [
          Icon(icono, size: 20, color: colores.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  etiqueta,
                  style: TextStyle(
                    fontSize: 11,
                    color: colores.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  valor,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
