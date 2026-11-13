import 'package:carrousel_app/features/auth/domain/entities/perfil.dart';
import 'package:carrousel_app/features/auth/domain/entities/rol_usuario.dart';

Perfil perfilDesdeMapa(Map<String, dynamic> map) {
  String? centroNombre;
  final centro = map['centros_costo'];
  if (centro is Map<String, dynamic>) {
    centroNombre = centro['nombre'] as String?;
  }
  return Perfil(
    id: map['id'] as String,
    empresaId: map['empresa_id'] as String,
    centroCostoId: map['centro_costo_id'] as String,
    rol: RolUsuario.parse(map['rol'] as String?),
    nombreCompleto: map['nombre_completo'] as String,
    centroNombre: centroNombre,
  );
}
