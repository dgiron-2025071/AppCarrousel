import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/ecosistema.dart';
import '../../data/models/perfil.dart';
import '../admin/aprobaciones_page.dart';
import '../admin/panel_admin_page.dart';
import '../dashboard/dashboard_page.dart';
import '../perfil/perfil_page.dart';
import '../solicitudes/solicitudes_page.dart';

/// Ancho a partir del cual se usa el menú lateral (computadora o tableta).
const anchoEscritorio = 900.0;

const versionApp = 'Jornadas v0.3.0 · Ecosistema v1.5.0';

class _Seccion {
  const _Seccion(this.titulo, this.etiqueta, this.icono, this.iconoActivo, this.pagina);

  final String titulo;
  final String etiqueta;
  final IconData icono;
  final IconData iconoActivo;
  final Widget pagina;
}

/// Contenedor principal. En el celular usa la barra inferior; en el
/// navegador o una tableta, el menú lateral del ecosistema (`.sidebar`).
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.perfil});

  final Perfil perfil;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _indice = 0;

  List<_Seccion> get _secciones => [
        const _Seccion('Inicio', 'Inicio', Icons.home_outlined, Icons.home_rounded, DashboardPage()),
        const _Seccion('Horas extras', 'Horas extras', Icons.more_time_outlined,
            Icons.more_time_rounded, SolicitudesPage()),
        if (widget.perfil.esAdmin)
          const _Seccion('Equipo', 'Equipo', Icons.groups_outlined, Icons.groups_rounded,
              PanelAdminPage()),
        if (widget.perfil.esAdmin)
          const _Seccion('Aprobaciones', 'Aprobar', Icons.fact_check_outlined,
              Icons.fact_check_rounded, AprobacionesPage()),
        _Seccion('Mi perfil', 'Perfil', Icons.person_outline_rounded, Icons.person_rounded,
            PerfilPage(perfil: widget.perfil)),
      ];

  @override
  Widget build(BuildContext context) {
    final secciones = _secciones;
    final indice = _indice.clamp(0, secciones.length - 1);
    final contenido = IndexedStack(
      index: indice,
      children: [for (final s in secciones) s.pagina],
    );
    final escritorio = MediaQuery.sizeOf(context).width >= anchoEscritorio;

    if (escritorio) {
      return Scaffold(
        body: Column(
          children: [
            const FranjaMarca(),
            Expanded(
              child: Row(
                children: [
                  _MenuLateral(
                    perfil: widget.perfil,
                    secciones: secciones,
                    indice: indice,
                    onSeleccion: (i) => setState(() => _indice = i),
                  ),
                  Expanded(
                    child: Scaffold(
                      appBar: AppBar(
                        toolbarHeight: 68,
                        automaticallyImplyLeading: false,
                        title: Text(secciones[indice].titulo),
                        actions: [
                          const BotonTema(),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Center(
                              child: Text(
                                widget.perfil.nombreCompleto,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ],
                      ),
                      body: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1100),
                          child: contenido,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(secciones[indice].titulo),
        bottom: const FranjaMarca(),
        actions: const [BotonTema()],
      ),
      body: contenido,
      bottomNavigationBar: NavigationBar(
        selectedIndex: indice,
        onDestinationSelected: (valor) => setState(() => _indice = valor),
        destinations: [
          for (final s in secciones)
            NavigationDestination(
              icon: Icon(s.icono),
              selectedIcon: Icon(s.iconoActivo),
              label: s.etiqueta,
            ),
        ],
      ),
    );
  }
}

/// Menú lateral azul marino del ecosistema (255 px).
class _MenuLateral extends StatelessWidget {
  const _MenuLateral({
    required this.perfil,
    required this.secciones,
    required this.indice,
    required this.onSeleccion,
  });

  final Perfil perfil;
  final List<_Seccion> secciones;
  final int indice;
  final ValueChanged<int> onSeleccion;

  @override
  Widget build(BuildContext context) {
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    const textoTenue = Color(0xFFAEBBE9);
    return Container(
      width: 255,
      color: oscuro ? const Color(0xFF0F1C48) : Marca.brandDark,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.attractions_rounded, color: Marca.brand),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Jornadas',
                            style: TextStyle(
                                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                        Text('Carrousel', style: TextStyle(color: textoTenue, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 6, 20, 8),
              child: Text(
                'MENÚ',
                style: TextStyle(
                  color: textoTenue,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .6,
                ),
              ),
            ),
            for (var i = 0; i < secciones.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                child: Material(
                  color: i == indice ? Colors.white.withAlpha(31) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onSeleccion(i),
                    child: SizedBox(
                      height: 44,
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          Icon(
                            i == indice ? secciones[i].iconoActivo : secciones[i].icono,
                            color: i == indice ? Colors.white : textoTenue,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            secciones[i].titulo,
                            style: TextStyle(
                              color: i == indice ? Colors.white : textoTenue,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${perfil.rolEtiqueta} · $versionApp',
                style: const TextStyle(color: textoTenue, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
