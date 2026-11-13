import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:carrousel_app/core/utils/duraciones.dart';
import 'package:carrousel_app/core/widgets/estado_widgets.dart';
import 'package:carrousel_app/features/jornada/domain/entities/jornada.dart';
import 'package:carrousel_app/features/catalogo/domain/entities/parque.dart';
import 'package:carrousel_app/features/auth/domain/entities/perfil.dart';
import 'package:carrousel_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:carrousel_app/features/catalogo/presentation/providers/catalogo_providers.dart';
import 'package:carrousel_app/features/jornada/domain/utils/jornadas.dart';
import 'package:carrousel_app/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:carrousel_app/features/jornada/presentation/pages/marcaje_page.dart';
import 'package:carrousel_app/features/solicitudes/presentation/pages/solicitud_form_page.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    _reloj = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final perfil = ref.watch(perfilProvider).valueOrNull;
    final jornadasAsync = ref.watch(jornadasStreamProvider);
    final parques = ref.watch(parquesProvider).valueOrNull ?? const <Parque>[];
    final nombresParques = {
      for (final parque in parques) parque.id: parque.nombre,
    };

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(jornadasStreamProvider);
        ref.invalidate(parquesProvider);
        await ref.read(jornadasStreamProvider.future);
      },
      child: jornadasAsync.when(
        loading: () => const CargandoWidget(mensaje: 'Cargando tus horas...'),
        error: (error, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.6,
              child: MensajeError(
                mensaje:
                    'No se pudieron cargar tus jornadas. Desliza para reintentar.',
                onReintentar: () => ref.invalidate(jornadasStreamProvider),
              ),
            ),
          ],
        ),
        data: (jornadas) => _contenido(context, perfil, jornadas, nombresParques),
      ),
    );
  }

  Widget _contenido(
    BuildContext context,
    Perfil? perfil,
    List<Jornada> jornadas,
    Map<String, String> nombresParques,
  ) {
    final ahora = DateTime.now();
    final abierta = jornadaAbiertaDe(jornadas);
    final hoy = inicioDelDia(ahora);
    final semana = inicioSemana(ahora);
    final mes = inicioMes(ahora);

    final horasHoy = _sumar(jornadas, hoy, finDelDia(ahora), ahora);
    final horasSemana = _sumar(jornadas, semana, ahora, ahora);
    final horasMes = _sumar(jornadas, mes, ahora, ahora);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Text(
          'Hola, ${perfil?.primerNombre ?? ''}',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          'Este es el resumen de tu jornada.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        _TarjetaJornada(
          abierta: abierta,
          nombreParque: abierta == null ? null : nombresParques[abierta.parqueId],
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MarcajePage()),
          ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final ancho = (constraints.maxWidth - 24) / 3;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: ancho,
                  child: _Metrica(
                    etiqueta: 'Hoy',
                    valor: formatearHorasDecimales(horasHoy),
                    unidad: 'horas',
                    icono: Icons.today_rounded,
                  ),
                ),
                SizedBox(
                  width: ancho,
                  child: _Metrica(
                    etiqueta: 'Semana',
                    valor: formatearHorasDecimales(horasSemana),
                    unidad: 'horas',
                    icono: Icons.date_range_rounded,
                  ),
                ),
                SizedBox(
                  width: ancho,
                  child: _Metrica(
                    etiqueta: 'Mes',
                    valor: formatearHorasDecimales(horasMes),
                    unidad: 'horas',
                    icono: Icons.calendar_month_rounded,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        _AccionHorasExtras(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SolicitudFormPage()),
          ),
        ),
        const SizedBox(height: 26),
        Row(
          children: [
            Text(
              'Últimos marcajes',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            Text(
              '${jornadas.length} en total',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (jornadas.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: EstadoVacio(
              icono: Icons.timer_outlined,
              titulo: 'Aún no tienes marcajes',
              mensaje:
                  'Cuando marques tu entrada aparecerá aquí tu jornada y tus horas trabajadas.',
            ),
          )
        else
          ...jornadas.take(6).map(
                (jornada) => _FilaJornada(
                  jornada: jornada,
                  nombreParque:
                      nombresParques[jornada.parqueId] ?? 'Parque',
                ),
              ),
      ],
    );
  }

  Duration _sumar(
    List<Jornada> jornadas,
    DateTime desde,
    DateTime hasta,
    DateTime ahora,
  ) {
    var total = Duration.zero;
    for (final jornada in jornadas) {
      final inicio =
          jornada.entradaEn.isAfter(desde) ? jornada.entradaEn : desde;
      final finReal = jornada.salidaEn ?? ahora;
      final fin = finReal.isBefore(hasta) ? finReal : hasta;
      if (fin.isAfter(inicio)) total += fin.difference(inicio);
    }
    return total;
  }
}

