class AuthActionResult {
  const AuthActionResult({
    required this.success,
    required this.message,
    this.requiresEmailConfirmation = false,
  });

  final bool success;
  final String message;
  final bool requiresEmailConfirmation;
}
