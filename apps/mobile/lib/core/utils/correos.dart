/// Longitud máxima permitida para una dirección de correo (RFC 5321).
const int longitudMaximaCorreo = 320;

final RegExp _expresionCorreo = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// Validación de correo compartida por login, registro, recuperación e
/// invitaciones. La base y Supabase Auth siguen siendo la validación
/// definitiva; aquí solo evitamos envíos claramente inválidos.
bool correoValido(String? valor) {
  final texto = (valor ?? '').trim();
  if (texto.isEmpty || texto.length > longitudMaximaCorreo) return false;
  return _expresionCorreo.hasMatch(texto);
}
