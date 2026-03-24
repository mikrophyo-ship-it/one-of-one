import 'payment_provider.dart';

class StripePaymentProvider implements PaymentProvider {
  const StripePaymentProvider();

  @override
  String get providerKey => 'stripe';
}
