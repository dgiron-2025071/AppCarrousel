import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/ecosistema.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/auth/forgot_password_page.dart';
import 'registro_page.dart';

/// Acceso con el diseño de doble panel del Ecosistema Carrousel
/// (`.auth-layout-v2`). En el celular el panel de marca va arriba.
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
    mostrarAviso(context, 'No se pudo abrir Google.', tipo: TipoAviso.danger);
  }

  void _abrir(Widget pagina) {
    ref.read(authControllerProvider.notifier).limpiarError();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => pagina));
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(authControllerProvider);
    final c = ColoresCarrousel.of(context);
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    final cargando = estado.isLoading;

    return Scaffold(
      body: DecoratedBox(
        // Fondo radial azul de .auth-body-v2.
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.7, -0.7),
            radius: 1.6,
            colors: [Color(0xFF315F9B), Color(0xFF173D75), Color(0xFF0C294F)],
            stops: [0, .34, .74],
          ),
        ),
        child: Column(
          children: [
            const FranjaMarca(),
            Expanded(
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(26),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _PanelMarca(),
                            Container(
                              color: Theme.of(context).colorScheme.surface,
                              padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      'ACCESO SEGURO',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: .8,
                                        color: oscuro
                                            ? const Color(0xFFF472B6)
                                            : const Color(0xFFC42A74),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Ingresa a Jornadas',
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800,
                                        color: c.ink,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Usa el correo con el que te registraste.',
                                      style: TextStyle(color: c.muted),
                                    ),
                                    const SizedBox(height: 18),
                                    TextFormField(
                                      controller: _email,
                                      keyboardType: TextInputType.emailAddress,
                                      textInputAction: TextInputAction.next,
                                      autofillHints: const [AutofillHints.email],
                                      decoration: const InputDecoration(
                                        labelText: 'Correo electrónico',
                                        prefixIcon:
                                            Icon(Icons.mail_outline_rounded),
                                      ),
                                      validator: (valor) {
                                        final texto = valor?.trim() ?? '';
                                        if (texto.isEmpty) {
                                          return 'Escribe tu correo.';
                                        }
                                        if (!texto.contains('@') ||
                                            !texto.contains('.')) {
                                          return 'Escribe un correo válido.';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _password,
                                      obscureText: !_verContrasena,
                                      textInputAction: TextInputAction.done,
                                      autofillHints: const [
                                        AutofillHints.password
                                      ],
                                      onFieldSubmitted: (_) => _entrar(),
                                      decoration: InputDecoration(
                                        labelText: 'Contraseña',
                                        prefixIcon: const Icon(
                                            Icons.lock_outline_rounded),
                                        suffixIcon: IconButton(
                                          tooltip: _verContrasena
                                              ? 'Ocultar contraseña'
                                              : 'Mostrar contraseña',
                                          onPressed: () => setState(
                                            () => _verContrasena =
                                                !_verContrasena,
                                          ),
                                          icon: Icon(
                                            _verContrasena
                                                ? Icons.visibility_off_rounded
                                                : Icons.visibility_rounded,
                                          ),
                                        ),
                                      ),
                                      validator: (valor) =>
                                          (valor == null || valor.isEmpty)
                                              ? 'Escribe tu contraseña.'
                                              : null,
                                    ),
                                    if (estado.hasError) ...[
                                      const SizedBox(height: 14),
                                      AvisoEnPagina(
                                        tipo: TipoAviso.danger,
                                        mensaje: estado.error.toString(),
                                      ),
                                    ],
                                    const SizedBox(height: 18),
                                    FilledButton(
                                      style: oscuro
                                          ? null
                                          : FilledButton.styleFrom(
                                              backgroundColor:
                                                  Marca.authPrimary,
                                            ),
                                      onPressed: cargando ? null : _entrar,
                                      child: cargando
                                          ? const SizedBox(
                                              height: 22,
                                              width: 22,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2.4),
                                            )
                                          : const Text('Iniciar sesión'),
                                    ),
                                    const SizedBox(height: 10),
                                    OutlinedButton.icon(
                                      onPressed: cargando ? null : _google,
                                      icon: const Icon(
                                          Icons.g_mobiledata_rounded,
                                          size: 28),
                                      label: const Text('Continuar con Google'),
                                    ),
                                    const SizedBox(height: 14),
                                    Container(
                                      padding: const EdgeInsets.fromLTRB(
                                          12, 8, 4, 8),
                                      decoration: BoxDecoration(
                                        color: c.infoBg,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.person_add_alt_1_rounded,
                                              color: c.info),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              '¿Primera vez? Solicita tu acceso '
                                              'y tu supervisor te asignará.',
                                              style: TextStyle(
                                                  color: c.info, fontSize: 13),
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: cargando
                                                ? null
                                                : () => _abrir(
                                                    const RegistroPage()),
                                            child: const Text('Registrarme'),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        TextButton(
                                          onPressed: cargando
                                              ? null
                                              : () => _abrir(
                                                  const ForgotPasswordPage()),
                                          child: const Text(
                                              '¿Olvidaste tu contraseña?'),
                                        ),
                                        const Spacer(),
                                        BotonTema(color: c.muted),
                                      ],
                                    ),
                                    Text(
                                      'Conexión cifrada. Tu ubicación solo se '
                                      'usa al marcar.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontSize: 12, color: c.muted),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Panel de marca (`.auth-brand-v2`) con círculos decorativos.
class _PanelMarca extends StatelessWidget {
  const _PanelMarca();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Marca.authPanel,
      padding: const EdgeInsets.all(22),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned(
            right: -40,
            top: -50,
            child: _Circulo(diametro: 140, color: Marca.pink),
          ),
          const Positioned(
            right: 40,
            bottom: -70,
            child: _Circulo(diametro: 110, color: Marca.yellow),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.attractions_rounded,
                  color: Marca.brand,
                  size: 32,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(30),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Text(
                  'Control de Jornadas',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Bienvenido a Carrousel',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Marca tu jornada con GPS y registra tus horas extras sin papel.',
                style: TextStyle(color: Color(0xFFD5DEF5)),
              ),
              const SizedBox(height: 14),
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Etiqueta('Geocercas'),
                  _Etiqueta('Horas extras'),
                  _Etiqueta('Tiempo real'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Circulo extends StatelessWidget {
  const _Circulo({required this.diametro, required this.color});

  final double diametro;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: diametro,
        height: diametro,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withAlpha(70),
        ),
      );
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white.withAlpha(90)),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Text(
          texto,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      );
}
