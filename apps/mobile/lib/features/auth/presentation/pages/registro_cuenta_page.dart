import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:carrousel_app/core/utils/correos.dart';
import 'package:carrousel_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:carrousel_app/features/auth/presentation/controllers/auth_controller.dart';

/// Crea la cuenta de Supabase Auth. El perfil de negocio se solicita después,
/// con el código de empresa, desde la pantalla de cuenta sin aprovisionar.
class RegistroCuentaPage extends ConsumerStatefulWidget {
  const RegistroCuentaPage({super.key});

  @override
  ConsumerState<RegistroCuentaPage> createState() => _RegistroCuentaPageState();
}

class _RegistroCuentaPageState extends ConsumerState<RegistroCuentaPage> {
  final _formKey = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmacion = TextEditingController();
  bool _ver = false;
  bool _confirmarCorreo = false;

  @override
  void dispose() {
    _nombre.dispose();
    _email.dispose();
    _password.dispose();
    _confirmacion.dispose();
    super.dispose();
  }

  Future<void> _crear() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final resultado = await ref
        .read(authControllerProvider.notifier)
        .registrarCuenta(
          email: _email.text,
          password: _password.text,
          nombreCompleto: _nombre.text,
        );
    if (!mounted || resultado == null) return;

    if (resultado == ResultadoRegistroCuenta.sesionIniciada) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _confirmarCorreo = true);
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(authControllerProvider);
    final colores = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_confirmarCorreo ? 'Confirma tu correo' : 'Crear cuenta'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: _confirmarCorreo
                  ? _correoEnviado(context, colores)
                  : Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Crea tu cuenta y luego solicita el alta con el '
                            'código de tu empresa. Un administrador aprobará '
                            'tu acceso como empleado.',
                            style: TextStyle(color: colores.onSurfaceVariant),
                          ),
                          const SizedBox(height: 22),
                          TextFormField(
                            controller: _nombre,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.name],
                            decoration: const InputDecoration(
                              labelText: 'Nombre completo',
                              prefixIcon: Icon(Icons.badge_outlined),
                            ),
                            validator: (valor) {
                              final texto = valor?.trim() ?? '';
                              if (texto.isEmpty) {
                                return 'Escribe tu nombre completo.';
                              }
                              if (texto.length > 160) {
                                return 'Usa máximo 160 caracteres.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(
                              labelText: 'Correo electrónico',
                              prefixIcon: Icon(Icons.mail_outline_rounded),
                            ),
                            validator: (valor) {
                              final texto = valor?.trim() ?? '';
                              if (texto.isEmpty) return 'Escribe tu correo.';
                              if (!correoValido(texto)) {
                                return 'Escribe un correo válido.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _password,
                            obscureText: !_ver,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.newPassword],
                            decoration: InputDecoration(
                              labelText: 'Contraseña',
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                              ),
                              suffixIcon: IconButton(
                                tooltip: _ver
                                    ? 'Ocultar contraseña'
                                    : 'Mostrar contraseña',
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
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.newPassword],
                            onFieldSubmitted: (_) => _crear(),
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
                            const SizedBox(height: 16),
                            _BannerError(mensaje: estado.error.toString()),
                          ],
                          const SizedBox(height: 22),
                          FilledButton(
                            onPressed: estado.isLoading ? null : _crear,
                            child: estado.isLoading
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                    ),
                                  )
                                : const Text('Crear cuenta'),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _correoEnviado(BuildContext context, ColorScheme colores) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.mark_email_read_outlined, size: 64, color: colores.primary),
        const SizedBox(height: 18),
        Text(
          'Revisa tu correo',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(
          'Enviamos un enlace de confirmación a ${_email.text.trim()}. '
          'Ábrelo y luego inicia sesión: dentro de la app completarás tu '
          'solicitud con el código de empresa.',
          textAlign: TextAlign.center,
          style: TextStyle(color: colores.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Volver al inicio de sesión'),
        ),
      ],
    );
  }
}

class _BannerError extends StatelessWidget {
  const _BannerError({required this.mensaje});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colores.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: colores.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              mensaje,
              style: TextStyle(color: colores.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
