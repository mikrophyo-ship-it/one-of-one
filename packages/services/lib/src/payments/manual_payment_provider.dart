import 'payment_provider.dart';

class ManualPaymentProvider implements PaymentProvider {
  const ManualPaymentProvider();

  @override
  String get providerKey => 'manual_transfer';
}
