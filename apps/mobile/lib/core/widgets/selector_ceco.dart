import 'package:flutter/material.dart';

import '../../data/models/centro_costo.dart';
import '../utils/centros.dart';

/// Campo de formulario para elegir un centro de costo con buscador.
///
/// El catálogo real tiene cientos de CECO; en lugar de un desplegable se abre
/// una hoja con búsqueda por código o nombre ("057", "andaria kiddies").
class SelectorCeco extends FormField<String> {
  SelectorCeco({
    super.key,
    required List<CentroCosto> centros,
    required ValueChanged<String> onChanged,
    super.initialValue,
    String etiqueta = 'Centro de costo',
    super.validator,
  }) : super(
          builder: (estado) {
            final contexto = estado.context;
            CentroCosto? elegido;
            for (final centro in centros) {
              if (centro.id == estado.value) elegido = centro;
            }

            Future<void> abrir() async {
              final id = await showModalBottomSheet<String>(
                context: contexto,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => _HojaBusqueda(
                  centros: centros,
                  seleccionadoId: estado.value,
                ),
              );
              if (id == null) return;
              estado.didChange(id);
              onChanged(id);
            }

            return InkWell(
              onTap: abrir,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                isEmpty: elegido == null,
                decoration: InputDecoration(
                  labelText: etiqueta,
                  prefixIcon: const Icon(Icons.account_tree_outlined),
                  suffixIcon: const Icon(Icons.search_rounded),
                  errorText: estado.errorText,
                ),
                child: elegido == null
                    ? null
                    : Text(
                        elegido.etiqueta,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
            );
          },
        );
}

class _HojaBusqueda extends StatefulWidget {
  const _HojaBusqueda({required this.centros, this.seleccionadoId});

  final List<CentroCosto> centros;
  final String? seleccionadoId;

  @override
  State<_HojaBusqueda> createState() => _HojaBusquedaState();
}

class _HojaBusquedaState extends State<_HojaBusqueda> {
  String _consulta = '';

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final resultados = filtrarCentros(widget.centros, _consulta);
    final nombres = {for (final c in widget.centros) c.id: c.nombre};

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.8,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'Busca por código o nombre (ej. 057, Andaria)',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (valor) => setState(() => _consulta = valor),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${resultados.length} centros de costo',
                    style: TextStyle(
                      fontSize: 12,
                      color: colores.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: resultados.isEmpty
                    ? const Center(child: Text('Sin coincidencias.'))
                    : ListView.builder(
                        itemCount: resultados.length,
                        itemBuilder: (_, i) {
                          final centro = resultados[i];
                          final padre = nombres[centro.padreId];
                          return ListTile(
                            selected: centro.id == widget.seleccionadoId,
                            leading: SizedBox(
                              width: 64,
                              child: Text(
                                centro.codigo,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                            title: Text(centro.nombre),
                            subtitle: padre == null ? null : Text(padre),
                            onTap: () => Navigator.of(context).pop(centro.id),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
