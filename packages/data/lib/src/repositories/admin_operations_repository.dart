import 'dart:typed_data';

import 'package:domain/domain.dart';

abstract class AdminOperationsRepository {
  AdminOperationsSnapshot? snapshot();

  Future<MarketplaceActionResult<AdminOperationsSnapshot>> refresh();

  Future<MarketplaceActionResult<AdminDisputeRecord>> updateDisputeStatus({
    required String disputeId,
    required String status,
    required String note,
    required bool releaseItem,
    String? releaseTargetState,
  });

  Future<MarketplaceActionResult<AdminListingRecord>> moderateListing({
    required String listingId,
    required String action,
    required String note,
  });

  Future<MarketplaceActionResult<PlatformSettingsSnapshot>> updateSettings({
    required int platformFeeBps,
    required int defaultRoyaltyBps,
    required Map<String, dynamic> marketplaceRules,
    required Map<String, dynamic> brandSettings,
  });

  Future<MarketplaceActionResult<AdminCustomerRecord>> setUserRole({
    required String userId,
    required String role,
  });

  Future<MarketplaceActionResult<AdminArtistRecord>> upsertArtist({
    String? artistId,
    required String displayName,
    required String slug,
    required int royaltyBps,
    required String authenticityStatement,
    required bool isActive,
  });

  Future<MarketplaceActionResult<AdminArtworkRecord>> upsertArtwork({
    String? artworkId,
    required String artistId,
    required String title,
    required String story,
    required List<String> provenanceProof,
    DateTime? creationDate,
  });

  Future<MarketplaceActionResult<AdminInventoryRecord>> upsertInventoryItem({
    String? itemId,
    required String artistId,
    required String artworkId,
    required String garmentProductId,
    required String serialNumber,
    required String itemState,
  });

  Future<MarketplaceActionResult<AdminInventoryRecord>>
  createAuthenticityRecord({required String itemId});

  Future<MarketplaceActionResult<AdminInventoryRecord>> upsertInventoryListing({
    required String itemId,
    required int askingPriceCents,
    required String status,
  });

  Future<MarketplaceActionResult<AdminClaimPacketData>> revealItemClaimCode({
    required String itemId,
    required String reason,
  });

  Future<MarketplaceActionResult<AdminClaimPacketData>> generateClaimPacket({
    required String itemId,
    required String reason,
  });

  Future<MarketplaceActionResult<void>> uploadInventoryImage({
    required String itemId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  });

  Future<MarketplaceActionResult<void>> removeInventoryImage({
    required String itemId,
  });

  Future<MarketplaceActionResult<void>> flagItemStatus({
    required String itemId,
    required String targetState,
    required String note,
  });

  Future<MarketplaceActionResult<AdminOrderRecord>> reviewManualPayment({
    required String orderId,
    required String action,
    required String note,
  });
}
