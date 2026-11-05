import 'package:flutter/material.dart';

void main() {
  runApp(const CarrouselPreviewApp());
}

/// Vista previa local de los flujos de la app.
/// No usa Riverpod/Bloc ni Supabase todavía: solo demuestra la navegación
/// y las acciones principales antes de conectar el backend.
enum RolPreview { empleado, gerente }

extension RolPreviewX on RolPreview {
  String get etiqueta => switch (this) {
        RolPreview.empleado => 'Empleado',
        RolPreview.gerente => 'Gerente',
      };

  String get nombre => switch (this) {
        RolPreview.empleado => 'Ana López',
        RolPreview.gerente => 'Carlos Méndez',
      };

  String get cargo => switch (this) {
        RolPreview.empleado => 'Auxiliar de bodega',
        RolPreview.gerente => 'Gerente de centro de costo',
      };
}

class CarrouselPreviewApp extends StatelessWidget {
  const CarrouselPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Carrousel Preview',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0B5CAD),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        useMaterial3: true,
      ),
      home: const BotonesPreviewPage(),
    );
  }
}

class BotonesPreviewPage extends StatefulWidget {
  const BotonesPreviewPage({super.key});

  @override
  State<BotonesPreviewPage> createState() => _BotonesPreviewPageState();
}

class _BotonesPreviewPageState extends State<BotonesPreviewPage> {
  RolPreview _rol = RolPreview.empleado;
  String _ultimaAccion = 'Sin acciones todavía';
  String _horaAccion = '';

  bool get _esGerente => _rol == RolPreview.gerente;

  void _simular(String accion) {
    final ahora = DateTime.now();
    final hora = [
      ahora.hour,
      ahora.minute,
      ahora.second,
    ].map((valor) => valor.toString().padLeft(2, '0')).join(':');

    setState(() {
      _ultimaAccion = accion;
      _horaAccion = hora;
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(accion),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Empresa Carrousel'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Chip(
              label: const Text('PREVIEW'),
              visualDensity: VisualDensity.compact,
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TarjetaUsuario(
                rol: _rol,
                onRolChanged: (rol) => setState(() => _rol = rol),
              ),
              const SizedBox(height: 24),
              Text(
                'Acciones disponibles',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _esGerente
                    ? 'Vista de gerente: incluye funciones de supervisión.'
                    : 'Vista de empleado: marcaje y consulta personal.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              _BotonAccion(
                icono: Icons.login,
                titulo: 'Marcar entrada',
                subtitulo: 'Registra el inicio de la jornada',
                onPressed: () => _simular('Entrada registrada'),
              ),
              const SizedBox(height: 10),
              _BotonAccion(
                icono: Icons.logout,
                titulo: 'Marcar salida',
                subtitulo: 'Registra el fin de la jornada',
                onPressed: () => _simular('Salida registrada'),
                relleno: false,
              ),
              const SizedBox(height: 10),
              _BotonAccion(
                icono: Icons.my_location,
                titulo: 'Ver mi ubicación',
                subtitulo: 'Comprueba el GPS y la geocerca',
                onPressed: () => _simular('Ubicación verificada'),
                relleno: false,
              ),
              const SizedBox(height: 10),
              _BotonAccion(
                icono: Icons.history,
                titulo: 'Historial de asistencia',
                subtitulo: 'Consulta tus registros recientes',
                onPressed: () => _simular('Historial abierto'),
                relleno: false,
              ),
              if (_esGerente) ...[
                const SizedBox(height: 10),
                _BotonAccion(
                  icono: Icons.groups_outlined,
                  titulo: 'Panel gerente',
                  subtitulo: 'Revisa el equipo y las asistencias',
                  onPressed: () => _simular('Panel gerente abierto'),
                  relleno: false,
                ),
              ],
              const SizedBox(height: 24),
              _TarjetaEstado(
                ultimaAccion: _ultimaAccion,
                hora: _horaAccion,
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Prototipo local: sin Supabase, GPS ni RLS conectados.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: () => _simular('Sesión cerrada'),
                  icon: const Icon(Icons.power_settings_new),
                  label: const Text('Cerrar sesión'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TarjetaUsuario extends StatelessWidget {
  const _TarjetaUsuario({
    required this.rol,
    required this.onRolChanged,
  });

  final RolPreview rol;
  final ValueChanged<RolPreview> onRolChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  child: const Icon(Icons.person, size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rol.nombre,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        rol.cargo,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SegmentedButton<RolPreview>(
              segments: const [
                ButtonSegment(
                  value: RolPreview.empleado,
                  label: Text('Empleado'),
                ),
                ButtonSegment(
                  value: RolPreview.gerente,
                  label: Text('Gerente'),
                ),
              ],
              selected: {rol},
              onSelectionChanged: (seleccion) => onRolChanged(seleccion.first),
              showSelectedIcon: false,
            ),
          ],
        ),
      ),
    );
  }
}

class _BotonAccion extends StatelessWidget {
  const _BotonAccion({
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    required this.onPressed,
    this.relleno = true,
  });

  final IconData icono;
  final String titulo;
  final String subtitulo;
  final VoidCallback onPressed;
  final bool relleno;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final contenido = Row(
      children: [
        Icon(
          icono,
          size: 24,
          color: relleno
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.primary,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: relleno
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitulo,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: relleno
                      ? theme.colorScheme.onPrimary.withValues(alpha: 0.85)
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Icon(
          Icons.chevron_right,
          color: relleno
              ? theme.colorScheme.onPrimary.withValues(alpha: 0.85)
              : theme.colorScheme.onSurfaceVariant,
        ),
      ],
    );

    final estilo = ButtonStyle(
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
      alignment: Alignment.centerLeft,
    );

    return relleno
        ? FilledButton(
            onPressed: onPressed,
            style: estilo,
            child: contenido,
          )
        : OutlinedButton(
            onPressed: onPressed,
            style: estilo,
            child: contenido,
          );
  }
}

class _TarjetaEstado extends StatelessWidget {
  const _TarjetaEstado({
    required this.ultimaAccion,
    required this.hora,
  });

  final String ultimaAccion;
  final String hora;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tieneAccion = hora.isNotEmpty;

    return Card(
      elevation: 0,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 8,
        ),
        leading: CircleAvatar(
          backgroundColor: tieneAccion
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          child: Icon(
            tieneAccion ? Icons.check : Icons.touch_app_outlined,
            color: tieneAccion
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        title: Text(
          ultimaAccion,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          tieneAccion
              ? 'Última simulación a las $hora'
              : 'Presiona un botón para simular una función',
        ),
      ),
    );
  }
}
