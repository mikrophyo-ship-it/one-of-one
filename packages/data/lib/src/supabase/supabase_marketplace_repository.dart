// ignore_for_file: unnecessary_non_null_assertion

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
  Map<String, String> _qrTokensByItemId = <String, String>{};
  Map<String, List<OwnershipRecord>> _histories =
      <String, List<OwnershipRecord>>{};
  List<SavedCollectible> _savedItems = <SavedCollectible>[];
  List<CollectorNotification> _notifications = <CollectorNotification>[];

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
      final dynamic session = await _client!.rpc(
        'create_resale_checkout_session',
        params: <String, dynamic>{'p_listing_id': listing.id},
      );
      final Map<String, dynamic> sessionMap =
          session as Map<String, dynamic>? ?? const <String, dynamic>{};
      final dynamic orderId = sessionMap['order_id'];
      await _client!.rpc(
        'mark_resale_payment_authorized',
        params: <String, dynamic>{
          'p_order_id': orderId,
          'p_provider': 'mock_provider',
          'p_provider_reference': providerReference,
          'p_amount_cents': listing.askingPrice,
        },
      );
      await _client!.rpc(
        'confirm_resale_delivery',
        params: <String, dynamic>{
          'p_order_id': orderId,
          'p_release_payouts': true,
          'p_note': 'Mock workflow auto-confirmed delivery.',
        },
      );
      await refresh(userId: buyerUserId);
      return MarketplaceActionResult<UniqueItem>(
        success: true,
        message: 'Payment recorded and ownership transferred after delivery confirmation.',
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
  Future<MarketplaceActionResult<UniqueItem>> claimOwnershipByQrToken({
    required String qrToken,
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
        'claim_item_ownership_by_qr_token',
        params: <String, dynamic>{
          'p_public_qr_token': qrToken.trim(),
          'p_claim_code': claimCode,
        },
      );
      await refresh(userId: userId);
      final UniqueItem? matchedItem = _itemByQrToken(qrToken.trim());
      return MarketplaceActionResult<UniqueItem>(
        success: true,
        message: 'Ownership claim recorded by the backend.',
        data: matchedItem,
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
  Future<MarketplaceActionResult<UniqueItem>> confirmDelivery({
    required String orderId,
    required String userId,
    String? note,
  }) async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<UniqueItem>(
        success: false,
        message: configError,
      );
    }

    try {
      final dynamic row = await _client!.rpc(
        'confirm_resale_delivery',
        params: <String, dynamic>{
          'p_order_id': orderId,
          'p_release_payouts': true,
          'p_note': note,
        },
      );
      await refresh(userId: userId);
      final String? itemId = (row as Map<String, dynamic>?)?['item_id']
          ?.toString();
      return MarketplaceActionResult<UniqueItem>(
        success: true,
        message: 'Delivery confirmed and payout release queued.',
        data: itemId == null ? null : itemById(itemId),
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<UniqueItem>(
        success: false,
        message: _friendlyMessage(error),
      );
    }
  }

  @override
  Future<MarketplaceActionResult<List<CollectorNotification>>>
  fetchNotifications() async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<List<CollectorNotification>>(
        success: false,
        message: configError,
      );
    }

    try {
      final List<dynamic> rows =
          (await _client!.rpc('get_my_notifications')) as List<dynamic>;
      _notifications = rows
          .map(
            (dynamic row) => _notificationFromRow(row as Map<String, dynamic>),
          )
          .toList();
      return MarketplaceActionResult<List<CollectorNotification>>(
        success: true,
        message: 'Collector notifications refreshed.',
        data: List<CollectorNotification>.unmodifiable(_notifications),
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<List<CollectorNotification>>(
        success: false,
        message: _friendlyMessage(error),
      );
    }
  }

  @override
  Future<MarketplaceActionResult<List<SavedCollectible>>> fetchSavedItems() async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<List<SavedCollectible>>(
        success: false,
        message: configError,
      );
    }

    try {
      final List<dynamic> rows =
          (await _client!.rpc('get_my_saved_collectibles')) as List<dynamic>;
      _savedItems = rows
          .map((dynamic row) => _savedItemFromRow(row as Map<String, dynamic>))
          .toList();
      return MarketplaceActionResult<List<SavedCollectible>>(
        success: true,
        message: 'Saved collectibles refreshed.',
        data: List<SavedCollectible>.unmodifiable(_savedItems),
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<List<SavedCollectible>>(
        success: false,
        message: _friendlyMessage(error),
      );
    }
  }

  @override
  Future<MarketplaceActionResult<UniqueItem>> finalizeResaleCheckout({
    required String orderId,
    required String buyerUserId,
    required String provider,
    required String providerReference,
    required int amountCents,
  }) async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<UniqueItem>(
        success: false,
        message: configError,
      );
    }

    try {
      final Map<String, dynamic> paymentRow =
          await _client!.rpc(
                'mark_resale_payment_authorized',
                params: <String, dynamic>{
                  'p_order_id': orderId,
                  'p_provider': provider,
                  'p_provider_reference': providerReference,
                  'p_amount_cents': amountCents,
                },
              )
              as Map<String, dynamic>;
      await refresh(userId: buyerUserId);
      final String? itemId = paymentRow['item_id']?.toString();
      return MarketplaceActionResult<UniqueItem>(
        success: true,
        message: 'Payment authorized. Ownership will transfer after delivery review.',
        data: itemId == null ? null : itemById(itemId),
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<UniqueItem>(
        success: false,
        message: _friendlyMessage(error),
      );
    }
  }

  @override
  Future<MarketplaceActionResult<RefundRecord>> issueRefund({
    required String orderId,
    required int amountCents,
    required String reason,
    String? note,
  }) async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<RefundRecord>(
        success: false,
        message: configError,
      );
    }

    try {
      final Map<String, dynamic> row =
          await _client!.rpc(
                'issue_order_refund',
                params: <String, dynamic>{
                  'p_order_id': orderId,
                  'p_amount_cents': amountCents,
                  'p_reason': reason,
                  'p_note': note,
                },
              )
              as Map<String, dynamic>;
      return MarketplaceActionResult<RefundRecord>(
        success: true,
        message: 'Refund workflow recorded.',
        data: _refundFromRow(row),
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<RefundRecord>(
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
  Future<MarketplaceActionResult<PublicAuthenticityRecord>>
  lookupPublicAuthenticity({required String qrToken}) async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<PublicAuthenticityRecord>(
        success: false,
        message: configError,
      );
    }

    try {
      final dynamic row = await _client!.rpc(
        'get_public_authenticity_by_qr_token',
        params: <String, dynamic>{'p_public_qr_token': qrToken.trim()},
      );
      if (row == null) {
        return const MarketplaceActionResult<PublicAuthenticityRecord>(
          success: false,
          message: 'No verified collectible matched that QR token.',
        );
      }

      return MarketplaceActionResult<PublicAuthenticityRecord>(
        success: true,
        message: 'Authenticity verified from the backend.',
        data: _publicAuthenticityFromRow(row as Map<String, dynamic>),
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<PublicAuthenticityRecord>(
        success: false,
        message: _friendlyMessage(error),
      );
    }
  }

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
  Future<MarketplaceActionResult<ShipmentEvent>> recordShipmentEvent({
    required String orderId,
    required String shipmentStatus,
    String? carrier,
    String? trackingNumber,
    String? note,
  }) async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<ShipmentEvent>(
        success: false,
        message: configError,
      );
    }

    try {
      final Map<String, dynamic> row =
          await _client!.rpc(
                'record_order_shipment_event',
                params: <String, dynamic>{
                  'p_order_id': orderId,
                  'p_status': shipmentStatus,
                  'p_carrier': carrier,
                  'p_tracking_number': trackingNumber,
                  'p_note': note,
                },
              )
              as Map<String, dynamic>;
      return MarketplaceActionResult<ShipmentEvent>(
        success: true,
        message: 'Shipment event logged.',
        data: _shipmentEventFromRow(row),
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<ShipmentEvent>(
        success: false,
        message: _friendlyMessage(error),
      );
    }
  }

  @override
  Future<void> refresh({required String userId}) async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      _artists = <Artist>[];
      _artworks = <Artwork>[];
      _items = <UniqueItem>[];
      _listings = <Listing>[];
      _qrTokensByItemId = <String, String>{};
      _histories = <String, List<OwnershipRecord>>{};
      _savedItems = <SavedCollectible>[];
      _notifications = <CollectorNotification>[];
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
    List<dynamic> savedItemRows = <dynamic>[];
    List<dynamic> notificationRows = <dynamic>[];
    if (currentUserId() != null) {
      myCollectibleRows =
          (await _client!.rpc('get_my_collectibles')) as List<dynamic>;
      savedItemRows =
          (await _client!.rpc('get_my_saved_collectibles')) as List<dynamic>;
      notificationRows =
          (await _client!.rpc('get_my_notifications')) as List<dynamic>;
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
      _qrTokensByItemId[item.id] = map['public_qr_token'].toString();
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
    _savedItems = savedItemRows
        .map((dynamic row) => _savedItemFromRow(row as Map<String, dynamic>))
        .toList();
    _notifications = notificationRows
        .map(
          (dynamic row) => _notificationFromRow(row as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<MarketplaceActionResult<void>> removeSavedItem({
    required String itemId,
  }) async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<void>(success: false, message: configError);
    }

    try {
      await _client!.rpc(
        'remove_saved_collectible',
        params: <String, dynamic>{'p_item_id': itemId},
      );
      _savedItems.removeWhere((SavedCollectible item) => item.itemId == itemId);
      return const MarketplaceActionResult<void>(
        success: true,
        message: 'Collectible removed from saved list.',
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<void>(
        success: false,
        message: _friendlyMessage(error),
      );
    }
  }

  @override
  Future<MarketplaceActionResult<void>> saveItem({required String itemId}) async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<void>(success: false, message: configError);
    }

    try {
      await _client!.rpc(
        'save_collectible',
        params: <String, dynamic>{'p_item_id': itemId},
      );
      await fetchSavedItems();
      return const MarketplaceActionResult<void>(
        success: true,
        message: 'Collectible saved to your watchlist.',
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<void>(
        success: false,
        message: _friendlyMessage(error),
      );
    }
  }

  @override
  Future<MarketplaceActionResult<ResaleCheckoutSession>> startResaleCheckout({
    required String itemId,
    required String buyerUserId,
    required String provider,
    String? successUrl,
    String? cancelUrl,
  }) async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<ResaleCheckoutSession>(
        success: false,
        message: configError,
      );
    }

    try {
      final dynamic response = await _client!.functions.invoke(
        'stripe-create-checkout-session',
        body: <String, dynamic>{
          'item_id': itemId,
          'success_url': successUrl,
          'cancel_url': cancelUrl,
        },
      );
      final Map<String, dynamic> row = _edgeResponseMap(response);
      if (row['error'] != null) {
        return MarketplaceActionResult<ResaleCheckoutSession>(
          success: false,
          message: row['error'].toString(),
        );
      }
      return MarketplaceActionResult<ResaleCheckoutSession>(
        success: true,
        message: 'Hosted Stripe checkout session created.',
        data: _checkoutSessionFromRow(row),
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<ResaleCheckoutSession>(
        success: false,
        message: _friendlyMessage(error),
      );
    } catch (error) {
      return MarketplaceActionResult<ResaleCheckoutSession>(
        success: false,
        message: error.toString(),
      );
    }
  }

  Map<String, dynamic> _edgeResponseMap(dynamic response) {
    if (response is Map<String, dynamic>) {
      return response;
    }
    final dynamic data = response?.data;
    if (data is Map<String, dynamic>) {
      return data;
    }
    return const <String, dynamic>{};
  }

  UniqueItem? _itemByQrToken(String qrToken) {
    for (final UniqueItem item in _items) {
      final String? knownQrToken = _qrTokenForItem(item.id);
      if (knownQrToken == qrToken) {
        return item;
      }
    }
    return null;
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

  ResaleCheckoutSession _checkoutSessionFromRow(Map<String, dynamic> row) {
    return ResaleCheckoutSession(
      orderId: row['order_id'].toString(),
      provider: row['provider'].toString(),
      status: row['status'].toString(),
      providerReference: row['provider_reference'].toString(),
      checkoutUrl: row['checkout_url']?.toString(),
      clientSecret: row['client_secret']?.toString(),
      expiresAt: row['expires_at'] == null
          ? null
          : DateTime.parse(row['expires_at'].toString()),
    );
  }

  CollectorNotification _notificationFromRow(Map<String, dynamic> row) {
    return CollectorNotification(
      id: row['notification_id'].toString(),
      title: row['title'].toString(),
      body: row['body'].toString(),
      createdAt: DateTime.parse(row['created_at'].toString()),
      read: row['is_read'] == true,
    );
  }

  PublicAuthenticityRecord _publicAuthenticityFromRow(
    Map<String, dynamic> row,
  ) {
    return PublicAuthenticityRecord(
      qrToken: row['public_qr_token'].toString(),
      serialNumber: row['serial_number'].toString(),
      state: itemStateFromKey(row['state'].toString()),
      garmentName: row['garment_name'].toString(),
      artworkTitle: row['artwork_title'].toString(),
      story: row['public_story']?.toString() ?? row['story'].toString(),
      artistName: row['artist_name'].toString(),
      authenticityStatus: row['authenticity_status'].toString(),
      publicStory: row['public_story']?.toString() ?? row['story'].toString(),
      ownershipVisibility: row['ownership_visibility'].toString(),
      verifiedTransferCount:
          (row['verified_transfer_count'] as num?)?.toInt() ?? 0,
    );
  }

  RefundRecord _refundFromRow(Map<String, dynamic> row) {
    return RefundRecord(
      refundId: row['refund_id'].toString(),
      orderId: row['order_id'].toString(),
      status: row['status'].toString(),
      amountCents: (row['amount_cents'] as num?)?.toInt() ?? 0,
      reason: row['reason'].toString(),
      providerReference: row['provider_reference']?.toString(),
      createdAt: DateTime.parse(row['created_at'].toString()),
    );
  }

  SavedCollectible _savedItemFromRow(Map<String, dynamic> row) {
    return SavedCollectible(
      itemId: row['item_id'].toString(),
      savedAt: DateTime.parse(row['saved_at'].toString()),
    );
  }

  ShipmentEvent _shipmentEventFromRow(Map<String, dynamic> row) {
    return ShipmentEvent(
      orderId: row['order_id'].toString(),
      status: row['status'].toString(),
      occurredAt: DateTime.parse(row['occurred_at'].toString()),
      carrier: row['carrier']?.toString(),
      trackingNumber: row['tracking_number']?.toString(),
      note: row['note']?.toString(),
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

  String? _qrTokenForItem(String itemId) {
    return _qrTokensByItemId[itemId];
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
    if (message.contains('Authentication required') ||
        message.contains('JWT') ||
        message.contains('permission denied')) {
      return 'Sign in with a real collector account to continue.';
    }
    if (message.contains(
      'Only the recorded owner, buyer, or admin can open a dispute',
    )) {
      return 'Only the verified owner or buyer can submit this dispute.';
    }
    if (message.contains('Authenticity token not found')) {
      return 'No verified collectible matched that QR token.';
    }
    if (message.contains('delivery') || message.contains('review window')) {
      return 'Delivery confirmation is still pending for this order.';
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
