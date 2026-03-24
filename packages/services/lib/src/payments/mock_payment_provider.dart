import 'payment_provider.dart';

class MockPaymentProvider implements PaymentProvider {
  const MockPaymentProvider({this.shouldSucceed = true});

  final bool shouldSucceed;

  @override
  String get providerKey => shouldSucceed ? 'mock_provider' : 'mock_failure';
}
