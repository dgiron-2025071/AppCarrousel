/// Sesión activa del usuario, sin exponer tipos de Supabase al dominio.
class SesionUsuario {
  const SesionUsuario({required this.id, required this.email});

  final String id;
  final String email;
}
