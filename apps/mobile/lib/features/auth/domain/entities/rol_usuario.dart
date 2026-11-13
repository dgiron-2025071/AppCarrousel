/// Roles de negocio de Carrousel.
///
/// El rol efectivo vive en `app_metadata.rol` y solo lo escribe el servidor.
/// La app lo interpreta para mostrar u ocultar funciones; nunca lo eleva.
enum RolUsuario {
  empleado('Empleado'),
  admin('Administrador');

  const RolUsuario(this.etiqueta);

  final String etiqueta;

  static RolUsuario parse(String? valor) =>
      valor == 'admin' ? RolUsuario.admin : RolUsuario.empleado;
}
