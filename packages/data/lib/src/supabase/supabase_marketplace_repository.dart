// ignore_for_file: unnecessary_non_null_assertion

import 'dart:async';
import 'dart:typed_data';

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
  Map<String, List<ItemComment>> _commentsByItemId =
      <String, List<ItemComment>>{};
  Map<String, ManualPaymentOrder> _manualPaymentsByItemId =
      <String, ManualPaymentOrder>{};

  @override
  List<Listing> activeListings() => List<Listing>.unmodifiable(_listings);

  @override
  List<ItemComment> commentsForItem(String itemId) =>
      List<ItemComment>.unmodifiable(
        _commentsByItemId[itemId] ?? const <ItemComment>[],
      );

  @override
  ManualPaymentOrder? manualPaymentForItem(String itemId) =>
      _manualPaymentsByItemId[itemId];

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
  Future<MarketplaceActionResult<ItemComment>> addItemComment({
    required String itemId,
    required String body,
  }) async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<ItemComment>(
        success: false,
        message: configError,
      );
    }

    try {
      final dynamic row = await _client!.rpc(
        'add_item_comment',
        params: <String, dynamic>{
          'p_item_id': itemId,
          'p_body': body,
        },
      );
      final ItemComment comment = _itemCommentFromRow(
        row as Map<String, dynamic>,
      );
      _commentsByItemId[itemId] = <ItemComment>[
        comment,
        ...(_commentsByItemId[itemId] ?? const <ItemComment>[]),
      ];
      return MarketplaceActionResult<ItemComment>(
        success: true,
        message: 'Comment posted to the collectible conversation.',
        data: comment,
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<ItemComment>(
        success: false,
        message: _friendlyMessage(error),
      );
    }
  }

  @override
  Future<MarketplaceActionResult<ManualPaymentOrder>> submitManualPaymentProof({
    required String orderId,
    required String paymentMethod,
    required String payerName,
    required String payerPhone,
    required int paidAmountCents,
    required DateTime paidAt,
    required String? transactionReference,
    required Uint8List proofBytes,
    required String proofFileName,
    required String proofContentType,
  }) async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<ManualPaymentOrder>(
        success: false,
        message: configError,
      );
    }

    final User? currentUser = _client?.auth.currentUser;
    if (currentUser == null) {
      return const MarketplaceActionResult<ManualPaymentOrder>(
        success: false,
        message: 'Sign in with a real collector account to continue.',
      );
    }

    if (!_supportedProofContentTypes.contains(proofContentType)) {
      return const MarketplaceActionResult<ManualPaymentOrder>(
        success: false,
        message: 'Upload a PNG, JPG, WEBP, or GIF payment screenshot.',
      );
    }

    if (proofBytes.length > 8 * 1024 * 1024) {
      return const MarketplaceActionResult<ManualPaymentOrder>(
        success: false,
        message: 'Payment proof images must be 8 MB or smaller.',
      );
    }

    final String sanitizedFileName = proofFileName.replaceAll(
      RegExp(r'[^a-zA-Z0-9._-]'),
      '_',
    );
    final String storagePath =
        '${currentUser.id}/$orderId/${DateTime.now().millisecondsSinceEpoch}_$sanitizedFileName';

    try {
      await _client!.storage.from('payment-proofs').uploadBinary(
        storagePath,
        proofBytes,
        fileOptions: FileOptions(
          contentType: proofContentType,
          upsert: false,
        ),
      );

      final List<dynamic> rows =
          (await _client!.rpc(
                'submit_manual_payment_proof',
                params: <String, dynamic>{
                  'p_order_id': orderId,
                  'p_payment_method': paymentMethod,
                  'p_payer_name': payerName,
                  'p_payer_phone': payerPhone,
                  'p_paid_amount_cents': paidAmountCents,
                  'p_paid_at': paidAt.toUtc().toIso8601String(),
                  'p_transaction_reference': transactionReference,
                  'p_proof_bucket': 'payment-proofs',
                  'p_proof_path': storagePath,
                },
              ))
              as List<dynamic>;
      await refresh(userId: currentUser.id);
      final ManualPaymentOrder? paymentOrder = rows.isEmpty
          ? _manualPaymentByOrderId(orderId)
          : _manualPaymentOrderFromRow(rows.first as Map<String, dynamic>);
      return MarketplaceActionResult<ManualPaymentOrder>(
        success: true,
        message: 'Payment proof submitted for admin review.',
        data: paymentOrder,
      );
    } on StorageException catch (error) {
      return MarketplaceActionResult<ManualPaymentOrder>(
        success: false,
        message: error.message,
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<ManualPaymentOrder>(
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
  Future<MarketplaceActionResult<void>> markNotificationsRead({
    required List<String> notificationIds,
  }) async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<void>(success: false, message: configError);
    }
    if (notificationIds.isEmpty) {
      return const MarketplaceActionResult<void>(
        success: true,
        message: 'No notifications needed updating.',
      );
    }

    try {
      await _client!.rpc(
        'mark_my_notifications_read',
        params: <String, dynamic>{'p_notification_ids': notificationIds},
      );
      final Set<String> ids = notificationIds.toSet();
      _notifications = _notifications
          .map((CollectorNotification notification) {
            if (!ids.contains(notification.id) || notification.read) {
              return notification;
            }
            return CollectorNotification(
              id: notification.id,
              title: notification.title,
              body: notification.body,
              createdAt: notification.createdAt,
              read: true,
            );
          })
          .toList(growable: false);
      return const MarketplaceActionResult<void>(
        success: true,
        message: 'Notifications marked as read.',
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<void>(
        success: false,
        message: _friendlyMessage(error),
      );
    }
  }

  @override
  Stream<void> watchCustomerData({required String userId}) {
    final String? configError = _requireConfigured();
    if (configError != null || userId.trim().isEmpty) {
      return const Stream<void>.empty();
    }
    return Stream<void>.periodic(const Duration(seconds: 15), (_) {});
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
      _commentsByItemId = <String, List<ItemComment>>{};
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
    final List<dynamic> mediaRows = await _client!
        .from('media_assets')
        .select(
          'storage_bucket, storage_path, linked_entity_id, visibility, media_type',
        )
        .eq('linked_entity_type', 'unique_item')
        .eq('visibility', 'public');
    List<dynamic> myCollectibleRows = <dynamic>[];
    List<dynamic> savedItemRows = <dynamic>[];
    List<dynamic> notificationRows = <dynamic>[];
    List<dynamic> paymentOrderRows = <dynamic>[];
    if (currentUserId() != null) {
      myCollectibleRows =
          (await _client!.rpc('get_my_collectibles')) as List<dynamic>;
      savedItemRows =
          (await _client!.rpc('get_my_saved_collectibles')) as List<dynamic>;
      notificationRows =
          (await _client!.rpc('get_my_notifications')) as List<dynamic>;
      paymentOrderRows =
          (await _client!.rpc('get_my_order_payment_statuses'))
              as List<dynamic>;
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
    final Map<String, List<String>> mediaByItemId = <String, List<String>>{};
    for (final dynamic row in mediaRows) {
      final Map<String, dynamic> map = row as Map<String, dynamic>;
      final String itemId = map['linked_entity_id'].toString();
      final String url = _publicMediaUrl(map);
      mediaByItemId.putIfAbsent(itemId, () => <String>[]).add(url);
    }
    final Map<String, List<ItemComment>> commentsByItemId =
        <String, List<ItemComment>>{};
    for (final String itemId in mergedItems.keys) {
      final List<dynamic> commentRows =
          (await _client!.rpc(
                'get_public_item_comments',
                params: <String, dynamic>{'p_item_id': itemId},
              ))
              as List<dynamic>;
      commentsByItemId[itemId] = commentRows
          .map(
            (dynamic row) => _itemCommentFromRow(row as Map<String, dynamic>),
          )
          .toList();
    }
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
      ..replaceRange(
        0,
        mergedItems.length,
        mergedItems.values.map((UniqueItem item) {
          return item.copyWith(imageUrls: mediaByItemId[item.id] ?? const <String>[]);
        }),
      )
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
    _commentsByItemId = commentsByItemId;
    _manualPaymentsByItemId = <String, ManualPaymentOrder>{
      for (final dynamic row in paymentOrderRows)
        (row as Map<String, dynamic>)['item_id'].toString():
            _manualPaymentOrderFromRow(row),
    };
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
      if (_manualPaymentProviders.contains(provider)) {
        final Listing? listing = _activeListingForItem(itemId);
        if (listing == null) {
          return const MarketplaceActionResult<ResaleCheckoutSession>(
            success: false,
            message: 'Active resale listing not found.',
          );
        }
        final dynamic row = await _client!.rpc(
          'create_resale_checkout_session',
          params: <String, dynamic>{
            'p_listing_id': listing.id,
            'p_provider': provider,
            'p_success_url': null,
            'p_cancel_url': null,
          },
        );
        await refresh(userId: buyerUserId);
        return MarketplaceActionResult<ResaleCheckoutSession>(
          success: true,
          message: 'Manual payment instructions are ready.',
          data: _checkoutSessionFromRow(row as Map<String, dynamic>),
        );
      }

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

  ItemComment _itemCommentFromRow(Map<String, dynamic> row) {
    return ItemComment(
      id: row['comment_id'].toString(),
      itemId: row['item_id'].toString(),
      userDisplayName: row['user_display_name'].toString(),
      body: row['body'].toString(),
      createdAt: DateTime.parse(row['created_at'].toString()),
    );
  }

  String _publicMediaUrl(Map<String, dynamic> row) {
    final String bucket = row['storage_bucket'].toString();
    final String path = row['storage_path'].toString();
    if (bucket == 'external') {
      return path;
    }
    return _client!.storage.from(bucket).getPublicUrl(path);
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
      askingPrice: (row['asking_price_cents'] as num?)?.toInt(),
      imageUrls: fallback?.imageUrls ?? const <String>[],
    );
  }

  ManualPaymentOrder _manualPaymentOrderFromRow(Map<String, dynamic> row) {
    return ManualPaymentOrder(
      orderId: row['order_id'].toString(),
      itemId: row['item_id'].toString(),
      orderStatus: row['order_status'].toString(),
      paymentStatus: row['payment_status'].toString(),
      paymentProvider: row['payment_provider'].toString(),
      paymentReference: row['payment_reference'].toString(),
      amountCents: (row['total_cents'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(row['created_at'].toString()),
      reviewStatus: _nullableString(row['review_status']),
      paymentMethod: _nullableString(row['payment_method']),
      payerName: _nullableString(row['payer_name']),
      payerPhone: _nullableString(row['payer_phone']),
      submittedAmountCents: row['paid_amount_cents'] == null
          ? null
          : (row['paid_amount_cents'] as num).toInt(),
      paidAt: row['paid_at'] == null
          ? null
          : DateTime.parse(row['paid_at'].toString()),
      transactionReference: _nullableString(row['transaction_reference']),
      reviewNote: _nullableString(row['review_note']),
      submittedAt: row['proof_submitted_at'] == null
          ? null
          : DateTime.parse(row['proof_submitted_at'].toString()),
      reviewedAt: row['reviewed_at'] == null
          ? null
          : DateTime.parse(row['reviewed_at'].toString()),
    );
  }

  String? _qrTokenForItem(String itemId) {
    return _qrTokensByItemId[itemId];
  }

  ManualPaymentOrder? _manualPaymentByOrderId(String orderId) {
    for (final ManualPaymentOrder order in _manualPaymentsByItemId.values) {
      if (order.orderId == orderId) {
        return order;
      }
    }
    return null;
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
    if (message.contains('A payment proof is already awaiting review')) {
      return 'A payment proof is already under review for this order.';
    }
    if (message.contains('Payment proof upload is required')) {
      return 'Upload a payment screenshot before submitting for review.';
    }
    if (message.contains('Paid amount must be greater than zero')) {
      return 'Enter the amount you paid before sending the proof.';
    }
    if (message.contains('Order is not awaiting payment review')) {
      return 'This order is not accepting a new payment proof right now.';
    }
    return message;
  }

  String? _nullableString(dynamic value) {
    if (value == null) {
      return null;
    }
    final String text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static const Set<String> _manualPaymentProviders = <String>{
    'manual_transfer',
  };

  static const Set<String> _supportedProofContentTypes = <String>{
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
  };

  String? _requireConfigured() {
    if (_client == null) {
      return _configurationError ?? 'Supabase is not configured for this app.';
    }
    return null;
  }
}
