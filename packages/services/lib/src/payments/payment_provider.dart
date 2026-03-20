class PaymentIntentResult {
  const PaymentIntentResult({
    required this.success,
    required this.reference,
    required this.status,
  });

  final bool success;
  final String reference;
  final String status;
}

abstract class PaymentProvider {
  Future<PaymentIntentResult> charge({
    required String orderId,
    required int amount,
  });
}
