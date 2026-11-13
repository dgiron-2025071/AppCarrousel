import 'package:carrousel_app/features/auth/domain/entities/rol_usuario.dart';

/// Perfil de negocio del usuario autenticado.
///
/// Es una entidad pura: no conoce Supabase ni el formato de las filas. El
/// mapeo desde la base vive en la capa `data`.
class Perfil {
  const Perfil({
    required this.id,
    required this.empresaId,
    required this.centroCostoId,
    required this.rol,
    required this.nombreCompleto,
    this.centroNombre,
  });

  final String id;
  final String empresaId;
  final String centroCostoId;
  final RolUsuario rol;
  final String nombreCompleto;
  final String? centroNombre;

  bool get esAdmin => rol == RolUsuario.admin;

  String get primerNombre {
    final partes = nombreCompleto.trim().split(RegExp(r'\s+'));
    return partes.isEmpty ? nombreCompleto : partes.first;
  }

  String get rolEtiqueta => rol.etiqueta;
}
