class MarketplaceActionResult<T> {
  const MarketplaceActionResult({
    required this.success,
    required this.message,
    this.data,
  });

  final bool success;
  final String message;
  final T? data;
}
