class AuthenticityPayload {
  const AuthenticityPayload({
    required this.itemId,
    required this.serialNumber,
    required this.publicUrl,
    required this.statusLabel,
  });

  final String itemId;
  final String serialNumber;
  final String publicUrl;
  final String statusLabel;
}
