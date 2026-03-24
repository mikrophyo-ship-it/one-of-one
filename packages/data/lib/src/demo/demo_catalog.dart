import 'package:domain/domain.dart';

import '../repositories/marketplace_repository.dart';

class DemoCatalog implements MarketplaceRepository {
  DemoCatalog({MarketplaceRules? rules})
    : _rules =
          rules ??
          const MarketplaceRules(
            platformFeeBps: 1000,
            defaultRoyaltyBps: 1200,
          ) {
    _items = <UniqueItem>[
      const UniqueItem(
        id: 'item_afterglow_01',
        serialNumber: 'OOO-AG-0001',
        artworkId: 'artwork_afterglow',
        artistId: 'artist_maya',
        productName: 'Afterglow Hand-Finished Tee',
        state: ItemState.listedForResale,
        currentOwnerUserId: 'user_collector_1',
        claimCodeConsumed: true,
        askingPrice: 180000,
      ),
      const UniqueItem(
        id: 'item_ember_02',
        serialNumber: 'OOO-EM-0002',
        artworkId: 'artwork_afterglow',
        artistId: 'artist_maya',
        productName: 'Ember Archive Crew',
        state: ItemState.soldUnclaimed,
        currentOwnerUserId: null,
        claimCodeConsumed: false,
        askingPrice: null,
      ),
      const UniqueItem(
        id: 'item_restricted_03',
        serialNumber: 'OOO-RS-0003',
        artworkId: 'artwork_afterglow',
        artistId: 'artist_maya',
        productName: 'Restricted Study Hoodie',
        state: ItemState.frozen,
        currentOwnerUserId: 'user_collector_2',
        claimCodeConsumed: true,
        askingPrice: null,
      ),
    ];
    _qrTokens = <String, String>{
      'item_afterglow_01': 'qr_afterglow_01',
      'item_ember_02': 'qr_ember_02',
      'item_restricted_03': 'qr_restricted_03',
    };
    _listings = <Listing>[
      const Listing(
        id: 'listing_1',
        itemId: 'item_afterglow_01',
        sellerUserId: 'user_collector_1',
        askingPrice: 180000,
        isActive: true,
      ),
    ];
    _ownershipRecords = <OwnershipRecord>[
      OwnershipRecord(
        id: 'ownership_1',
        itemId: 'item_afterglow_01',
        ownerUserId: 'business_inventory',
        acquiredAt: DateTime(2026, 1, 12),
        relinquishedAt: DateTime(2026, 1, 18),
      ),
      OwnershipRecord(
        id: 'ownership_2',
        itemId: 'item_afterglow_01',
        ownerUserId: 'user_collector_1',
        acquiredAt: DateTime(2026, 1, 18),
      ),
      OwnershipRecord(
        id: 'ownership_3',
        itemId: 'item_restricted_03',
        ownerUserId: 'user_collector_2',
        acquiredAt: DateTime(2026, 2, 1),
      ),
    ];
  }

  final MarketplaceRules _rules;

  static const Artist maya = Artist(
    id: 'artist_maya',
    displayName: 'Maya Vale',
    slug: 'maya-vale',
    royaltyBps: 1200,
    authenticityStatement:
        'Created and finished by Maya Vale in-studio, without generative tooling.',
  );

  static final Artwork artwork = Artwork(
    id: 'artwork_afterglow',
    artistId: maya.id,
    title: 'Afterglow No. 01',
    story:
        'A hand-painted study of nightlife reflections translated into a single collectible garment.',
    humanMadeProof: <String>[
      'Graphite composition studies',
      'Studio paint process stills',
      'Signed finishing statement',
    ],
    createdOn: DateTime(2026, 1, 10),
  );

  late final List<UniqueItem> _items;
  late final Map<String, String> _qrTokens;
  late final List<Listing> _listings;
  late final List<OwnershipRecord> _ownershipRecords;
  final List<SavedCollectible> _savedItems = <SavedCollectible>[];
  final List<CollectorNotification> _notifications = <CollectorNotification>[];

  @override
  List<Listing> activeListings() => List<Listing>.unmodifiable(
    _listings.where((Listing listing) => listing.isActive),
  );

  @override
  Artwork? artworkById(String artworkId) {
    if (artwork.id == artworkId) {
      return artwork;
    }
    return null;
  }

  @override
  List<Artwork> artworks() => <Artwork>[artwork];

