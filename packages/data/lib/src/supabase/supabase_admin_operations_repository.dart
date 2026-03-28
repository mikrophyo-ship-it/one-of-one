// ignore_for_file: unnecessary_non_null_assertion

import 'dart:typed_data';

import 'package:domain/domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repositories/admin_operations_repository.dart';

class SupabaseAdminOperationsRepository implements AdminOperationsRepository {
  SupabaseAdminOperationsRepository({
    SupabaseClient? client,
    String? configurationError,
  }) : _client = client,
       _configurationError = configurationError;

  final SupabaseClient? _client;
  final String? _configurationError;

  AdminOperationsSnapshot? _snapshot;

  @override
  AdminOperationsSnapshot? snapshot() => _snapshot;

  @override
  Future<MarketplaceActionResult<AdminOperationsSnapshot>> refresh() async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<AdminOperationsSnapshot>(
        success: false,
        message: configError,
      );
    }

    final MarketplaceActionResult<void> accessCheck =
        await _assertAdminAccess();
    if (!accessCheck.success) {
      return MarketplaceActionResult<AdminOperationsSnapshot>(
        success: false,
        message: accessCheck.message,
      );
    }

    try {
      final List<dynamic> dashboardRows =
          (await _client!.rpc('get_admin_dashboard_overview')) as List<dynamic>;
      final List<dynamic> customerRows =
          (await _client!.rpc('get_admin_customer_overview')) as List<dynamic>;
      final List<dynamic> listingRows =
          (await _client!.rpc('get_admin_listing_queue')) as List<dynamic>;
      final List<dynamic> disputeRows =
          (await _client!.rpc('get_admin_dispute_queue')) as List<dynamic>;
      final List<dynamic> orderRows =
          (await _client!.rpc('get_admin_order_queue')) as List<dynamic>;
      final List<dynamic> artistRows =
          (await _client!.rpc('get_admin_artist_directory')) as List<dynamic>;
      final List<dynamic> artworkRows =
          (await _client!.rpc('get_admin_artwork_directory')) as List<dynamic>;
      final List<dynamic> inventoryRows =
          (await _client!.rpc('get_admin_inventory_directory'))
              as List<dynamic>;
      final List<dynamic> garmentProductRows =
          (await _client!.rpc('get_admin_garment_product_directory'))
              as List<dynamic>;
      final List<dynamic> financeRows =
          (await _client!.rpc('get_admin_finance_report')) as List<dynamic>;
      final List<dynamic> auditRows =
          (await _client!.rpc('get_admin_audit_feed')) as List<dynamic>;
      final Map<String, dynamic> settingsRow = await _client!
          .from('platform_settings')
          .select(
            'platform_fee_bps, default_royalty_bps, marketplace_rules, brand_settings',
          )
          .eq('id', true)
          .single();

      _snapshot = AdminOperationsSnapshot(
        dashboard: _dashboardFromRow(
          dashboardRows.isEmpty
              ? const <String, dynamic>{}
              : dashboardRows.first as Map<String, dynamic>,
        ),
        customers: customerRows
            .map((dynamic row) => _customerFromRow(row as Map<String, dynamic>))
            .toList(),
        listings: listingRows
            .map((dynamic row) => _listingFromRow(row as Map<String, dynamic>))
            .toList(),
        disputes: disputeRows
            .map((dynamic row) => _disputeFromRow(row as Map<String, dynamic>))
            .toList(),
        orders: await Future.wait(
          orderRows.map(
            (dynamic row) => _orderFromRow(row as Map<String, dynamic>),
          ),
        ),
        artists: artistRows
            .map((dynamic row) => _artistFromRow(row as Map<String, dynamic>))
            .toList(),
        artworks: artworkRows
            .map((dynamic row) => _artworkFromRow(row as Map<String, dynamic>))
            .toList(),
        inventory: inventoryRows
            .map(
              (dynamic row) => _inventoryFromRow(row as Map<String, dynamic>),
            )
            .toList(),
        garmentProducts: garmentProductRows
            .map(
              (dynamic row) =>
                  _garmentProductFromRow(row as Map<String, dynamic>),
            )
            .toList(),
        finance: financeRows
            .map((dynamic row) => _financeFromRow(row as Map<String, dynamic>))
            .toList(),
        audits: auditRows
            .map((dynamic row) => _auditFromRow(row as Map<String, dynamic>))
            .toList(),
        settings: _settingsFromRow(settingsRow),
      );

      return MarketplaceActionResult<AdminOperationsSnapshot>(
        success: true,
        message: 'Admin operations refreshed from Supabase.',
        data: _snapshot,
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<AdminOperationsSnapshot>(
        success: false,
        message: _friendlyMessage(error.message),
      );
    }
  }

  @override
  Future<MarketplaceActionResult<void>> flagItemStatus({
    required String itemId,
    required String targetState,
    required String note,
  }) async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<void>(
        success: false,
        message: configError,
      );
    }

    try {
      await _client!.rpc(
        'admin_flag_item_status',
        params: <String, dynamic>{
          'p_item_id': itemId,
          'p_target_state': targetState,
          'p_note': note.isEmpty ? null : note,
        },
      );
      final MarketplaceActionResult<AdminOperationsSnapshot> refreshResult =
          await refresh();
      return MarketplaceActionResult<void>(
        success: refreshResult.success,
        message: refreshResult.success
            ? 'Item status updated by admin control.'
            : refreshResult.message,
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<void>(
        success: false,
        message: _friendlyMessage(error.message),
      );
    }
  }

  @override
  Future<MarketplaceActionResult<AdminListingRecord>> moderateListing({
    required String listingId,
    required String action,
    required String note,
  }) async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<AdminListingRecord>(
        success: false,
        message: configError,
      );
    }

    try {
      await _client!.rpc(
        'admin_moderate_listing',
        params: <String, dynamic>{
          'p_listing_id': listingId,
          'p_action': action,
          'p_note': note.isEmpty ? null : note,
        },
      );
      await refresh();
      return MarketplaceActionResult<AdminListingRecord>(
        success: true,
        message: 'Listing moderation was saved.',
        data: _findListing(listingId),
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<AdminListingRecord>(
        success: false,
        message: _friendlyMessage(error.message),
      );
    }
  }

  @override
  Future<MarketplaceActionResult<AdminCustomerRecord>> setUserRole({
    required String userId,
    required String role,
  }) async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<AdminCustomerRecord>(
        success: false,
        message: configError,
      );
    }

    try {
      await _client!.rpc(
        'admin_set_user_role',
        params: <String, dynamic>{'p_user_id': userId, 'p_role': role},
      );
      await refresh();
      return MarketplaceActionResult<AdminCustomerRecord>(
        success: true,
        message: 'Customer role updated.',
        data: _findCustomer(userId),
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<AdminCustomerRecord>(
        success: false,
        message: _friendlyMessage(error.message),
      );
    }
  }

  @override
  Future<MarketplaceActionResult<AdminArtistRecord>> upsertArtist({
    String? artistId,
    required String displayName,
    required String slug,
    required int royaltyBps,
    required String authenticityStatement,
    required bool isActive,
  }) async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<AdminArtistRecord>(
        success: false,
        message: configError,
      );
    }

    try {
      await _client!.rpc(
        'admin_upsert_artist',
        params: <String, dynamic>{
          'p_artist_id': artistId,
          'p_display_name': displayName,
          'p_slug': slug,
          'p_royalty_bps': royaltyBps,
          'p_authenticity_statement': authenticityStatement,
          'p_is_active': isActive,
        },
      );
      await refresh();
      return MarketplaceActionResult<AdminArtistRecord>(
        success: true,
        message: 'Artist saved.',
        data: _findArtist(artistId, slug),
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<AdminArtistRecord>(
        success: false,
        message: _friendlyMessage(error.message),
      );
    }
  }

  @override
  Future<MarketplaceActionResult<AdminArtworkRecord>> upsertArtwork({
    String? artworkId,
    required String artistId,
    required String title,
    required String story,
    required List<String> provenanceProof,
    DateTime? creationDate,
  }) async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<AdminArtworkRecord>(
        success: false,
        message: configError,
      );
    }

    try {
      await _client!.rpc(
        'admin_upsert_artwork',
        params: <String, dynamic>{
          'p_artwork_id': artworkId,
          'p_artist_id': artistId,
          'p_title': title,
          'p_story': story,
          'p_provenance_proof': provenanceProof,
          'p_creation_date': creationDate?.toIso8601String(),
        },
      );
      await refresh();
      return MarketplaceActionResult<AdminArtworkRecord>(
        success: true,
        message: 'Artwork saved.',
        data: _findArtwork(artworkId, title),
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<AdminArtworkRecord>(
        success: false,
        message: _friendlyMessage(error.message),
      );
    }
  }

  @override
  Future<MarketplaceActionResult<AdminInventoryRecord>> upsertInventoryItem({
    String? itemId,
    required String artistId,
    required String artworkId,
    required String garmentProductId,
    required String serialNumber,
    required String itemState,
  }) async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<AdminInventoryRecord>(
        success: false,
        message: configError,
      );
    }

    try {
      await _client!.rpc(
        'admin_upsert_inventory_item',
        params: <String, dynamic>{
          'p_item_id': itemId,
          'p_artist_id': artistId,
          'p_artwork_id': artworkId,
          'p_garment_product_id': garmentProductId,
          'p_serial_number': serialNumber,
          'p_item_state': itemState,
        },
      );
      await refresh();
      return MarketplaceActionResult<AdminInventoryRecord>(
        success: true,
        message: 'Inventory item saved.',
        data: _findInventory(itemId, serialNumber),
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<AdminInventoryRecord>(
        success: false,
        message: _friendlyMessage(error.message),
      );
    }
  }

  @override
  Future<MarketplaceActionResult<AdminInventoryRecord>>
  createAuthenticityRecord({required String itemId}) async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<AdminInventoryRecord>(
        success: false,
        message: configError,
      );
    }

    try {
      await _client!.rpc(
        'admin_create_item_authenticity_record',
        params: <String, dynamic>{'p_item_id': itemId},
      );
      await refresh();
      return MarketplaceActionResult<AdminInventoryRecord>(
        success: true,
        message: 'Authenticity record linked to inventory item.',
        data: _findInventory(itemId, ''),
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<AdminInventoryRecord>(
        success: false,
        message: _friendlyMessage(error.message),
      );
    }
  }

  @override
  Future<MarketplaceActionResult<AdminInventoryRecord>> upsertInventoryListing({
    required String itemId,
    required int askingPriceCents,
    required String status,
  }) async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<AdminInventoryRecord>(
        success: false,
        message: configError,
      );
    }

    try {
      await _client!.rpc(
        'admin_upsert_item_listing',
        params: <String, dynamic>{
          'p_item_id': itemId,
          'p_asking_price_cents': askingPriceCents,
          'p_status': status,
        },
      );
      await refresh();
      return MarketplaceActionResult<AdminInventoryRecord>(
        success: true,
        message: status == 'active'
            ? 'Listing published for sale.'
            : 'Listing saved.',
        data: _findInventory(itemId, ''),
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<AdminInventoryRecord>(
        success: false,
        message: _friendlyMessage(error.message),
      );
    }
  }

  @override
  Future<MarketplaceActionResult<AdminClaimPacketData>> revealItemClaimCode({
    required String itemId,
    required String reason,
  }) async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<AdminClaimPacketData>(
        success: false,
        message: configError,
      );
    }

    try {
      final Map<String, dynamic> row =
          (await _client!.rpc(
                'admin_reveal_item_claim_code',
                params: <String, dynamic>{
                  'p_item_id': itemId,
                  'p_reason': reason,
                },
              ))
              as Map<String, dynamic>;
      await refresh();
      return MarketplaceActionResult<AdminClaimPacketData>(
        success: true,
        message: 'Hidden claim code opened in secure view.',
        data: _claimPacketFromRow(row),
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<AdminClaimPacketData>(
        success: false,
        message: _friendlyMessage(error.message),
      );
    }
  }

  @override
  Future<MarketplaceActionResult<AdminClaimPacketData>> generateClaimPacket({
    required String itemId,
    required String reason,
  }) async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<AdminClaimPacketData>(
        success: false,
        message: configError,
      );
    }

    try {
      final Map<String, dynamic> row =
          (await _client!.rpc(
                'admin_generate_claim_packet',
                params: <String, dynamic>{
                  'p_item_id': itemId,
                  'p_reason': reason,
                },
              ))
              as Map<String, dynamic>;
      await refresh();
      return MarketplaceActionResult<AdminClaimPacketData>(
        success: true,
        message: 'Claim packet opened in secure print view.',
        data: _claimPacketFromRow(row),
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<AdminClaimPacketData>(
        success: false,
        message: _friendlyMessage(error.message),
      );
    }
  }

  @override
  Future<MarketplaceActionResult<void>> uploadInventoryImage({
    required String itemId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<void>(
        success: false,
        message: configError,
      );
    }

    final MarketplaceActionResult<void> accessCheck =
        await _assertAdminAccess();
    if (!accessCheck.success) {
      return MarketplaceActionResult<void>(
        success: false,
        message: accessCheck.message,
      );
    }

    final String sanitizedName = fileName.replaceAll(
      RegExp(r'[^a-zA-Z0-9._-]'),
      '_',
    );
    final String storagePath =
        'inventory/$itemId/${DateTime.now().millisecondsSinceEpoch}_$sanitizedName';

    try {
      await _client!.storage
          .from('garment-editorial')
          .uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: false),
          );
      await _client!.rpc(
        'admin_attach_item_media_asset',
        params: <String, dynamic>{
          'p_item_id': itemId,
          'p_storage_bucket': 'garment-editorial',
          'p_storage_path': storagePath,
          'p_media_type': contentType,
          'p_visibility': 'public',
        },
      );
      return const MarketplaceActionResult<void>(
        success: true,
        message: 'Editorial image uploaded for the collectible.',
      );
    } on PostgrestException catch (error) {
      try {
        await _client!.storage.from('garment-editorial').remove(<String>[
          storagePath,
        ]);
      } on StorageException {
        // Keep the original RPC failure for the operator; storage cleanup can be retried manually.
      }
      return MarketplaceActionResult<void>(
        success: false,
        message: _friendlyMessage(error.message),
      );
    } on StorageException catch (error) {
      return MarketplaceActionResult<void>(
        success: false,
        message: error.toString(),
      );
    } catch (error) {
      return MarketplaceActionResult<void>(
        success: false,
        message: error.toString(),
      );
    }
  }

  @override
  Future<MarketplaceActionResult<void>> removeInventoryImage({
    required String itemId,
  }) async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<void>(
        success: false,
        message: configError,
      );
    }

    final MarketplaceActionResult<void> accessCheck =
        await _assertAdminAccess();
    if (!accessCheck.success) {
      return MarketplaceActionResult<void>(
        success: false,
        message: accessCheck.message,
      );
    }

    try {
      final List<dynamic> deletedRows =
          (await _client!.rpc(
                'admin_remove_item_media_assets',
                params: <String, dynamic>{'p_item_id': itemId},
              ))
              as List<dynamic>;

      final Map<String, List<String>> pathsByBucket = <String, List<String>>{};
      for (final dynamic row in deletedRows) {
        final Map<String, dynamic> data = row as Map<String, dynamic>;
        final String? bucket = _nullableString(data['storage_bucket']);
        final String? path = _nullableString(data['storage_path']);
        if (bucket == null || path == null) {
          continue;
        }
        pathsByBucket.putIfAbsent(bucket, () => <String>[]).add(path);
      }

      String? cleanupWarning;
      for (final MapEntry<String, List<String>> entry
          in pathsByBucket.entries) {
        try {
          await _client!.storage.from(entry.key).remove(entry.value);
        } on StorageException {
          cleanupWarning =
              'Catalog photo removed, but storage cleanup needs a follow-up check.';
        }
      }

      return MarketplaceActionResult<void>(
        success: true,
        message:
            cleanupWarning ?? 'Editorial image removed from the collectible.',
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<void>(
        success: false,
        message: _friendlyMessage(error.message),
      );
    } catch (error) {
      return MarketplaceActionResult<void>(
        success: false,
        message: error.toString(),
      );
    }
  }

  @override
  Future<MarketplaceActionResult<PlatformSettingsSnapshot>> updateSettings({
    required int platformFeeBps,
    required int defaultRoyaltyBps,
    required Map<String, dynamic> marketplaceRules,
    required Map<String, dynamic> brandSettings,
  }) async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<PlatformSettingsSnapshot>(
        success: false,
        message: configError,
      );
    }

    try {
      final dynamic row = await _client!.rpc(
        'admin_update_platform_settings',
        params: <String, dynamic>{
          'p_platform_fee_bps': platformFeeBps,
          'p_default_royalty_bps': defaultRoyaltyBps,
          'p_marketplace_rules': marketplaceRules,
          'p_brand_settings': brandSettings,
        },
      );
      await refresh();
      return MarketplaceActionResult<PlatformSettingsSnapshot>(
        success: true,
        message: 'Platform settings saved.',
        data: row == null
            ? _snapshot?.settings
            : _settingsFromRow(row as Map<String, dynamic>),
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<PlatformSettingsSnapshot>(
        success: false,
        message: _friendlyMessage(error.message),
      );
    }
  }

  @override
  Future<MarketplaceActionResult<AdminDisputeRecord>> updateDisputeStatus({
    required String disputeId,
    required String status,
    required String note,
    required bool releaseItem,
    String? releaseTargetState,
  }) async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<AdminDisputeRecord>(
        success: false,
        message: configError,
      );
    }

    try {
      await _client!.rpc(
        'admin_update_dispute_status',
        params: <String, dynamic>{
          'p_dispute_id': disputeId,
          'p_status': status,
          'p_note': note.isEmpty ? null : note,
          'p_release_item': releaseItem,
          'p_release_target_state': releaseTargetState,
        },
      );
      await refresh();
      return MarketplaceActionResult<AdminDisputeRecord>(
        success: true,
        message: 'Dispute status updated.',
        data: _findDispute(disputeId),
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<AdminDisputeRecord>(
        success: false,
        message: _friendlyMessage(error.message),
      );
    }
  }

  @override
  Future<MarketplaceActionResult<AdminOrderRecord>> reviewManualPayment({
    required String orderId,
    required String action,
    required String note,
  }) async {
    final String? configError = _requireConfigured();
    if (configError != null) {
      return MarketplaceActionResult<AdminOrderRecord>(
        success: false,
        message: configError,
      );
    }

    try {
      await _client!.rpc(
        'admin_review_manual_payment',
        params: <String, dynamic>{
          'p_order_id': orderId,
          'p_action': action,
          'p_note': note.isEmpty ? null : note,
        },
      );
      await refresh();
      return MarketplaceActionResult<AdminOrderRecord>(
        success: true,
        message: action == 'approve'
            ? 'Payment proof approved and order advanced to fulfillment.'
            : action == 'reject'
            ? 'Payment proof rejected and the order was released.'
            : action == 'cancel'
            ? 'Order cancelled and removed from the active review queue.'
            : 'Payment proof marked for resubmission.',
        data: _findOrder(orderId),
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<AdminOrderRecord>(
        success: false,
        message: _friendlyMessage(error.message),
      );
    }
  }

  Future<MarketplaceActionResult<void>> _assertAdminAccess() async {
    final String? currentUserId = _client?.auth.currentUser?.id;
    if (currentUserId == null) {
      return const MarketplaceActionResult<void>(
        success: false,
        message: 'Sign in with an admin-approved account to continue.',
      );
    }

    try {
      final Map<String, dynamic> profile = await _client!
          .from('user_profiles')
          .select('role')
          .eq('user_id', currentUserId)
          .single();
      const Set<String> adminRoles = <String>{
        'admin',
        'owner',
        'artist_manager',
        'support',
      };
      final String role = profile['role'].toString();
      if (!adminRoles.contains(role)) {
        return const MarketplaceActionResult<void>(
          success: false,
          message: 'This account does not have admin console access.',
        );
      }
      return const MarketplaceActionResult<void>(
        success: true,
        message: 'Admin access confirmed.',
      );
    } on PostgrestException catch (error) {
      return MarketplaceActionResult<void>(
        success: false,
        message: _friendlyMessage(error.message),
      );
    }
  }

  AdminDashboardSnapshot _dashboardFromRow(Map<String, dynamic> row) {
    return AdminDashboardSnapshot(
      openDisputes: _toInt(row['open_disputes']),
      activeListings: _toInt(row['active_listings']),
      paymentPendingOrders: _toInt(row['payment_pending_orders']),
      deliveryPendingOrders: _toInt(row['delivery_pending_orders']),
      payoutPendingOrders: _toInt(row['payout_pending_orders']),
      refundPendingOrders: _toInt(row['refund_pending_orders']),
      grossSalesCents: _toInt(row['gross_sales_cents']),
      royaltyCents: _toInt(row['royalty_cents']),
      platformFeeCents: _toInt(row['platform_fee_cents']),
      frozenItems: _toInt(row['frozen_items']),
      stolenItems: _toInt(row['stolen_items']),
    );
  }

  AdminCustomerRecord _customerFromRow(Map<String, dynamic> row) {
    return AdminCustomerRecord(
      userId: row['user_id'].toString(),
      displayName: row['display_name'].toString(),
      username: _nullableString(row['username']),
      role: row['role'].toString(),
      createdAt: DateTime.parse(row['created_at'].toString()),
      ownedItemCount: _toInt(row['owned_item_count']),
      openDisputeCount: _toInt(row['open_dispute_count']),
      buyOrderCount: _toInt(row['buy_order_count']),
      sellOrderCount: _toInt(row['sell_order_count']),
      lastActivityAt: _nullableDateTime(row['last_activity_at']),
    );
  }

  AdminListingRecord _listingFromRow(Map<String, dynamic> row) {
    return AdminListingRecord(
      listingId: row['listing_id'].toString(),
      itemId: row['item_id'].toString(),
      sellerUserId: row['seller_user_id'].toString(),
      listingStatus: row['listing_status'].toString(),
      askingPriceCents: _toInt(row['asking_price_cents']),
      createdAt: DateTime.parse(row['created_at'].toString()),
      serialNumber: row['serial_number'].toString(),
      itemState: row['item_state'].toString(),
      garmentName: row['garment_name'].toString(),
      artworkTitle: row['artwork_title'].toString(),
      artistName: row['artist_name'].toString(),
      sellerDisplayName: _nullableString(row['seller_display_name']),
      sellerUsername: _nullableString(row['seller_username']),
    );
  }

  AdminDisputeRecord _disputeFromRow(Map<String, dynamic> row) {
    return AdminDisputeRecord(
      disputeId: row['dispute_id'].toString(),
      itemId: row['item_id'].toString(),
      orderId: _nullableString(row['order_id']),
      disputeStatus: row['dispute_status'].toString(),
      reason: row['reason'].toString(),
      details: _nullableString(row['details']),
      createdAt: DateTime.parse(row['created_at'].toString()),
      reportedByUserId: row['reported_by_user_id'].toString(),
      reporterDisplayName: _nullableString(row['reporter_display_name']),
      reporterUsername: _nullableString(row['reporter_username']),
      serialNumber: row['serial_number'].toString(),
      itemState: row['item_state'].toString(),
      garmentName: row['garment_name'].toString(),
      artworkTitle: row['artwork_title'].toString(),
      artistName: row['artist_name'].toString(),
      latestListingStatus: _nullableString(row['latest_listing_status']),
    );
  }

  Future<AdminOrderRecord> _orderFromRow(Map<String, dynamic> row) async {
    String? paymentProofUrl;
    final String? proofBucket = _nullableString(row['payment_proof_bucket']);
    final String? proofPath = _nullableString(row['payment_proof_path']);
    if (proofBucket != null && proofPath != null) {
      try {
        paymentProofUrl = await _client!.storage
            .from(proofBucket)
            .createSignedUrl(proofPath, 3600);
      } on StorageException {
        paymentProofUrl = null;
      }
    }

    return AdminOrderRecord(
      orderId: row['order_id'].toString(),
      listingId: _nullableString(row['listing_id']),
      orderStatus: row['order_status'].toString(),
      subtotalCents: _toInt(row['subtotal_cents']),
      totalCents: _toInt(row['total_cents']),
      createdAt: DateTime.parse(row['created_at'].toString()),
      itemId: row['item_id'].toString(),
      serialNumber: row['serial_number'].toString(),
      itemState: row['item_state'].toString(),
      garmentName: row['garment_name'].toString(),
      artworkTitle: row['artwork_title'].toString(),
      artistName: row['artist_name'].toString(),
      buyerDisplayName: _nullableString(row['buyer_display_name']),
      sellerDisplayName: _nullableString(row['seller_display_name']),
      listingStatus: _nullableString(row['listing_status']),
      paymentStatus: _nullableString(row['payment_status']),
      paymentProvider: _nullableString(row['payment_provider']),
      shipmentStatus: _nullableString(row['shipment_status']),
      shipmentCarrier: _nullableString(row['shipment_carrier']),
      trackingNumber: _nullableString(row['tracking_number']),
      sellerPayoutStatus: _nullableString(row['seller_payout_status']),
      royaltyStatus: _nullableString(row['royalty_status']),
      platformFeeStatus: _nullableString(row['platform_fee_status']),
      manualPaymentReviewStatus: _nullableString(
        row['manual_payment_review_status'],
      ),
      manualPaymentMethod: _nullableString(row['manual_payment_method']),
      payerName: _nullableString(row['payer_name']),
      payerPhone: _nullableString(row['payer_phone']),
      submittedAmountCents: row['submitted_amount_cents'] == null
          ? null
          : _toInt(row['submitted_amount_cents']),
      paidAt: _nullableDateTime(row['paid_at']),
      transactionReference: _nullableString(row['transaction_reference']),
      paymentProofBucket: proofBucket,
      paymentProofPath: proofPath,
      paymentProofUrl: paymentProofUrl,
      paymentReviewNote: _nullableString(row['payment_review_note']),
      reviewedAt: _nullableDateTime(row['reviewed_at']),
      reviewedByDisplayName: _nullableString(row['reviewed_by_display_name']),
    );
  }

  AdminArtistRecord _artistFromRow(Map<String, dynamic> row) {
    return AdminArtistRecord(
      artistId: row['artist_id'].toString(),
      displayName: row['display_name'].toString(),
      slug: row['slug'].toString(),
      royaltyBps: _toInt(row['royalty_bps']),
      isActive: row['is_active'] == true,
      artworkCount: _toInt(row['artwork_count']),
      inventoryCount: _toInt(row['inventory_count']),
    );
  }

  AdminArtworkRecord _artworkFromRow(Map<String, dynamic> row) {
    return AdminArtworkRecord(
      artworkId: row['artwork_id'].toString(),
      artistId: row['artist_id'].toString(),
      artistName: row['artist_name'].toString(),
      title: row['title'].toString(),
      creationDate: _nullableDateTime(row['creation_date']),
      inventoryCount: _toInt(row['inventory_count']),
    );
  }

  AdminInventoryRecord _inventoryFromRow(Map<String, dynamic> row) {
    return AdminInventoryRecord(
      itemId: row['item_id'].toString(),
      serialNumber: row['serial_number'].toString(),
      createdAt: DateTime.parse(row['created_at'].toString()),
      artistName: row['artist_name'].toString(),
      artworkTitle: row['artwork_title'].toString(),
      garmentName: row['garment_name'].toString(),
      itemState: row['item_state'].toString(),
      ownerDisplayLabel: row['owner_display_label'].toString(),
      hasAuthenticityRecord: row['has_authenticity_record'] == true,
      authenticityStatus: _nullableString(row['authenticity_status']),
      listingId: _nullableString(row['listing_id']),
      listingStatus: _nullableString(row['listing_status']),
      askingPriceCents: row['asking_price_cents'] == null
          ? null
          : _toInt(row['asking_price_cents']),
      customerVisible: row['customer_visible'] == true,
      buyable: row['buyable'] == true,
      qrReady: row['qr_ready'] == true,
      claimPacketReady: row['claim_packet_ready'] == true,
      claimCodeRevealState:
          _nullableString(row['claim_code_reveal_state']) ?? 'unavailable',
      hasEditorialImage: row['has_editorial_image'] == true,
    );
  }

  AdminClaimPacketData _claimPacketFromRow(Map<String, dynamic> row) {
    return AdminClaimPacketData(
      itemId: row['item_id'].toString(),
      serialNumber: row['serial_number'].toString(),
      artistName: row['artist_name'].toString(),
      artworkTitle: row['artwork_title'].toString(),
      garmentName: row['garment_name'].toString(),
      publicQrToken: row['public_qr_token'].toString(),
      verificationUri: row['verification_uri'].toString(),
      hiddenClaimCode: row['hidden_claim_code'].toString(),
      claimCodeRevealState: row['claim_code_reveal_state'].toString(),
      revealAction: row['reveal_action'].toString(),
    );
  }

  AdminGarmentProductRecord _garmentProductFromRow(Map<String, dynamic> row) {
    return AdminGarmentProductRecord(
      garmentProductId: row['garment_product_id'].toString(),
      sku: row['sku'].toString(),
      name: row['name'].toString(),
      silhouette: _nullableString(row['silhouette']),
      sizeLabel: _nullableString(row['size_label']),
      colorway: _nullableString(row['colorway']),
      basePriceCents: _toInt(row['base_price_cents']),
    );
  }

  AdminFinanceRecord _financeFromRow(Map<String, dynamic> row) {
    return AdminFinanceRecord(
      orderId: row['order_id'].toString(),
      paymentStatus: row['payment_status'].toString(),
      shipmentStatus: row['shipment_status'].toString(),
      sellerPayoutStatus: row['seller_payout_status'].toString(),
      royaltyStatus: row['royalty_status'].toString(),
      platformFeeStatus: row['platform_fee_status'].toString(),
      totalCents: _toInt(row['total_cents']),
    );
  }

  AdminAuditRecord _auditFromRow(Map<String, dynamic> row) {
    return AdminAuditRecord(
      auditId: row['audit_id'].toString(),
      createdAt: DateTime.parse(row['created_at'].toString()),
      entityType: row['entity_type'].toString(),
      entityId: _nullableString(row['entity_id']),
      action: row['action'].toString(),
      payload:
          (row['payload'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
      actorDisplayName: _nullableString(row['actor_display_name']),
      actorUsername: _nullableString(row['actor_username']),
    );
  }

  PlatformSettingsSnapshot _settingsFromRow(Map<String, dynamic> row) {
    return PlatformSettingsSnapshot(
      platformFeeBps: _toInt(row['platform_fee_bps']),
      defaultRoyaltyBps: _toInt(row['default_royalty_bps']),
      marketplaceRules:
          (row['marketplace_rules'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
      brandSettings:
          (row['brand_settings'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
    );
  }

  AdminCustomerRecord? _findCustomer(String userId) {
    for (final AdminCustomerRecord customer
        in _snapshot?.customers ?? const <AdminCustomerRecord>[]) {
      if (customer.userId == userId) {
        return customer;
      }
    }
    return null;
  }

  AdminDisputeRecord? _findDispute(String disputeId) {
    for (final AdminDisputeRecord dispute
        in _snapshot?.disputes ?? const <AdminDisputeRecord>[]) {
      if (dispute.disputeId == disputeId) {
        return dispute;
      }
    }
    return null;
  }

  AdminListingRecord? _findListing(String listingId) {
    for (final AdminListingRecord listing
        in _snapshot?.listings ?? const <AdminListingRecord>[]) {
      if (listing.listingId == listingId) {
        return listing;
      }
    }
    return null;
  }

  AdminArtistRecord? _findArtist(String? artistId, String slug) {
    for (final AdminArtistRecord artist
        in _snapshot?.artists ?? const <AdminArtistRecord>[]) {
      if ((artistId != null && artist.artistId == artistId) ||
          artist.slug == slug) {
        return artist;
      }
    }
    return null;
  }

  AdminArtworkRecord? _findArtwork(String? artworkId, String title) {
    for (final AdminArtworkRecord artwork
        in _snapshot?.artworks ?? const <AdminArtworkRecord>[]) {
      if ((artworkId != null && artwork.artworkId == artworkId) ||
          artwork.title == title) {
        return artwork;
      }
    }
    return null;
  }

  AdminInventoryRecord? _findInventory(String? itemId, String serialNumber) {
    for (final AdminInventoryRecord inventory
        in _snapshot?.inventory ?? const <AdminInventoryRecord>[]) {
      if ((itemId != null && inventory.itemId == itemId) ||
          inventory.serialNumber == serialNumber) {
        return inventory;
      }
    }
    return null;
  }

  AdminOrderRecord? _findOrder(String orderId) {
    for (final AdminOrderRecord order
        in _snapshot?.orders ?? const <AdminOrderRecord>[]) {
      if (order.orderId == orderId) {
        return order;
      }
    }
    return null;
  }

  String _friendlyMessage(String message) {
    if (message.contains('Admin access required')) {
      return 'Sign in with an admin-approved account to continue.';
    }
    if (message.contains('invalid input syntax for type uuid')) {
      return 'One of the admin form ids is not a valid UUID. For inventory creation, garment product id must be the UUID from public.garment_products.id.';
    }
    if (message.contains('permission denied') || message.contains('JWT')) {
      return 'This admin console needs a real authenticated session.';
    }
    if (message.contains('Unsafe release target state')) {
      return 'That item release state would violate marketplace controls.';
    }
    if (message.contains(
      'JSON object requested, multiple (or no) rows returned',
    )) {
      return 'This account does not have admin console access.';
    }
    if (message.contains('Authenticity record already exists')) {
      return 'This item already has a linked authenticity record.';
    }
    if (message.contains('Listing price must be greater than zero')) {
      return 'Enter a listing price greater than zero.';
    }
    if (message.contains('Restricted items cannot be listed')) {
      return 'Disputed, frozen, stolen, or archived items cannot be listed.';
    }
    if (message.contains('Listing already exists for this item')) {
      return 'This item already has an operational listing record.';
    }
    if (message.contains('Editorial image already attached for this item')) {
      return 'This collectible already has an editorial photo. Remove it before uploading a replacement.';
    }
    if (message.contains('Editorial image not found for this item')) {
      return 'No editorial photo is attached to this collectible yet.';
    }
    if (message.contains('Create authenticity record first')) {
      return 'Create the item authenticity record before publishing it to customers or preparing a claim packet.';
    }
    if (message.contains('Claim code already revealed')) {
      return 'This item already had its hidden claim code revealed once and can no longer be reopened from the console.';
    }
    if (message.contains('Claim packet already generated')) {
      return 'This item already generated a printable claim packet once and cannot open another packet.';
    }
    if (message.contains('Claim code already consumed')) {
      return 'This item already used its hidden claim code and cannot open a new claim packet.';
    }
    if (message.contains('Sensitive claim action reason is required')) {
      return 'Enter a clear operator reason before revealing a claim code or generating a packet.';
    }
    if (message.contains('QR token is not ready for this item')) {
      return 'Create authenticity first so the public verification QR is ready before preparing claim materials.';
    }
    if (message.contains('Item is not eligible for secure claim operations')) {
      return 'Only unclaimed, unrestricted inventory items can open a secure claim reveal or packet.';
    }
    if (message.contains('Secure claim material unavailable for this item')) {
      return 'This item does not have secure claim packet material yet. Reissue the claim packet only for inventory created after the claim-ops migration is applied.';
    }
    if (message.contains(
      'Secure claim material is out of sync for this item',
    )) {
      return 'Secure claim material for this item is out of sync and needs an admin migration review before it can be revealed.';
    }
    if (message.contains('Unsupported listing status')) {
      return 'Use draft or active when saving an operational listing.';
    }
    if (message.contains('Payment proof not found for order')) {
      return 'No payment proof is available for review on this order yet.';
    }
    if (message.contains('Unsupported payment review action')) {
      return 'Use approve, reject, request resubmission, or cancel for order review.';
    }
    if (message.contains('Reason is required for this order action')) {
      return 'Add a clear reason before rejecting, requesting resubmission, or cancelling an order.';
    }
    if (message.contains('Order cannot be cancelled from its current state')) {
      return 'This order is already closed and cannot be cancelled from the queue.';
    }
    if (message.contains(
      'Paid orders cannot be cancelled from this review flow',
    )) {
      return 'Use the downstream fulfillment or refund workflow for orders that are already paid.';
    }
    if (message.contains('Payment amount does not match order total')) {
      return 'Submitted payment amount does not match the expected order total.';
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

  DateTime? _nullableDateTime(dynamic value) {
    final String? text = _nullableString(value);
    if (text == null) {
      return null;
    }
    return DateTime.parse(text);
  }

  int _toInt(dynamic value) {
    return (value as num?)?.toInt() ?? 0;
  }

  String? _requireConfigured() {
    if (_client == null) {
      return _configurationError ?? 'Supabase is not configured for this app.';
    }
    return null;
  }
}
