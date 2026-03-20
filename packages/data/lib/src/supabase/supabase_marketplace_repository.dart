import 'package:domain/domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repositories/marketplace_repository.dart';

class SupabaseMarketplaceRepository implements MarketplaceRepository {
  SupabaseMarketplaceRepository({
    SupabaseClient? client,
    String? configurationError,
  }) : _client = client,
       _configurationError = configurationError;

  final SupabaseClient? _client;
  final String? _configurationError;

  List<Artist> _artists = <Artist>[];
  List<Artwork> _artworks = <Artwork>[];
  List<UniqueItem> _items = <UniqueItem>[];
  List<Listing> _listings = <Listing>[];
  Map<String, List<OwnershipRecord>> _histories =
      <String, List<OwnershipRecord>>{};

  @override
  List<Listing> activeListings() => List<Listing>.unmodifiable(_listings);

  @override
  Artwork? artworkById(String artworkId) {
    for (final Artwork artwork in _artworks) {
      if (artwork.id == artworkId) {
        return artwork;
      }
    }
    return null;
  }

  @override
  List<Artwork> artworks() => List<Artwork>.unmodifiable(_artworks);

  @override
  Future<MarketplaceActionResult<UniqueItem>> buyResaleItem({
    required String itemId,
    required String buyerUserId,
    required String providerReference,
  }) async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<UniqueItem>(
        success: false,
        message: configError,
      );
    }

    final Listing? listing = _activeListingForItem(itemId);
    if (listing == null) {
      return const MarketplaceActionResult<UniqueItem>(
        success: false,
        message: 'Active resale listing not found.',
      );
    }

    try {
      final dynamic orderId = await _client!.rpc(
        'create_resale_order',
        params: <String, dynamic>{'p_listing_id': listing.id},
      );
      await _client!.rpc(
        'record_resale_payment_and_transfer',
        params: <String, dynamic>{
          'p_order_id': orderId,
          'p_provider': 'mock_provider',
          'p_provider_reference': providerReference,
          'p_amount_cents': listing.askingPrice,
        },
      );
      await refresh(userId: buyerUserId);
      return MarketplaceActionResult<UniqueItem>(
        success: true,
        message: 'Payment captured and ownership transferred on-platform.',
        data: itemById(itemId),
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<UniqueItem>(
        success: false,
        message: _friendlyMessage(error),
      );
    }
  }

  @override
  Future<MarketplaceActionResult<UniqueItem>> claimOwnership({
    required String itemId,
    required String claimCode,
    required String userId,
  }) async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<UniqueItem>(
        success: false,
        message: configError,
      );
    }

    try {
      await _client!.rpc(
        'claim_item_ownership',
        params: <String, dynamic>{
          'p_item_id': itemId,
          'p_claim_code': claimCode,
        },
      );
      await refresh(userId: userId);
      return MarketplaceActionResult<UniqueItem>(
        success: true,
        message: 'Ownership claim recorded by the backend.',
        data: itemById(itemId),
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<UniqueItem>(
        success: false,
        message: _friendlyMessage(error),
      );
    }
  }

  @override
  Future<MarketplaceActionResult<Listing>> createResaleListing({
    required String itemId,
    required String userId,
    required int priceCents,
  }) async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<Listing>(
        success: false,
        message: configError,
      );
    }

    try {
      final dynamic listingId = await _client!.rpc(
        'create_resale_listing',
        params: <String, dynamic>{
          'p_item_id': itemId,
          'p_price_cents': priceCents,
        },
      );
      await refresh(userId: userId);
      return MarketplaceActionResult<Listing>(
        success: true,
        message: 'Resale listing published through backend validation.',
        data: _listingById('$listingId') ?? _activeListingForItem(itemId),
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<Listing>(
        success: false,
        message: _friendlyMessage(error),
      );
    }
  }

  @override
  String? currentUserId() => _client?.auth.currentUser?.id;

  @override
  List<Artist> featuredArtists() => List<Artist>.unmodifiable(_artists);

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
  Future<MarketplaceActionResult<UniqueItem>> openDispute({
    required String itemId,
    required String userId,
    required String reason,
    required bool freeze,
  }) async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<UniqueItem>(
        success: false,
        message: configError,
      );
    }

    try {
      await _client!.rpc(
        'open_dispute',
        params: <String, dynamic>{
          'p_item_id': itemId,
          'p_reason': reason,
          'p_details': null,
          'p_freeze_item': freeze,
        },
      );
      await refresh(userId: userId);
      return MarketplaceActionResult<UniqueItem>(
        success: true,
        message: freeze
            ? 'Lost or stolen report submitted and item frozen.'
            : 'Dispute submitted for admin review.',
        data: itemById(itemId),
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<UniqueItem>(
        success: false,
        message: _friendlyMessage(error),
      );
    }
  }

  @override
  List<OwnershipRecord> ownershipHistory(String itemId) =>
      List<OwnershipRecord>.unmodifiable(
        _histories[itemId] ?? const <OwnershipRecord>[],
      );

  @override
  Future<void> refresh({required String userId}) async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      _artists = <Artist>[];
      _artworks = <Artwork>[];
      _items = <UniqueItem>[];
      _listings = <Listing>[];
      _histories = <String, List<OwnershipRecord>>{};
      return;
    }

    final List<dynamic> artistRows = await _client!
        .from('artists')
        .select('id, slug, display_name, royalty_bps, authenticity_statement')
        .eq('is_active', true);
    final List<dynamic> artworkRows = await _client!
        .from('artworks')
        .select('id, artist_id, title, story, provenance_proof, creation_date');
    final List<dynamic> catalogRows = await _client!
        .from('public_collectible_catalog')
        .select();

    List<dynamic> myCollectibleRows = <dynamic>[];
    if (currentUserId() != null) {
      myCollectibleRows =
          (await _client!.rpc('get_my_collectibles')) as List<dynamic>;
    }

    _artists = artistRows
        .map((dynamic row) => _artistFromRow(row as Map<String, dynamic>))
        .toList();
    _artworks = artworkRows
        .map((dynamic row) => _artworkFromRow(row as Map<String, dynamic>))
        .toList();

    final Map<String, UniqueItem> mergedItems = <String, UniqueItem>{};
    final List<Listing> publicListings = <Listing>[];

    for (final dynamic row in catalogRows) {
      final Map<String, dynamic> map = row as Map<String, dynamic>;
      final UniqueItem item = _catalogItemFromRow(map);
      mergedItems[item.id] = item;
      if (map['listing_id'] != null &&
          item.state == ItemState.listedForResale) {
        publicListings.add(
          Listing(
            id: map['listing_id'].toString(),
            itemId: item.id,
            sellerUserId: 'private_seller',
            askingPrice: (map['asking_price_cents'] as num?)?.toInt() ?? 0,
            isActive: true,
          ),
        );
      }
    }

    final Map<String, List<OwnershipRecord>> histories =
        <String, List<OwnershipRecord>>{};
    for (final dynamic row in myCollectibleRows) {
      final Map<String, dynamic> map = row as Map<String, dynamic>;
      final UniqueItem item = _ownedItemFromRow(
        map,
        mergedItems[map['item_id'].toString()],
      );
      mergedItems[item.id] = item;
      final List<dynamic> historyRows =
          await _client!.rpc(
                'get_my_item_history',
                params: <String, dynamic>{'p_item_id': item.id},
              )
              as List<dynamic>;
      histories[item.id] = historyRows
          .map(
            (dynamic historyRow) =>
                _historyFromRow(item.id, historyRow as Map<String, dynamic>),
          )
          .toList();
    }

    _items = mergedItems.values.toList()
      ..sort(
        (UniqueItem a, UniqueItem b) =>
            a.serialNumber.compareTo(b.serialNumber),
      );
    _listings = publicListings;
    _histories = histories;
  }

  Listing? _listingById(String listingId) {
    for (final Listing listing in _listings) {
      if (listing.id == listingId) {
        return listing;
      }
    }
    return null;
  }

  Listing? _activeListingForItem(String itemId) {
    for (final Listing listing in _listings) {
      if (listing.itemId == itemId && listing.isActive) {
        return listing;
      }
    }
    return null;
  }

  Artist _artistFromRow(Map<String, dynamic> row) {
    return Artist(
      id: row['id'].toString(),
      displayName: row['display_name'].toString(),
      slug: row['slug'].toString(),
      royaltyBps: (row['royalty_bps'] as num?)?.toInt() ?? 0,
      authenticityStatement: row['authenticity_statement'].toString(),
    );
  }

  Artwork _artworkFromRow(Map<String, dynamic> row) {
    final List<dynamic> proof =
        row['provenance_proof'] as List<dynamic>? ?? const <dynamic>[];
    final String? createdOn = row['creation_date'] as String?;
    return Artwork(
      id: row['id'].toString(),
      artistId: row['artist_id'].toString(),
      title: row['title'].toString(),
      story: row['story'].toString(),
      humanMadeProof: proof.map((dynamic item) => item.toString()).toList(),
      createdOn: createdOn == null ? DateTime(2026) : DateTime.parse(createdOn),
    );
  }

  UniqueItem _catalogItemFromRow(Map<String, dynamic> row) {
    return UniqueItem(
      id: row['item_id'].toString(),
      serialNumber: row['serial_number'].toString(),
      artworkId: row['artwork_id'].toString(),
      artistId: row['artist_id'].toString(),
      productName: row['garment_name'].toString(),
      state: itemStateFromKey(row['state'].toString()),
      currentOwnerUserId: null,
      claimCodeConsumed: row['state'].toString() != 'sold_unclaimed',
      askingPrice: (row['asking_price_cents'] as num?)?.toInt(),
    );
  }

  OwnershipRecord _historyFromRow(String itemId, Map<String, dynamic> row) {
    return OwnershipRecord(
      id: '${itemId}_${row['acquired_at']}',
      itemId: itemId,
      ownerUserId: row['owner_label'].toString(),
      acquiredAt: DateTime.parse(row['acquired_at'].toString()),
      relinquishedAt: row['relinquished_at'] == null
          ? null
          : DateTime.parse(row['relinquished_at'].toString()),
    );
  }

  UniqueItem _ownedItemFromRow(Map<String, dynamic> row, UniqueItem? fallback) {
    return UniqueItem(
      id: row['item_id'].toString(),
      serialNumber: row['serial_number'].toString(),
      artworkId: row['artwork_id'].toString(),
      artistId: row['artist_id'].toString(),
      productName: row['garment_name'].toString(),
      state: itemStateFromKey(row['state'].toString()),
      currentOwnerUserId: currentUserId(),
      claimCodeConsumed: true,
      askingPrice:
          (row['asking_price_cents'] as num?)?.toInt() ?? fallback?.askingPrice,
    );
  }

  String _friendlyMessage(PostgrestException error) {
    final String message = error.message;
    if (message.contains('Profile required before claim')) {
      return 'Complete your profile before claiming ownership.';
    }
    if (message.contains('Claim code invalid')) {
      return 'That hidden claim code was not accepted.';
    }
    if (message.contains('Claim code already used')) {
      return 'This claim code has already been used.';
    }
    if (message.contains(
      'Only the recorded owner, buyer, or admin can open a dispute',
    )) {
      return 'Only the verified owner or buyer can submit this dispute.';
    }
    return message;
  }

  String? _requireConfigured() {
    if (_client == null) {
      return _configurationError ?? 'Supabase is not configured for this app.';
    }
    return null;
  }
}
