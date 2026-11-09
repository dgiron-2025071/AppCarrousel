/// Resultado de una invitación creada por un administrador.
///
/// La Edge Function `invitar-usuario` ya creó el usuario en Auth, envió el
/// correo y escribió los claims en `app_metadata`. La app solo refleja la
/// respuesta para confirmar el alcance asignado.
class InvitacionUsuario {
  const InvitacionUsuario({
    required this.id,
    required this.email,
    required this.rol,
    required this.empresaId,
    required this.centroCostoId,
    required this.nombreCompleto,
    required this.invitacionEnviada,
  });

  final String id;
  final String email;
  final String rol;
  final String empresaId;
  final String centroCostoId;
  final String nombreCompleto;
  final bool invitacionEnviada;

  String get rolEtiqueta => rol == 'admin' ? 'Administrador' : 'Empleado';

  factory InvitacionUsuario.fromMap(Map<String, dynamic> map) {
    return InvitacionUsuario(
      id: map['id'] as String,
      email: map['email'] as String? ?? '',
      rol: map['rol'] as String? ?? 'empleado',
      empresaId: map['empresa_id'] as String? ?? '',
      centroCostoId: map['centro_costo_id'] as String? ?? '',
      nombreCompleto: map['nombre_completo'] as String? ?? '',
      invitacionEnviada: map['invitacion_enviada'] as bool? ?? false,
    );
  }
}
