import 'package:domain/domain.dart';

abstract class MarketplaceRepository {
  List<Artist> featuredArtists();
  List<Artwork> artworks();
  List<UniqueItem> items();
  List<Listing> activeListings();
  List<OwnershipRecord> ownershipHistory(String itemId);
  UniqueItem? itemById(String itemId);
  Artwork? artworkById(String artworkId);
  String? currentUserId();
  Future<void> refresh({required String userId});
  Future<MarketplaceActionResult<PublicAuthenticityRecord>>
  lookupPublicAuthenticity({required String qrToken});
  Future<MarketplaceActionResult<UniqueItem>> claimOwnership({
    required String itemId,
    required String claimCode,
    required String userId,
  });
  Future<MarketplaceActionResult<UniqueItem>> claimOwnershipByQrToken({
    required String qrToken,
    required String claimCode,
    required String userId,
  });
  Future<MarketplaceActionResult<Listing>> createResaleListing({
    required String itemId,
    required String userId,
    required int priceCents,
  });
  Future<MarketplaceActionResult<ResaleCheckoutSession>> startResaleCheckout({
    required String itemId,
    required String buyerUserId,
    required String provider,
    String? successUrl,
    String? cancelUrl,
  });
  Future<MarketplaceActionResult<UniqueItem>> finalizeResaleCheckout({
    required String orderId,
    required String buyerUserId,
    required String provider,
    required String providerReference,
    required int amountCents,
  });
  Future<MarketplaceActionResult<ShipmentEvent>> recordShipmentEvent({
    required String orderId,
    required String shipmentStatus,
    String? carrier,
    String? trackingNumber,
    String? note,
  });
  Future<MarketplaceActionResult<UniqueItem>> confirmDelivery({
    required String orderId,
    required String userId,
    String? note,
  });
  Future<MarketplaceActionResult<RefundRecord>> issueRefund({
    required String orderId,
    required int amountCents,
    required String reason,
    String? note,
  });
  Future<MarketplaceActionResult<List<SavedCollectible>>> fetchSavedItems();
  Future<MarketplaceActionResult<List<CollectorNotification>>>
  fetchNotifications();
  Future<MarketplaceActionResult<void>> saveItem({required String itemId});
  Future<MarketplaceActionResult<void>> removeSavedItem({required String itemId});
  Future<MarketplaceActionResult<UniqueItem>> buyResaleItem({
    required String itemId,
    required String buyerUserId,
    required String providerReference,
  });
  Future<MarketplaceActionResult<UniqueItem>> openDispute({
    required String itemId,
    required String userId,
    required String reason,
    required bool freeze,
  });
}
