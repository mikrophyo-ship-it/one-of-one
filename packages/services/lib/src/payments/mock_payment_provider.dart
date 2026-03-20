import 'payment_provider.dart';

class MockPaymentProvider implements PaymentProvider {
  const MockPaymentProvider({this.shouldSucceed = true});

  final bool shouldSucceed;

  @override
  Future<PaymentIntentResult> charge({
    required String orderId,
    required int amount,
  }) async {
    return PaymentIntentResult(
      success: shouldSucceed,
      reference: 'mock-$orderId-$amount',
      status: shouldSucceed ? 'captured' : 'failed',
    );
  }
}
