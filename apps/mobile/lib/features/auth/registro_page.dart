import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/error_messages.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ecosistema.dart';
import '../../providers/app_providers.dart';

/// Registro propio, como en control-jornadas-carrousel: la persona crea su
/// cuenta con el código de su empresa y espera a que un admin la asigne.
class RegistroPage extends ConsumerStatefulWidget {
  const RegistroPage({super.key});

  @override
  ConsumerState<RegistroPage> createState() => _RegistroPageState();
}

class _RegistroPageState extends ConsumerState<RegistroPage> {
  final _formKey = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _telefono = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _empresa = TextEditingController(text: 'CARR');
  bool _enviando = false;
  bool _ver = false;
  String? _confirmarCorreo;

  @override
  void dispose() {
    for (final c in [_nombre, _telefono, _email, _password, _empresa]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _registrar() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _enviando = true);
    try {
      final pideConfirmacion =
          await ref.read(authRepositoryProvider).registrarse(
                email: _email.text,
                password: _password.text,
                nombre: _nombre.text,
                telefono: _telefono.text,
                empresaCodigo: _empresa.text,
              );
      if (!mounted) return;
      if (pideConfirmacion) {
        setState(() {
          _enviando = false;
          _confirmarCorreo = _email.text.trim();
        });
      } else {
        // Con sesión abierta, RootGate muestra la cuenta pendiente.
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _enviando = false);
      mostrarAviso(context, mensajeDeError(error), tipo: TipoAviso.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ColoresCarrousel.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear cuenta'),
        bottom: const FranjaMarca(),
        actions: const [BotonTema()],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: _confirmarCorreo != null
                  ? _RevisaTuCorreo(email: _confirmarCorreo!)
                  : Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const EncabezadoPagina(
                            eyebrow: 'Registro de colaborador',
                            titulo: 'Solicita tu acceso',
                            subtitulo:
                                'Tu cuenta quedará pendiente hasta que tu supervisor '
                                'te asigne parque o área y puesto.',
                          ),
                          TextFormField(
                            controller: _nombre,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Nombre completo',
                              prefixIcon: Icon(Icons.badge_outlined),
                            ),
                            validator: (v) => (v?.trim().length ?? 0) < 3
                                ? 'Escribe tu nombre completo.'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _telefono,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Teléfono',
                              prefixIcon: Icon(Icons.phone_outlined),
                            ),
                            validator: (v) => (v?.trim().length ?? 0) < 8
                                ? 'Escribe un teléfono de 8 dígitos.'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Correo electrónico',
                              prefixIcon: Icon(Icons.mail_outline_rounded),
                            ),
                            validator: (v) {
                              final t = v?.trim() ?? '';
                              return t.contains('@') && t.contains('.')
                                  ? null
                                  : 'Escribe un correo válido.';
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _password,
                            obscureText: !_ver,
                            decoration: InputDecoration(
                              labelText: 'Contraseña (mínimo 8 caracteres)',
                              prefixIcon: const Icon(Icons.lock_outline_rounded),
                              suffixIcon: IconButton(
                                onPressed: () => setState(() => _ver = !_ver),
                                icon: Icon(_ver
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded),
                              ),
                            ),
                            validator: (v) => (v?.length ?? 0) < 8
                                ? 'Usa al menos 8 caracteres.'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _empresa,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Código de empresa',
                              helperText: 'Te lo da Recursos Humanos o tu supervisor.',
                              prefixIcon: Icon(Icons.apartment_rounded),
                            ),
                            validator: (v) => (v?.trim().isEmpty ?? true)
                                ? 'Escribe el código de tu empresa.'
                                : null,
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _enviando ? null : _registrar,
                            child: _enviando
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.4),
                                  )
                                : const Text('Solicitar acceso'),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Tus datos solo se usan para el control de jornadas.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: c.muted),
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

class _RevisaTuCorreo extends StatelessWidget {
  const _RevisaTuCorreo({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const EncabezadoPagina(
          eyebrow: 'Registro enviado',
          titulo: 'Confirma tu correo',
        ),
        AvisoEnPagina(
          tipo: TipoAviso.success,
          mensaje:
              'Enviamos un enlace a $email. Ábrelo para confirmar tu cuenta y '
              'luego inicia sesión. Tu supervisor recibirá tu solicitud.',
        ),
        const SizedBox(height: 18),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Volver al inicio de sesión'),
        ),
      ],
    );
  }
}
