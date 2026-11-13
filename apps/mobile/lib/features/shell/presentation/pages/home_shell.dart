import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:carrousel_app/features/auth/domain/entities/perfil.dart';
import 'package:carrousel_app/features/admin/presentation/pages/aprobaciones_page.dart';
import 'package:carrousel_app/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:carrousel_app/features/perfil/presentation/pages/perfil_page.dart';
import 'package:carrousel_app/features/solicitudes/presentation/pages/solicitudes_page.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.perfil});

  final Perfil perfil;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _indice = 0;

  @override
  Widget build(BuildContext context) {
    final paginas = <Widget>[
      const DashboardPage(),
      const SolicitudesPage(),
      if (widget.perfil.esAdmin) const AprobacionesPage(),
      PerfilPage(perfil: widget.perfil),
    ];
    final titulos = <String>[
      'Inicio',
      'Horas extras',
      if (widget.perfil.esAdmin) 'Aprobaciones',
      'Mi perfil',
    ];
    final indice = _indice.clamp(0, paginas.length - 1);

    return Scaffold(
      appBar: AppBar(title: Text(titulos[indice])),
      body: IndexedStack(index: indice, children: paginas),
      bottomNavigationBar: NavigationBar(
        selectedIndex: indice,
        onDestinationSelected: (valor) => setState(() => _indice = valor),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Inicio',
          ),
          const NavigationDestination(
            icon: Icon(Icons.more_time_outlined),
            selectedIcon: Icon(Icons.more_time_rounded),
            label: 'Horas extras',
          ),
          if (widget.perfil.esAdmin)
            const NavigationDestination(
              icon: Icon(Icons.fact_check_outlined),
              selectedIcon: Icon(Icons.fact_check_rounded),
              label: 'Aprobar',
            ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}