class _TarjetaJornada extends StatelessWidget {
  const _TarjetaJornada({
    required this.abierta,
    required this.nombreParque,
    required this.onPressed,
  });

  final Jornada? abierta;
  final String? nombreParque;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final enCurso = abierta != null;
    final duracion = abierta?.duracionHasta(DateTime.now());

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: enCurso
              ? [colores.primary, colores.primary.withAlpha(210)]
              : [colores.surface, colores.surfaceContainerHighest],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: enCurso
            ? null
            : Border.all(color: colores.outlineVariant, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: enCurso
                      ? colores.onPrimary.withAlpha(36)
                      : colores.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  enCurso ? Icons.timer_rounded : Icons.location_on_outlined,
                  color:
                      enCurso ? colores.onPrimary : colores.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  enCurso ? 'Jornada en curso' : 'Sin jornada activa',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: enCurso ? colores.onPrimary : colores.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            enCurso
                ? (nombreParque ?? 'Parque')
                : 'Marca tu entrada desde el parque donde trabajas.',
            style: TextStyle(
              color: enCurso
                  ? colores.onPrimary.withAlpha(225)
                  : colores.onSurfaceVariant,
            ),
          ),
          if (enCurso && duracion != null) ...[
            const SizedBox(height: 6),
            Text(
              '${formatearHora(abierta!.entradaEn)} · ${formatearDuracion(duracion)}',
              style: TextStyle(
                color: colores.onPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: enCurso
                ? FilledButton.tonalIcon(
                    onPressed: onPressed,
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Marcar salida'),
                  )
                : FilledButton.icon(
                    onPressed: onPressed,
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Marcar entrada'),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Metrica extends StatelessWidget {
  const _Metrica({
    required this.etiqueta,
    required this.valor,
    required this.unidad,
    required this.icono,
  });

  final String etiqueta;
  final String valor;
  final String unidad;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colores.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colores.outlineVariant, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 20, color: colores.primary),
          const SizedBox(height: 10),
          Text(
            valor,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          Text(
            '$etiqueta · $unidad',
            style: TextStyle(fontSize: 11, color: colores.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _AccionHorasExtras extends StatelessWidget {
  const _AccionHorasExtras({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Material(
      color: colores.secondaryContainer,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.add_alarm_rounded,
                  size: 30, color: colores.onSecondaryContainer),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Agregar horas extras',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: colores.onSecondaryContainer,
                      ),
                    ),
                    Text(
                      'Registra el apoyo en otro parque y envíalo a tu admin.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colores.onSecondaryContainer.withAlpha(200),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: colores.onSecondaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilaJornada extends StatelessWidget {
  const _FilaJornada({required this.jornada, required this.nombreParque});

  final Jornada jornada;
  final String nombreParque;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final duracion = jornada.duracionHasta(DateTime.now());
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colores.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colores.outlineVariant, width: 0.6),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: jornada.abierta
                  ? colores.primaryContainer
                  : colores.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              jornada.abierta ? Icons.play_arrow_rounded : Icons.check_rounded,
              size: 20,
              color: jornada.abierta
                  ? colores.onPrimaryContainer
                  : colores.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombreParque,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${formatearFecha(jornada.entradaEn)} · ${jornada.rangoTexto}',
                  style: TextStyle(
                    fontSize: 12,
                    color: colores.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatearDuracion(duracion),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
