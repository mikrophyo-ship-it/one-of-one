class PlatformUser {
  const PlatformUser({
    required this.id,
    required this.displayName,
    required this.email,
    required this.roles,
  });

  final String id;
  final String displayName;
  final String email;
  final List<String> roles;
}
