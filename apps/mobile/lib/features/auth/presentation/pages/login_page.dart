import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:carrousel_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:carrousel_app/features/auth/presentation/pages/forgot_password_page.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _verContrasena = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    await ref.read(authControllerProvider.notifier).iniciarSesion(
          email: _email.text,
          password: _password.text,
        );
  }

  Future<void> _google() async {
    FocusScope.of(context).unfocus();
    final abierto =
        await ref.read(authControllerProvider.notifier).iniciarConGoogle();
    if (!mounted || abierto) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudo abrir Google.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(authControllerProvider);
    final colores = Theme.of(context).colorScheme;
    final cargando = estado.isLoading;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      height: 78,
                      width: 78,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colores.primaryContainer,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Icon(
                        Icons.attractions_rounded,
                        size: 44,
                        color: colores.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'Carrousel',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Control de jornadas y horas extras',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: colores.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 36),
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
                        if (!texto.contains('@') || !texto.contains('.')) {
                          return 'Escribe un correo válido.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: !_verContrasena,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _entrar(),
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          tooltip: _verContrasena
                              ? 'Ocultar contraseña'
                              : 'Mostrar contraseña',
                          onPressed: () => setState(
                            () => _verContrasena = !_verContrasena,
                          ),
                          icon: Icon(
                            _verContrasena
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                          ),
                        ),
                      ),
                      validator: (valor) {
                        if (valor == null || valor.isEmpty) {
                          return 'Escribe tu contraseña.';
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
                      onPressed: cargando ? null : _entrar,
                      child: cargando
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.4),
                            )
                          : const Text('Iniciar sesión'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: cargando ? null : _google,
                      icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
                      label: const Text('Continuar con Google'),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: cargando
                          ? null
                          : () {
                              ref
                                  .read(authControllerProvider.notifier)
                                  .limpiarError();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const ForgotPasswordPage(),
                                ),
                              );
                            },
                      child: const Text('¿Olvidaste tu contraseña?'),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'El acceso se crea por invitación del administrador.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colores.onSurfaceVariant,
                          ),
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
