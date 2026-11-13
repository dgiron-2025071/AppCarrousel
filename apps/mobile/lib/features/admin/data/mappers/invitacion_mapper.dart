import 'package:carrousel_app/features/admin/domain/entities/invitacion_usuario.dart';
import 'package:carrousel_app/features/auth/domain/entities/rol_usuario.dart';

InvitacionUsuario invitacionDesdeMapa(Map<String, dynamic> map) =>
    InvitacionUsuario(
      id: map['id'] as String,
      email: map['email'] as String? ?? '',
      rol: RolUsuario.parse(map['rol'] as String?),
      empresaId: map['empresa_id'] as String? ?? '',
      centroCostoId: map['centro_costo_id'] as String? ?? '',
      nombreCompleto: map['nombre_completo'] as String? ?? '',
      invitacionEnviada: map['invitacion_enviada'] as bool? ?? false,
    );