  @override
  Future<MarketplaceActionResult<UniqueItem>> buyResaleItem({
    required String itemId,
    required String buyerUserId,
    required String providerReference,
  }) async {
    final int itemIndex = _items.indexWhere(
      (UniqueItem item) => item.id == itemId,
    );
    if (itemIndex == -1) {
      return const MarketplaceActionResult<UniqueItem>(
        success: false,
        message: 'Resale item not found.',
      );
    }

    final UniqueItem item = _items[itemIndex];
    final int listingIndex = _listings.indexWhere(
      (Listing listing) => listing.itemId == itemId && listing.isActive,
    );
    if (listingIndex == -1) {
      return const MarketplaceActionResult<UniqueItem>(
        success: false,
        message: 'Active listing not found for this collectible.',
      );
    }

    final Listing listing = _listings[listingIndex];
    if (listing.sellerUserId == buyerUserId) {
      return const MarketplaceActionResult<UniqueItem>(
        success: false,
        message: 'You cannot purchase your own listing.',
      );
    }
    if (_rules.blocksMarketplaceAction(item.state)) {
      return const MarketplaceActionResult<UniqueItem>(
        success: false,
        message: 'Restricted items cannot be sold or transferred.',
      );
    }

    final UniqueItem transferred = _rules.completeResale(
      item: item.copyWith(state: ItemState.salePending),
      order: Order(
        id: 'order-$itemId',
        itemId: itemId,
        buyerUserId: buyerUserId,
        amount: listing.askingPrice,
        paymentCaptured: true,
        deliveryConfirmedAt: DateTime.now(),
        reviewWindowClosesAt: DateTime.now().subtract(const Duration(hours: 1)),
      ),
    );

    _items[itemIndex] = transferred;
    _listings[listingIndex] = listing.copyWith(isActive: false);
    _closeOpenOwnershipRecord(itemId);
    _ownershipRecords.add(
      OwnershipRecord(
        id: 'ownership_${_ownershipRecords.length + 1}',
        itemId: itemId,
        ownerUserId: buyerUserId,
        acquiredAt: DateTime.now(),
      ),
    );

    return MarketplaceActionResult<UniqueItem>(
      success: true,
      message:
          'Payment captured with reference $providerReference. Ownership transferred on-platform.',
      data: transferred,
    );
  }

  @override
  Future<MarketplaceActionResult<UniqueItem>> confirmDelivery({
    required String orderId,
    required String userId,
    String? note,
  }) async {
    final UniqueItem? item = _items.where((UniqueItem candidate) {
      return candidate.currentOwnerUserId == userId;
    }).cast<UniqueItem?>().firstWhere(
      (UniqueItem? candidate) => candidate != null,
      orElse: () => null,
    );
    return MarketplaceActionResult<UniqueItem>(
      success: true,
      message: note ?? 'Delivery confirmed.',
      data: item,
    );
  }

  @override
  Future<MarketplaceActionResult<UniqueItem>> claimOwnership({
    required String itemId,
    required String claimCode,
    required String userId,
  }) async {
    final int index = _items.indexWhere((UniqueItem item) => item.id == itemId);
    if (index == -1) {
      return const MarketplaceActionResult<UniqueItem>(
        success: false,
        message: 'Collectible not found.',
      );
    }

    final UniqueItem item = _items[index];
    final ClaimResult result = _rules.validateClaim(
      item: item,
      providedClaimCode: claimCode,
      expectedClaimCode: 'CLAIM-${item.serialNumber}',
    );
    if (!result.success) {
      return MarketplaceActionResult<UniqueItem>(
        success: false,
        message: result.message,
      );
    }

    final UniqueItem claimed = item.copyWith(
      state: ItemState.claimed,
      currentOwnerUserId: userId,
      claimCodeConsumed: true,
    );
    _items[index] = claimed;
    _ownershipRecords.add(
      OwnershipRecord(
        id: 'ownership_${_ownershipRecords.length + 1}',
        itemId: itemId,
        ownerUserId: userId,
        acquiredAt: DateTime.now(),
      ),
    );

    return MarketplaceActionResult<UniqueItem>(
      success: true,
      message:
          'Ownership claim approved and refreshed from the server contract.',
      data: claimed,
    );
  }

  @override
  Future<MarketplaceActionResult<UniqueItem>> claimOwnershipByQrToken({
    required String qrToken,
    required String claimCode,
    required String userId,
  }) async {
    final String? itemId = _itemIdForQrToken(qrToken);
    if (itemId == null) {
      return const MarketplaceActionResult<UniqueItem>(
        success: false,
        message: 'No verified collectible matched that QR token.',
      );
    }
    return claimOwnership(itemId: itemId, claimCode: claimCode, userId: userId);
  }

