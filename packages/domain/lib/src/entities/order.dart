class Order {
  const Order({
    required this.id,
    required this.itemId,
    required this.buyerUserId,
    required this.amount,
    required this.paymentCaptured,
  });

  final String id;
  final String itemId;
  final String buyerUserId;
  final int amount;
  final bool paymentCaptured;
}
