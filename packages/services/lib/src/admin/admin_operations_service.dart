import 'dart:typed_data';

import 'package:data/data.dart';
import 'package:domain/domain.dart';

class AdminOperationsService {
  const AdminOperationsService({required this.repository});

  final AdminOperationsRepository repository;

  AdminOperationsSnapshot? snapshot() => repository.snapshot();

  Future<MarketplaceActionResult<AdminOperationsSnapshot>> refresh() {
    return repository.refresh();
  }

  Future<MarketplaceActionResult<AdminDisputeRecord>> updateDisputeStatus({
    required String disputeId,
    required String status,
    required String note,
    required bool releaseItem,
    String? releaseTargetState,
  }) {
    return repository.updateDisputeStatus(
      disputeId: disputeId,
      status: status,
      note: note,
      releaseItem: releaseItem,
      releaseTargetState: releaseTargetState,
    );
  }

  Future<MarketplaceActionResult<AdminListingRecord>> moderateListing({
    required String listingId,
    required String action,
    required String note,
  }) {
    return repository.moderateListing(
      listingId: listingId,
      action: action,
      note: note,
    );
  }

  Future<MarketplaceActionResult<PlatformSettingsSnapshot>> updateSettings({
    required int platformFeeBps,
    required int defaultRoyaltyBps,
    required Map<String, dynamic> marketplaceRules,
    required Map<String, dynamic> brandSettings,
  }) {
    return repository.updateSettings(
      platformFeeBps: platformFeeBps,
      defaultRoyaltyBps: defaultRoyaltyBps,
      marketplaceRules: marketplaceRules,
      brandSettings: brandSettings,
    );
  }

  Future<MarketplaceActionResult<AdminCustomerRecord>> setUserRole({
    required String userId,
    required String role,
  }) {
    return repository.setUserRole(userId: userId, role: role);
  }

  Future<MarketplaceActionResult<AdminArtistRecord>> upsertArtist({
    String? artistId,
    required String displayName,
    required String slug,
    required int royaltyBps,
    required String authenticityStatement,
    String? shortBio,
    String? fullBio,
    String? artistStatement,
    String? instagramUrl,
    String? websiteUrl,
    required bool isFeatured,
    required int sortOrder,
    required String profileStatus,
  }) {
    return repository.upsertArtist(
      artistId: artistId,
      displayName: displayName,
      slug: slug,
      royaltyBps: royaltyBps,
      authenticityStatement: authenticityStatement,
      shortBio: shortBio,
      fullBio: fullBio,
      artistStatement: artistStatement,
      instagramUrl: instagramUrl,
      websiteUrl: websiteUrl,
      isFeatured: isFeatured,
      sortOrder: sortOrder,
      profileStatus: profileStatus,
    );
  }

  Future<MarketplaceActionResult<void>> uploadArtistImage({
    required String artistId,
    required String slot,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) {
    return repository.uploadArtistImage(
      artistId: artistId,
      slot: slot,
      bytes: bytes,
      fileName: fileName,
      contentType: contentType,
    );
  }

  Future<MarketplaceActionResult<void>> removeArtistImage({
    required String artistId,
    required String slot,
  }) {
    return repository.removeArtistImage(artistId: artistId, slot: slot);
  }

  Future<MarketplaceActionResult<AdminArtworkRecord>> upsertArtwork({
    String? artworkId,
    required String artistId,
    required String title,
    required String story,
    required List<String> provenanceProof,
    DateTime? creationDate,
  }) {
    return repository.upsertArtwork(
      artworkId: artworkId,
      artistId: artistId,
      title: title,
      story: story,
      provenanceProof: provenanceProof,
      creationDate: creationDate,
    );
  }

  Future<MarketplaceActionResult<AdminInventoryRecord>> upsertInventoryItem({
    String? itemId,
    required String artistId,
    required String artworkId,
    required String garmentProductId,
    required String serialNumber,
    required String itemState,
  }) {
    return repository.upsertInventoryItem(
      itemId: itemId,
      artistId: artistId,
      artworkId: artworkId,
      garmentProductId: garmentProductId,
      serialNumber: serialNumber,
      itemState: itemState,
    );
  }

  Future<MarketplaceActionResult<AdminInventoryRecord>>
  createAuthenticityRecord({required String itemId}) {
    return repository.createAuthenticityRecord(itemId: itemId);
  }

  Future<MarketplaceActionResult<AdminInventoryRecord>> upsertInventoryListing({
    required String itemId,
    required int askingPriceCents,
    required String status,
  }) {
    return repository.upsertInventoryListing(
      itemId: itemId,
      askingPriceCents: askingPriceCents,
      status: status,
    );
  }

  Future<MarketplaceActionResult<AdminClaimPacketData>> revealItemClaimCode({
    required String itemId,
    required String reason,
  }) {
    return repository.revealItemClaimCode(itemId: itemId, reason: reason);
  }

  Future<MarketplaceActionResult<AdminClaimPacketData>> generateClaimPacket({
    required String itemId,
    required String reason,
  }) {
    return repository.generateClaimPacket(itemId: itemId, reason: reason);
  }

  Future<MarketplaceActionResult<void>> uploadInventoryImage({
    required String itemId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) {
    return repository.uploadInventoryImage(
      itemId: itemId,
      bytes: bytes,
      fileName: fileName,
      contentType: contentType,
    );
  }

  Future<MarketplaceActionResult<void>> removeInventoryImage({
    required String itemId,
  }) {
    return repository.removeInventoryImage(itemId: itemId);
  }

  Future<MarketplaceActionResult<void>> flagItemStatus({
    required String itemId,
    required String targetState,
    required String note,
  }) {
    return repository.flagItemStatus(
      itemId: itemId,
      targetState: targetState,
      note: note,
    );
  }

  Future<MarketplaceActionResult<AdminOrderRecord>> reviewManualPayment({
    required String orderId,
    required String action,
    required String note,
  }) {
    return repository.reviewManualPayment(
      orderId: orderId,
      action: action,
      note: note,
    );
  }
}
