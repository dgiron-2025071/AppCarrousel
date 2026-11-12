import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';
import '../theme/tema_controller.dart';

/// Franja de marca de 4 px con el degradado corporativo (`.brand-strip`).
class FranjaMarca extends StatelessWidget implements PreferredSizeWidget {
  const FranjaMarca({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(4);

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(gradient: Marca.gradiente),
        child: SizedBox(height: 4, width: double.infinity),
      );
}

/// Botón ◐ para alternar claro/oscuro (`data-eco-theme-toggle`).
class BotonTema extends ConsumerWidget {
  const BotonTema({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      tooltip: oscuro ? 'Usar tema claro' : 'Usar tema oscuro',
      color: color,
      onPressed: () => ref
          .read(temaProvider.notifier)
          .alternar(Theme.of(context).brightness),
      icon: Icon(oscuro ? Icons.light_mode_outlined : Icons.contrast_rounded),
    );
  }
}

/// Encabezado de página: eyebrow, título y subtítulo (`.page-heading`).
class EncabezadoPagina extends StatelessWidget {
  const EncabezadoPagina({
    super.key,
    required this.eyebrow,
    required this.titulo,
    this.subtitulo,
  });

  final String eyebrow;
  final String titulo;
  final String? subtitulo;

  @override
  Widget build(BuildContext context) {
    final colores = ColoresCarrousel.of(context);
    final esquema = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: .6,
              color: esquema.brightness == Brightness.dark
                  ? const Color(0xFF9DB4FF)
                  : Marca.brand2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            titulo,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: colores.ink,
              height: 1.2,
            ),
          ),
          if (subtitulo != null) ...[
            const SizedBox(height: 4),
            Text(subtitulo!, style: TextStyle(fontSize: 14, color: colores.muted)),
          ],
        ],
      ),
    );
  }
}

/// Tarjeta de indicador (`.card.stat`): número grande, etiqueta y nota.
class TarjetaIndicador extends StatelessWidget {
  const TarjetaIndicador({
    super.key,
    required this.valor,
    required this.etiqueta,
    this.nota,
    this.icono,
    this.color,
    this.onTap,
  });

  final String valor;
  final String etiqueta;
  final String? nota;
  final IconData? icono;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colores = ColoresCarrousel.of(context);
    final acento = color ?? Theme.of(context).colorScheme.primary;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      etiqueta.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .4,
                        color: colores.muted,
                      ),
                    ),
                  ),
                  if (icono != null) Icon(icono, size: 18, color: acento),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                valor,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: acento,
                  height: 1.1,
                ),
              ),
              if (nota != null) ...[
                const SizedBox(height: 4),
                Text(nota!, style: TextStyle(fontSize: 12, color: colores.muted)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum TipoAviso { info, success, warning, danger }

/// Alerta en página (`.alert-info|success|warning|danger`).
class AvisoEnPagina extends StatelessWidget {
  const AvisoEnPagina({
    super.key,
    required this.mensaje,
    this.tipo = TipoAviso.info,
    this.titulo,
    this.accion,
  });

  final String mensaje;
  final TipoAviso tipo;
  final String? titulo;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final c = ColoresCarrousel.of(context);
    final (Color texto, Color fondo, IconData icono) = switch (tipo) {
      TipoAviso.info => (c.info, c.infoBg, Icons.info_outline_rounded),
      TipoAviso.success => (c.success, c.successBg, Icons.check_circle_outline_rounded),
      TipoAviso.warning => (c.warning, c.warningBg, Icons.warning_amber_rounded),
      TipoAviso.danger => (c.danger, c.dangerBg, Icons.error_outline_rounded),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: texto, width: 4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: texto, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (titulo != null)
                  Text(
                    titulo!,
                    style: TextStyle(fontWeight: FontWeight.w800, color: texto),
                  ),
                Text(mensaje, style: TextStyle(color: texto)),
                if (accion != null) ...[const SizedBox(height: 8), accion!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Aviso flotante (toast) con borde de color por tipo; cierre a los 3.6 s.
void mostrarAviso(
  BuildContext context,
  String mensaje, {
  TipoAviso tipo = TipoAviso.info,
}) {
  final c = ColoresCarrousel.of(context);
  final color = switch (tipo) {
    TipoAviso.info => c.info,
    TipoAviso.success => c.success,
    TipoAviso.warning => c.warning,
    TipoAviso.danger => c.danger,
  };
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 3600),
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: c.border),
        ),
        content: Row(
          children: [
            Container(width: 4, height: 32, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(mensaje, style: TextStyle(color: c.ink))),
          ],
        ),
      ),
    );
}

/// Confirmación del ecosistema: las acciones destructivas van en rojo y el
/// foco queda en "Cancelar" (`EcoUI.confirm`).
Future<bool> confirmar(
  BuildContext context, {
  required String pregunta,
  String? detalle,
  String aceptar = 'Confirmar',
}) async {
  final destructiva = RegExp(
    r'eliminar|borrar|quitar|desactivar|anular|rechazar|retirar',
    caseSensitive: false,
  ).hasMatch('$pregunta $aceptar');
  final c = ColoresCarrousel.of(context);
  final respuesta = await showDialog<bool>(
    context: context,
    builder: (dialogo) => AlertDialog(
      title: Text(pregunta),
      content: detalle == null ? null : Text(detalle),
      actions: [
        TextButton(
          autofocus: destructiva,
          onPressed: () => Navigator.of(dialogo).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: destructiva
              ? FilledButton.styleFrom(
                  backgroundColor: c.danger,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 44),
                )
              : FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () => Navigator.of(dialogo).pop(true),
          child: Text(aceptar),
        ),
      ],
    ),
  );
  return respuesta ?? false;
}

/// Burbuja "?" con la ayuda de la pantalla (`.help-fab` + `.help-panel`).
class BotonAyuda extends StatelessWidget {
  const BotonAyuda({
    super.key,
    required this.titulo,
    required this.introduccion,
    required this.pasos,
  });

  final String titulo;
  final String introduccion;
  final List<String> pasos;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      heroTag: 'ayuda-$titulo',
      tooltip: 'Ayuda de esta pantalla',
      shape: const CircleBorder(),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => _PanelAyuda(
          titulo: titulo,
          introduccion: introduccion,
          pasos: pasos,
        ),
      ),
      child: const Text(
        '?',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _PanelAyuda extends StatelessWidget {
  const _PanelAyuda({
    required this.titulo,
    required this.introduccion,
    required this.pasos,
  });

  final String titulo;
  final String introduccion;
  final List<String> pasos;

  @override
  Widget build(BuildContext context) {
    final c = ColoresCarrousel.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AYUDA DE ESTA PANTALLA',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: .6,
                color: c.muted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              titulo,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(introduccion, style: TextStyle(color: c.muted)),
            const SizedBox(height: 14),
            for (var i = 0; i < pasos.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: Marca.brand,
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(pasos[i])),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Text(
              '¿Necesitas más ayuda? Escribe a sistemas@carrousel.com.gt',
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
          ],
        ),
      ),
    );
  }
}