  @override
  Future<MarketplaceActionResult<Listing>> createResaleListing({
    required String itemId,
    required String userId,
    required int priceCents,
  }) async {
    final int itemIndex = _items.indexWhere(
      (UniqueItem item) => item.id == itemId,
    );
    if (itemIndex == -1) {
      return const MarketplaceActionResult<Listing>(
        success: false,
        message: 'Collectible not found.',
      );
    }

    final UniqueItem item = _items[itemIndex];
    if (_rules.blocksMarketplaceAction(item.state)) {
      return const MarketplaceActionResult<Listing>(
        success: false,
        message: 'Restricted items cannot be listed.',
      );
    }
    if (!_rules.canListForResale(item: item, actingUserId: userId)) {
      return const MarketplaceActionResult<Listing>(
        success: false,
        message: 'Only the recorded current owner can list this collectible.',
      );
    }
    if (_listings.any(
      (Listing listing) => listing.itemId == itemId && listing.isActive,
    )) {
      return const MarketplaceActionResult<Listing>(
        success: false,
        message: 'An active listing already exists for this collectible.',
      );
    }

    final Listing listing = Listing(
      id: 'listing_${_listings.length + 1}',
      itemId: itemId,
      sellerUserId: userId,
      askingPrice: priceCents,
      isActive: true,
    );
    _listings.add(listing);
    _items[itemIndex] = item.copyWith(
      state: ItemState.listedForResale,
      askingPrice: priceCents,
    );

    return MarketplaceActionResult<Listing>(
      success: true,
      message:
          'Listing published. Backend eligibility and royalty logic applied.',
      data: listing,
    );
  }

  @override
  Future<MarketplaceActionResult<List<CollectorNotification>>>
  fetchNotifications() async {
    return MarketplaceActionResult<List<CollectorNotification>>(
      success: true,
      message: 'Demo notifications ready.',
      data: List<CollectorNotification>.unmodifiable(_notifications),
    );
  }

  @override
  Future<MarketplaceActionResult<List<SavedCollectible>>> fetchSavedItems() async {
    return MarketplaceActionResult<List<SavedCollectible>>(
      success: true,
      message: 'Demo saved items ready.',
      data: List<SavedCollectible>.unmodifiable(_savedItems),
    );
  }

  @override
  Future<MarketplaceActionResult<UniqueItem>> finalizeResaleCheckout({
    required String orderId,
    required String buyerUserId,
    required String provider,
    required String providerReference,
    required int amountCents,
  }) async {
    final UniqueItem item = _items.firstWhere(
      (UniqueItem candidate) => candidate.askingPrice == amountCents,
      orElse: () => _items.first,
    );
    return buyResaleItem(
      itemId: item.id,
      buyerUserId: buyerUserId,
      providerReference: providerReference,
    );
  }

