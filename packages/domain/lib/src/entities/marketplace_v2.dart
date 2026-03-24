class ResaleCheckoutSession {
  const ResaleCheckoutSession({
    required this.orderId,
    required this.provider,
    required this.status,
    required this.providerReference,
    required this.checkoutUrl,
    required this.clientSecret,
    required this.expiresAt,
  });

  final String orderId;
  final String provider;
  final String status;
  final String providerReference;
  final String? checkoutUrl;
  final String? clientSecret;
  final DateTime? expiresAt;
}

class RefundRecord {
  const RefundRecord({
    required this.refundId,
    required this.orderId,
    required this.status,
    required this.amountCents,
    required this.reason,
    required this.providerReference,
    required this.createdAt,
  });

  final String refundId;
  final String orderId;
  final String status;
  final int amountCents;
  final String reason;
  final String? providerReference;
  final DateTime createdAt;
}

class ShipmentEvent {
  const ShipmentEvent({
    required this.orderId,
    required this.status,
    required this.occurredAt,
    this.carrier,
    this.trackingNumber,
    this.note,
  });

  final String orderId;
  final String status;
  final DateTime occurredAt;
  final String? carrier;
  final String? trackingNumber;
  final String? note;
}

class CollectorNotification {
  const CollectorNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.read,
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;
}

class SavedCollectible {
  const SavedCollectible({
    required this.itemId,
    required this.savedAt,
  });

  final String itemId;
  final DateTime savedAt;
}
