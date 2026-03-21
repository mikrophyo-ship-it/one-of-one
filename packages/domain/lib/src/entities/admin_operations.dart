class AdminDashboardSnapshot {
  const AdminDashboardSnapshot({
    required this.openDisputes,
    required this.activeListings,
    required this.paymentPendingOrders,
    required this.grossSalesCents,
    required this.royaltyCents,
    required this.platformFeeCents,
    required this.frozenItems,
    required this.stolenItems,
  });

  final int openDisputes;
  final int activeListings;
  final int paymentPendingOrders;
  final int grossSalesCents;
  final int royaltyCents;
  final int platformFeeCents;
  final int frozenItems;
  final int stolenItems;
}

class AdminCustomerRecord {
  const AdminCustomerRecord({
    required this.userId,
    required this.displayName,
    required this.username,
    required this.role,
    required this.createdAt,
    required this.ownedItemCount,
    required this.openDisputeCount,
    required this.buyOrderCount,
    required this.sellOrderCount,
    required this.lastActivityAt,
  });

  final String userId;
  final String displayName;
  final String? username;
  final String role;
  final DateTime createdAt;
  final int ownedItemCount;
  final int openDisputeCount;
  final int buyOrderCount;
  final int sellOrderCount;
  final DateTime? lastActivityAt;
}

class AdminListingRecord {
  const AdminListingRecord({
    required this.listingId,
    required this.itemId,
    required this.sellerUserId,
    required this.listingStatus,
    required this.askingPriceCents,
    required this.createdAt,
    required this.serialNumber,
    required this.itemState,
    required this.garmentName,
    required this.artworkTitle,
    required this.artistName,
    required this.sellerDisplayName,
    required this.sellerUsername,
  });

  final String listingId;
  final String itemId;
  final String sellerUserId;
  final String listingStatus;
  final int askingPriceCents;
  final DateTime createdAt;
  final String serialNumber;
  final String itemState;
  final String garmentName;
  final String artworkTitle;
  final String artistName;
  final String? sellerDisplayName;
  final String? sellerUsername;
}

class AdminDisputeRecord {
  const AdminDisputeRecord({
    required this.disputeId,
    required this.itemId,
    required this.orderId,
    required this.disputeStatus,
    required this.reason,
    required this.details,
    required this.createdAt,
    required this.reportedByUserId,
    required this.reporterDisplayName,
    required this.reporterUsername,
    required this.serialNumber,
    required this.itemState,
    required this.garmentName,
    required this.artworkTitle,
    required this.artistName,
    required this.latestListingStatus,
  });

  final String disputeId;
  final String itemId;
  final String? orderId;
  final String disputeStatus;
  final String reason;
  final String? details;
  final DateTime createdAt;
  final String reportedByUserId;
  final String? reporterDisplayName;
  final String? reporterUsername;
  final String serialNumber;
  final String itemState;
  final String garmentName;
  final String artworkTitle;
  final String artistName;
  final String? latestListingStatus;
}

class AdminOrderRecord {
  const AdminOrderRecord({
    required this.orderId,
    required this.listingId,
    required this.orderStatus,
    required this.subtotalCents,
    required this.totalCents,
    required this.createdAt,
    required this.itemId,
    required this.serialNumber,
    required this.itemState,
    required this.garmentName,
    required this.artworkTitle,
    required this.artistName,
    required this.buyerDisplayName,
    required this.sellerDisplayName,
    required this.listingStatus,
    required this.paymentStatus,
    required this.paymentProvider,
    required this.sellerPayoutStatus,
    required this.royaltyStatus,
    required this.platformFeeStatus,
  });

  final String orderId;
  final String? listingId;
  final String orderStatus;
  final int subtotalCents;
  final int totalCents;
  final DateTime createdAt;
  final String itemId;
  final String serialNumber;
  final String itemState;
  final String garmentName;
  final String artworkTitle;
  final String artistName;
  final String? buyerDisplayName;
  final String? sellerDisplayName;
  final String? listingStatus;
  final String? paymentStatus;
  final String? paymentProvider;
  final String? sellerPayoutStatus;
  final String? royaltyStatus;
  final String? platformFeeStatus;
}

class AdminAuditRecord {
  const AdminAuditRecord({
    required this.auditId,
    required this.createdAt,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.payload,
    required this.actorDisplayName,
    required this.actorUsername,
  });

  final String auditId;
  final DateTime createdAt;
  final String entityType;
  final String? entityId;
  final String action;
  final Map<String, dynamic> payload;
  final String? actorDisplayName;
  final String? actorUsername;
}

class PlatformSettingsSnapshot {
  const PlatformSettingsSnapshot({
    required this.platformFeeBps,
    required this.defaultRoyaltyBps,
    required this.marketplaceRules,
    required this.brandSettings,
  });

  final int platformFeeBps;
  final int defaultRoyaltyBps;
  final Map<String, dynamic> marketplaceRules;
  final Map<String, dynamic> brandSettings;
}

class AdminOperationsSnapshot {
  const AdminOperationsSnapshot({
    required this.dashboard,
    required this.customers,
    required this.listings,
    required this.disputes,
    required this.orders,
    required this.audits,
    required this.settings,
  });

  final AdminDashboardSnapshot dashboard;
  final List<AdminCustomerRecord> customers;
  final List<AdminListingRecord> listings;
  final List<AdminDisputeRecord> disputes;
  final List<AdminOrderRecord> orders;
  final List<AdminAuditRecord> audits;
  final PlatformSettingsSnapshot settings;
}
