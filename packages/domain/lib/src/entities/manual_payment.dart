class ManualPaymentOrder {
  const ManualPaymentOrder({
    required this.orderId,
    required this.itemId,
    required this.orderStatus,
    required this.paymentStatus,
    required this.paymentProvider,
    required this.paymentReference,
    required this.amountCents,
    required this.createdAt,
    this.reviewStatus,
    this.paymentMethod,
    this.payerName,
    this.payerPhone,
    this.submittedAmountCents,
    this.paidAt,
    this.transactionReference,
    this.reviewNote,
    this.submittedAt,
    this.reviewedAt,
  });

  final String orderId;
  final String itemId;
  final String orderStatus;
  final String paymentStatus;
  final String paymentProvider;
  final String paymentReference;
  final int amountCents;
  final DateTime createdAt;
  final String? reviewStatus;
  final String? paymentMethod;
  final String? payerName;
  final String? payerPhone;
  final int? submittedAmountCents;
  final DateTime? paidAt;
  final String? transactionReference;
  final String? reviewNote;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;

  bool get canSubmitProof =>
      orderStatus == 'payment_pending' &&
      (reviewStatus == null ||
          reviewStatus == 'rejected' ||
          reviewStatus == 'resubmission_requested');
}
