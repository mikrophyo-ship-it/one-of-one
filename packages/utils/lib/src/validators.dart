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
