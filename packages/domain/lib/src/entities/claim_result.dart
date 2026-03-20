class ClaimResult {
  const ClaimResult({
    required this.success,
    required this.message,
    this.newState,
  });

  final bool success;
  final String message;
  final String? newState;
}
