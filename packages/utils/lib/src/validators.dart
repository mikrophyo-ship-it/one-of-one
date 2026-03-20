String? validatePassword(String value) {
  if (value.trim().length < 8) {
    return 'Password must be at least 8 characters.';
  }
  return null;
}

String? validateUsername(String value) {
  final String normalized = value.trim();
  final RegExp pattern = RegExp(r'^[a-zA-Z0-9_]{3,24}$');
  if (!pattern.hasMatch(normalized)) {
    return 'Username must be 3-24 letters, numbers, or underscores.';
  }
  return null;
}

String? validateEmail(String value) {
  if (value.trim().isEmpty || !value.contains('@')) {
    return 'Enter a valid email address.';
  }
  return null;
}

String? validateRequired(String value, {required String field}) {
  if (value.trim().isEmpty) {
    return '$field is required.';
  }
  return null;
}
