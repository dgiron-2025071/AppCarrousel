import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:carrousel_app/features/auth/presentation/controllers/auth_controller.dart';

class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _enviado = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await ref
        .read(authControllerProvider.notifier)
        .enviarRecuperacion(_email.text);
    if (!mounted || !ok) return;
    setState(() => _enviado = true);
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(authControllerProvider);
    final colores = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar contraseña')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: _enviado
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.mark_email_read_outlined,
                        size: 64,
                        color: colores.primary,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Revisa tu correo',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Si el correo está registrado, recibirás un enlace para crear una nueva contraseña. '
                        'Abre el enlace en este mismo dispositivo para volver a Carrousel.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colores.onSurfaceVariant),
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Volver al inicio de sesión'),
                      ),
                    ],
                  )
                : Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Escribe el correo de tu cuenta y te enviaremos un enlace para restablecer la contraseña.',
                          style: TextStyle(color: colores.onSurfaceVariant),
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.email],
                          onFieldSubmitted: (_) => _enviar(),
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
                        if (estado.hasError) ...[
                          const SizedBox(height: 14),
                          Text(
                            estado.error.toString(),
                            style: TextStyle(color: colores.error),
                          ),
                        ],
                        const SizedBox(height: 22),
                        FilledButton(
                          onPressed: estado.isLoading ? null : _enviar,
                          child: estado.isLoading
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2.4),
                                )
                              : const Text('Enviar enlace'),
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
