import 'package:data/data.dart';
import 'package:domain/domain.dart';

class AdminOperationsService {
  const AdminOperationsService({required AdminOperationsRepository repository})
    : _repository = repository;

  final AdminOperationsRepository _repository;

  AdminOperationsSnapshot? snapshot() => _repository.snapshot();

  Future<MarketplaceActionResult<AdminOperationsSnapshot>> refresh() {
    return _repository.refresh();
  }

  Future<MarketplaceActionResult<AdminDisputeRecord>> updateDisputeStatus({
    required String disputeId,
    required String status,
    required String note,
    required bool releaseItem,
    String? releaseTargetState,
  }) {
    return _repository.updateDisputeStatus(
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
    return _repository.moderateListing(
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
    return _repository.updateSettings(
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
    return _repository.setUserRole(userId: userId, role: role);
  }

  Future<MarketplaceActionResult<AdminArtistRecord>> upsertArtist({
    String? artistId,
    required String displayName,
    required String slug,
    required int royaltyBps,
    required String authenticityStatement,
    required bool isActive,
  }) {
    return _repository.upsertArtist(
      artistId: artistId,
      displayName: displayName,
      slug: slug,
      royaltyBps: royaltyBps,
      authenticityStatement: authenticityStatement,
      isActive: isActive,
    );
  }

  Future<MarketplaceActionResult<AdminArtworkRecord>> upsertArtwork({
    String? artworkId,
    required String artistId,
    required String title,
    required String story,
    required List<String> provenanceProof,
    DateTime? creationDate,
  }) {
    return _repository.upsertArtwork(
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
    return _repository.upsertInventoryItem(
      itemId: itemId,
      artistId: artistId,
      artworkId: artworkId,
      garmentProductId: garmentProductId,
      serialNumber: serialNumber,
      itemState: itemState,
    );
  }

  Future<MarketplaceActionResult<void>> flagItemStatus({
    required String itemId,
    required String targetState,
    required String note,
  }) {
    return _repository.flagItemStatus(
      itemId: itemId,
      targetState: targetState,
      note: note,
    );
  }
}
