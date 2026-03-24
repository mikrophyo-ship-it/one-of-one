class Order {
  const Order({
    required this.id,
    required this.itemId,
    required this.buyerUserId,
    required this.amount,
    required this.paymentCaptured,
    this.orderStatus = 'payment_pending',
    this.paymentStatus = 'pending',
    this.shipmentStatus,
    this.deliveryConfirmedAt,
    this.reviewWindowClosesAt,
    this.payoutReleasedAt,
  });

  final String id;
  final String itemId;
  final String buyerUserId;
  final int amount;
  final bool paymentCaptured;
  final String orderStatus;
  final String paymentStatus;
  final String? shipmentStatus;
  final DateTime? deliveryConfirmedAt;
  final DateTime? reviewWindowClosesAt;
  final DateTime? payoutReleasedAt;

  bool get deliverySatisfied => deliveryConfirmedAt != null;

  bool get reviewWindowSatisfied {
    final DateTime? reviewWindowClosesAt = this.reviewWindowClosesAt;
    if (reviewWindowClosesAt == null) {
      return deliverySatisfied;
    }
    return !reviewWindowClosesAt.isAfter(DateTime.now().toUtc());
  }

  bool get payoutReleased => payoutReleasedAt != null;
}