  @override
  Future<MarketplaceActionResult<RefundRecord>> issueRefund({
    required String orderId,
    required int amountCents,
    required String reason,
    String? note,
  }) async {
    return MarketplaceActionResult<RefundRecord>(
      success: true,
      message: 'Demo refund recorded.',
      data: RefundRecord(
        refundId: 'refund_$orderId',
        orderId: orderId,
        status: 'refunded',
        amountCents: amountCents,
        reason: reason,
        providerReference: 'mock-refund-$orderId',
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  String? currentUserId() => 'user_collector_1';

  @override
  List<Artist> featuredArtists() => const <Artist>[maya];

  @override
  UniqueItem? itemById(String itemId) {
    for (final UniqueItem item in _items) {
      if (item.id == itemId) {
        return item;
      }
    }
    return null;
  }

  @override
  List<UniqueItem> items() => List<UniqueItem>.unmodifiable(_items);

  @override
  Future<MarketplaceActionResult<PublicAuthenticityRecord>>
  lookupPublicAuthenticity({required String qrToken}) async {
    final String? itemId = _itemIdForQrToken(qrToken);
    if (itemId == null) {
      return const MarketplaceActionResult<PublicAuthenticityRecord>(
        success: false,
        message: 'No verified collectible matched that QR token.',
      );
    }

    final UniqueItem? item = itemById(itemId);
    if (item == null) {
      return const MarketplaceActionResult<PublicAuthenticityRecord>(
        success: false,
        message: 'Authenticity record unavailable.',
      );
    }

    return MarketplaceActionResult<PublicAuthenticityRecord>(
      success: true,
      message: 'Authenticity verified from the backend.',
      data: PublicAuthenticityRecord(
        qrToken: qrToken,
        serialNumber: item.serialNumber,
        state: item.state,
        garmentName: item.productName,
        artworkTitle: artwork.title,
        story: artwork.story,
        artistName: maya.displayName,
        authenticityStatus: 'verified_human_made',
        publicStory: artwork.story,
        ownershipVisibility: item.state.isRestricted
            ? 'restricted ownership status'
            : 'platform verified',
        verifiedTransferCount:
            _ownershipRecords
                .where((OwnershipRecord record) => record.itemId == item.id)
                .length -
            1,
      ),
    );
  }

  @override
  Future<MarketplaceActionResult<UniqueItem>> openDispute({
    required String itemId,
    required String userId,
    required String reason,
    required bool freeze,
  }) async {
    final int itemIndex = _items.indexWhere(
      (UniqueItem item) => item.id == itemId,
    );
    if (itemIndex == -1) {
      return const MarketplaceActionResult<UniqueItem>(
        success: false,
        message: 'Collectible not found.',
      );
    }

    final UniqueItem item = _items[itemIndex];
    if (item.currentOwnerUserId != null && item.currentOwnerUserId != userId) {
      return const MarketplaceActionResult<UniqueItem>(
        success: false,
        message:
            'Only the recorded owner can raise this dispute in the demo workflow.',
      );
    }

    final UniqueItem updated = item.copyWith(
      state: freeze ? ItemState.frozen : ItemState.disputed,
      askingPrice: null,
    );
    _items[itemIndex] = updated;
    _deactivateListings(itemId);

    return MarketplaceActionResult<UniqueItem>(
      success: true,
      message: '${freeze ? 'Freeze' : 'Dispute'} recorded for review: $reason',
      data: updated,
    );
  }

  @override
  List<OwnershipRecord> ownershipHistory(String itemId) =>
      List<OwnershipRecord>.unmodifiable(
        _ownershipRecords.where(
          (OwnershipRecord record) => record.itemId == itemId,
        ),
      );

  @override
  Future<MarketplaceActionResult<ShipmentEvent>> recordShipmentEvent({
    required String orderId,
    required String shipmentStatus,
    String? carrier,
    String? trackingNumber,
    String? note,
  }) async {
    return MarketplaceActionResult<ShipmentEvent>(
      success: true,
      message: 'Demo shipment event saved.',
      data: ShipmentEvent(
        orderId: orderId,
        status: shipmentStatus,
        occurredAt: DateTime.now(),
        carrier: carrier,
        trackingNumber: trackingNumber,
        note: note,
      ),
    );
  }

  @override
  Future<void> refresh({required String userId}) async {}

  @override
  Future<MarketplaceActionResult<void>> removeSavedItem({
    required String itemId,
  }) async {
    _savedItems.removeWhere((SavedCollectible item) => item.itemId == itemId);
    return const MarketplaceActionResult<void>(
      success: true,
      message: 'Demo saved item removed.',
    );
  }

  @override
  Future<MarketplaceActionResult<void>> saveItem({required String itemId}) async {
    _savedItems.add(SavedCollectible(itemId: itemId, savedAt: DateTime.now()));
    return const MarketplaceActionResult<void>(
      success: true,
      message: 'Demo saved item added.',
    );
  }

  @override
  Future<MarketplaceActionResult<ResaleCheckoutSession>> startResaleCheckout({
    required String itemId,
    required String buyerUserId,
    required String provider,
    String? successUrl,
    String? cancelUrl,
  }) async {
    return MarketplaceActionResult<ResaleCheckoutSession>(
      success: true,
      message: 'Demo checkout session created.',
      data: ResaleCheckoutSession(
        orderId: 'order-$itemId',
        provider: provider,
        status: 'requires_action',
        providerReference: 'demo-$itemId-$buyerUserId',
        checkoutUrl: successUrl,
        clientSecret: 'secret-$itemId',
        expiresAt: DateTime.now().add(const Duration(minutes: 30)),
      ),
    );
  }

  String? _itemIdForQrToken(String qrToken) {
    for (final MapEntry<String, String> entry in _qrTokens.entries) {
      if (entry.value == qrToken.trim()) {
        return entry.key;
      }
    }
    return null;
  }

  void _closeOpenOwnershipRecord(String itemId) {
    for (int i = 0; i < _ownershipRecords.length; i++) {
      final OwnershipRecord record = _ownershipRecords[i];
      if (record.itemId == itemId && record.relinquishedAt == null) {
        _ownershipRecords[i] = OwnershipRecord(
          id: record.id,
          itemId: record.itemId,
          ownerUserId: record.ownerUserId,
          acquiredAt: record.acquiredAt,
          relinquishedAt: DateTime.now(),
        );
      }
    }
  }

  void _deactivateListings(String itemId) {
    for (int i = 0; i < _listings.length; i++) {
      final Listing listing = _listings[i];
      if (listing.itemId == itemId && listing.isActive) {
        _listings[i] = listing.copyWith(isActive: false);
      }
    }
  }
}
