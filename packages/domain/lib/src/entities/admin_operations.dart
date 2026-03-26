class AdminDashboardSnapshot {
  const AdminDashboardSnapshot({
    required this.openDisputes,
    required this.activeListings,
    required this.paymentPendingOrders,
    required this.deliveryPendingOrders,
    required this.payoutPendingOrders,
    required this.refundPendingOrders,
    required this.grossSalesCents,
    required this.royaltyCents,
    required this.platformFeeCents,
    required this.frozenItems,
    required this.stolenItems,
  });

  final int openDisputes;
  final int activeListings;
  final int paymentPendingOrders;
  final int deliveryPendingOrders;
  final int payoutPendingOrders;
  final int refundPendingOrders;
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
    required this.shipmentStatus,
    required this.shipmentCarrier,
    required this.trackingNumber,
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
  final String? shipmentStatus;
  final String? shipmentCarrier;
  final String? trackingNumber;
  final String? sellerPayoutStatus;
  final String? royaltyStatus;
  final String? platformFeeStatus;
}

class AdminArtistRecord {
  const AdminArtistRecord({
    required this.artistId,
    required this.displayName,
    required this.slug,
    required this.royaltyBps,
    required this.isActive,
    required this.artworkCount,
    required this.inventoryCount,
  });

  final String artistId;
  final String displayName;
  final String slug;
  final int royaltyBps;
  final bool isActive;
  final int artworkCount;
  final int inventoryCount;
}

class AdminArtworkRecord {
  const AdminArtworkRecord({
    required this.artworkId,
    required this.artistId,
    required this.artistName,
    required this.title,
    required this.creationDate,
    required this.inventoryCount,
  });

  final String artworkId;
  final String artistId;
  final String artistName;
  final String title;
  final DateTime? creationDate;
  final int inventoryCount;
}

class AdminInventoryRecord {
  const AdminInventoryRecord({
    required this.itemId,
    required this.serialNumber,
    required this.artistName,
    required this.artworkTitle,
    required this.garmentName,
    required this.itemState,
    required this.ownerDisplayLabel,
  });

  final String itemId;
  final String serialNumber;
  final String artistName;
  final String artworkTitle;
  final String garmentName;
  final String itemState;
  final String ownerDisplayLabel;
}

class AdminGarmentProductRecord {
  const AdminGarmentProductRecord({
    required this.garmentProductId,
    required this.sku,
    required this.name,
    required this.silhouette,
    required this.sizeLabel,
    required this.colorway,
    required this.basePriceCents,
  });

  final String garmentProductId;
  final String sku;
  final String name;
  final String? silhouette;
  final String? sizeLabel;
  final String? colorway;
  final int basePriceCents;
}

class AdminFinanceRecord {
  const AdminFinanceRecord({
    required this.orderId,
    required this.paymentStatus,
    required this.shipmentStatus,
    required this.sellerPayoutStatus,
    required this.royaltyStatus,
    required this.platformFeeStatus,
    required this.totalCents,
  });

  final String orderId;
  final String paymentStatus;
  final String shipmentStatus;
  final String sellerPayoutStatus;
  final String royaltyStatus;
  final String platformFeeStatus;
  final int totalCents;
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
    required this.artists,
    required this.artworks,
    required this.inventory,
    required this.garmentProducts,
    required this.finance,
    required this.audits,
    required this.settings,
  });

  final AdminDashboardSnapshot dashboard;
  final List<AdminCustomerRecord> customers;
  final List<AdminListingRecord> listings;
  final List<AdminDisputeRecord> disputes;
  final List<AdminOrderRecord> orders;
  final List<AdminArtistRecord> artists;
  final List<AdminArtworkRecord> artworks;
  final List<AdminInventoryRecord> inventory;
  final List<AdminGarmentProductRecord> garmentProducts;
  final List<AdminFinanceRecord> finance;
  final List<AdminAuditRecord> audits;
  final PlatformSettingsSnapshot settings;
}
