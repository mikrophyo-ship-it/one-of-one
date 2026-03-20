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
  Future<MarketplaceActionResult<UniqueItem>> claimOwnership({
    required String itemId,
    required String claimCode,
    required String userId,
  });
  Future<MarketplaceActionResult<Listing>> createResaleListing({
    required String itemId,
    required String userId,
    required int priceCents,
  });
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
