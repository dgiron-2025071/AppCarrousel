import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:carrousel_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:carrousel_app/features/auth/presentation/providers/auth_providers.dart';

class ResetPasswordPage extends ConsumerStatefulWidget {
  const ResetPasswordPage({
    super.key,
    this.obligatorio = false,
    this.onCompletado,
  });

  /// True cuando el usuario llegó por el enlace de recuperación.
  final bool obligatorio;
  final VoidCallback? onCompletado;

  @override
  ConsumerState<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends ConsumerState<ResetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmacion = TextEditingController();
  bool _ver = false;

  @override
  void dispose() {
    _password.dispose();
    _confirmacion.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final ok = await ref
        .read(authControllerProvider.notifier)
        .actualizarContrasena(_password.text);
    if (!mounted || !ok) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Contraseña actualizada.')),
    );

    if (widget.onCompletado != null) {
      widget.onCompletado!();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(authControllerProvider);
    final colores = Theme.of(context).colorScheme;
    final perfil = ref.watch(perfilProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cambiar contraseña'),
        automaticallyImplyLeading: !widget.obligatorio,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.obligatorio) ...[
                    Text(
                      'Crea una nueva contraseña para ${perfil?.nombreCompleto ?? 'tu cuenta'}.',
                      style: TextStyle(color: colores.onSurfaceVariant),
                    ),
                    const SizedBox(height: 22),
                  ],
                  TextFormField(
                    controller: _password,
                    obscureText: !_ver,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'Nueva contraseña',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        tooltip: _ver ? 'Ocultar' : 'Mostrar',
                        onPressed: () => setState(() => _ver = !_ver),
                        icon: Icon(
                          _ver
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                        ),
                      ),
                    ),
                    validator: (valor) {
                      if (valor == null || valor.length < 8) {
                        return 'Usa al menos 8 caracteres.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _confirmacion,
                    obscureText: !_ver,
                    autofillHints: const [AutofillHints.newPassword],
                    onFieldSubmitted: (_) => _guardar(),
                    decoration: const InputDecoration(
                      labelText: 'Confirmar contraseña',
                      prefixIcon: Icon(Icons.lock_reset_rounded),
                    ),
                    validator: (valor) {
                      if (valor != _password.text) {
                        return 'Las contraseñas no coinciden.';
                      }
                      return null;
                    },
                  ),
                  if (estado.hasError) ...[
                    const SizedBox(height: 14),
                    Text(
                      estado.error.toString(),
                      style: TextStyle(color: colores.error),
                    ),
                  ],
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: estado.isLoading ? null : _guardar,
                    child: estado.isLoading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : const Text('Guardar contraseña'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
