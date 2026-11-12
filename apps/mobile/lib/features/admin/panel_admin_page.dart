import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/ecosistema.dart';
import '../../providers/app_providers.dart';
import 'equipo_page.dart';
import 'exportar_reporte.dart';
import 'centros_costo_page.dart';
import 'lugares_page.dart';
import 'incidencias_page.dart';
import 'invitar_usuario_page.dart';
import 'jornadas_equipo_page.dart';
import 'registros_page.dart';

/// Módulo de administración: indicadores del equipo y accesos a cada
/// herramienta, como el menú Administración del ecosistema.
class PanelAdminPage extends ConsumerWidget {
  const PanelAdminPage({super.key});

  void _ir(BuildContext context, Widget destino) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => destino));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumen = ref.watch(resumenAdminProvider).valueOrNull;
    final c = ColoresCarrousel.of(context);
    String n(int? valor) => valor?.toString() ?? '–';

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: const BotonAyuda(
        titulo: 'Panel del equipo',
        introduccion:
            'Aquí ves en tiempo real lo que pasa con tu equipo y llegas a cada herramienta.',
        pasos: [
          'Revisa quién está en turno y las incidencias abiertas.',
          'Aprueba los registros nuevos asignándoles centro de costo y puesto.',
          'Ajusta jornadas mal marcadas dejando el motivo.',
          'Exporta el reporte de horas extras para planilla.',
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(resumenAdminProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 92),
          children: [
            const EncabezadoPagina(
              eyebrow: 'Administración',
              titulo: 'Panel del equipo',
              subtitulo: 'Jornadas, incidencias y solicitudes de tu subárbol.',
            ),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.45,
              children: [
                TarjetaIndicador(
                  valor: n(resumen?.enTurno),
                  etiqueta: 'En turno',
                  nota: 'Jornadas abiertas',
                  icono: Icons.radio_button_checked_rounded,
                  color: c.success,
                  onTap: () => _ir(context, const JornadasEquipoPage()),
                ),
                TarjetaIndicador(
                  valor: n(resumen?.incidenciasAbiertas),
                  etiqueta: 'Incidencias',
                  nota: 'Por revisar',
                  icono: Icons.report_gmailerrorred_rounded,
                  color: c.danger,
                  onTap: () => _ir(context, const IncidenciasPage()),
                ),
                TarjetaIndicador(
                  valor: n(resumen?.solicitudesPendientes),
                  etiqueta: 'Horas extras',
                  nota: 'Pendientes de aprobar',
                  icono: Icons.more_time_rounded,
                  color: Marca.orange,
                ),
                TarjetaIndicador(
                  valor: n(resumen?.registrosPendientes),
                  etiqueta: 'Registros',
                  nota: 'Cuentas por asignar',
                  icono: Icons.person_add_alt_rounded,
                  color: Marca.violet,
                  onTap: () => _ir(context, const RegistrosPage()),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              'HERRAMIENTAS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: .6,
                color: c.muted,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  _Opcion(
                    icono: Icons.schedule_rounded,
                    titulo: 'Jornadas del equipo',
                    subtitulo: 'Últimos 14 días y ajustes con motivo',
                    onTap: () => _ir(context, const JornadasEquipoPage()),
                  ),
                  _Opcion(
                    icono: Icons.report_gmailerrorred_rounded,
                    titulo: 'Incidencias',
                    subtitulo: 'Tardanzas, salidas tempranas y GPS impreciso',
                    onTap: () => _ir(context, const IncidenciasPage()),
                  ),
                  _Opcion(
                    icono: Icons.how_to_reg_rounded,
                    titulo: 'Registros pendientes',
                    subtitulo: 'Asigna centro de costo y puesto',
                    onTap: () => _ir(context, const RegistrosPage()),
                  ),
                  _Opcion(
                    icono: Icons.edit_calendar_rounded,
                    titulo: 'Horarios del equipo',
                    subtitulo: 'Días, horas y parque de cada persona',
                    onTap: () => _ir(context, const EquipoPage()),
                  ),
                  _Opcion(
                    icono: Icons.place_rounded,
                    titulo: 'Lugares y geocercas',
                    subtitulo: 'Crear, editar o eliminar parques, oficina y bodega',
                    onTap: () => _ir(context, const LugaresPage()),
                  ),
                  _Opcion(
                    icono: Icons.account_tree_rounded,
                    titulo: 'Centros de costo',
                    subtitulo: 'Parques, áreas y sub-centros',
                    onTap: () => _ir(context, const CentrosCostoPage()),
                  ),
                  _Opcion(
                    icono: Icons.download_rounded,
                    titulo: 'Reporte de horas extras',
                    subtitulo: 'CSV con las columnas del formulario actual',
                    onTap: () => exportarReporteHorasExtras(context, ref),
                  ),
                  _Opcion(
                    icono: Icons.person_add_alt_1_rounded,
                    titulo: 'Invitar usuario',
                    subtitulo: 'Alta directa de empleado o administrador',
                    onTap: () => _ir(context, const InvitarUsuarioPage()),
                    ultimo: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Opcion extends StatelessWidget {
  const _Opcion({
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
    this.ultimo = false,
  });

  final IconData icono;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;
  final bool ultimo;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          minVerticalPadding: 12,
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icono, color: Theme.of(context).colorScheme.primary),
          ),
          title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitulo),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        ),
        if (!ultimo) const Divider(height: 1, indent: 72),
      ],
    );
  }
}
