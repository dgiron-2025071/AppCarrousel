import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/estado_widgets.dart';
import '../../providers/app_providers.dart';
import 'horario_empleado_page.dart';

/// Personas del subárbol del admin (RLS) para editar su horario.
class EquipoPage extends ConsumerWidget {
  const EquipoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final yo = ref.watch(currentUserProvider)?.id;
    final personasAsync = ref.watch(personasProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Horarios del equipo')),
      body: personasAsync.when(
        loading: () => const CargandoWidget(mensaje: 'Cargando tu equipo...'),
        error: (_, _) => MensajeError(
          mensaje: 'No se pudo cargar tu equipo.',
          onReintentar: () => ref.invalidate(personasProvider),
        ),
        data: (personas) {
          final equipo = personas.entries
              .where((entrada) => entrada.key != yo)
              .toList()
            ..sort((a, b) => a.value.nombre.compareTo(b.value.nombre));
          if (equipo.isEmpty) {
            return const EstadoVacio(
              icono: Icons.groups_outlined,
              titulo: 'Sin personas a tu cargo',
              mensaje: 'Cuando invites empleados aparecerán aquí.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: equipo.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final entrada = equipo[i];
              return ListTile(
                leading: CircleAvatar(
                  child: Text(entrada.value.nombre.characters.first),
                ),
                title: Text(entrada.value.nombre),
                subtitle: Text(entrada.value.puesto ?? 'Sin puesto'),
                trailing: const Icon(Icons.edit_calendar_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => HorarioEmpleadoPage(
                      empleadoId: entrada.key,
                      nombre: entrada.value.nombre,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
