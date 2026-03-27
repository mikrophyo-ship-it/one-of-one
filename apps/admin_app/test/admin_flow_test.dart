import 'dart:async';

import 'package:admin_app/src/admin_app.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:services/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets(
    'admin app verification covers sign in, dashboard, customers, moderation, disputes, freeze-release, settings, and audit feed',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final _FakeAdminRepository repository = _FakeAdminRepository();
      final _TestAdminAuthService authService = _TestAdminAuthService()
        ..seedAccount(
          email: 'admin@example.com',
          password: 'password123',
          displayName: 'Admin Operator',
          username: 'adminoperator',
        );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: AdminShell(
            authService: authService,
            adminService: AdminOperationsService(repository: repository),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Operational access'), findsOneWidget);

      await _enterField(tester, 'Email', 'admin@example.com');
      await _enterField(tester, 'Password', 'password123');
      await tester.tap(find.widgetWithText(FilledButton, 'Enter admin console'));
      await tester.pumpAndSettle();

      expect(find.text('Operational overview'), findsOneWidget);
      expect(find.text('Marketplace guardrails'), findsOneWidget);

      await _tapRailLabel(tester, 'Catalog');
      expect(find.text('OOO-NEW-0002'), findsOneWidget);
      await _tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Link Authenticity').first,
      );
      expect(
        find.text('Authenticity record linked to inventory item.'),
        findsOneWidget,
      );
      expect(find.text('verified_human_made'), findsWidgets);

      await _tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Create Listing').first,
      );
      await _enterField(tester, 'Asking price (cents)', '210000');
      await tester.tap(find.widgetWithText(FilledButton, 'Create listing'));
      await tester.pumpAndSettle();
      expect(find.text('Listing published for sale.'), findsOneWidget);
      expect(find.text('active'), findsWidgets);

      await _tapRailLabel(tester, 'Customers');
      expect(find.text('Avery Collector'), findsOneWidget);
      await tester.tap(find.text('customer').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('support').last);
      await tester.pumpAndSettle();
      expect(find.text('Customer role updated.'), findsOneWidget);
      expect(find.text('support'), findsWidgets);

      await _tapRailLabel(tester, 'Listings');
      expect(find.text('OOO-AG-0001'), findsOneWidget);
      await _tapVisible(
        tester,
        find.widgetWithText(OutlinedButton, 'Block').first,
      );
      await _enterField(
        tester,
        'Add an internal moderation note',
        'Blocking listing for verification review.',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();
      expect(find.text('Listing moderation was saved.'), findsOneWidget);
      expect(find.text('blocked_by_admin'), findsWidgets);

      await _tapRailLabel(tester, 'Disputes');
      expect(find.text('OOO-AG-0001'), findsOneWidget);
      await _tapVisible(
        tester,
        find.widgetWithText(TextButton, 'Freeze').first,
      );
      await _enterField(
        tester,
        'Add an internal note for this item action',
        'Freezing item while dispute is under review.',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      expect(find.text('Item status updated by admin control.'), findsOneWidget);
      expect(find.text('frozen'), findsWidgets);

      await _tapVisible(
        tester,
        find.widgetWithText(TextButton, 'Release').first,
      );
      await _enterField(
        tester,
        'Add an internal note for this item action',
        'Releasing item after dispute review.',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      expect(find.text('claimed'), findsWidgets);

      await _tapRailLabel(tester, 'Settings');
      await _enterField(tester, 'Platform fee (bps)', '1250');
      await tester.tap(find.widgetWithText(FilledButton, 'Save settings'));
      await tester.pumpAndSettle();
      expect(find.text('Platform settings saved.'), findsOneWidget);

      await _tapRailLabel(tester, 'Overview');
      await _tapRailLabel(tester, 'Settings');
      expect(find.text('1250'), findsOneWidget);

      await _tapRailLabel(tester, 'Audit');
      expect(find.text('admin_create_item_authenticity_record'), findsOneWidget);
      expect(find.text('admin_upsert_item_listing'), findsOneWidget);
      expect(find.text('set_user_role'), findsOneWidget);
      expect(find.text('moderate_listing'), findsOneWidget);
      expect(find.text('flag_item_status'), findsWidgets);
      expect(find.text('update_platform_settings'), findsOneWidget);
    },
  );

  testWidgets('admin app restores an existing admin session on startup', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final _FakeAdminRepository repository = _FakeAdminRepository();
    final _TestAdminAuthService authService = _TestAdminAuthService(
      initialSession: _buildSession(
        id: 'admin_1',
        email: 'restored-admin@example.com',
        displayName: 'Restored Admin',
        username: 'restoredadmin',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: AdminShell(
          authService: authService,
          adminService: AdminOperationsService(repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Operational access'), findsNothing);
    expect(find.text('Operational overview'), findsOneWidget);
    await _tapRailLabel(tester, 'Audit');
    expect(find.text('seed_audit'), findsOneWidget);
  });
}

Future<void> _tapRailLabel(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _enterField(
  WidgetTester tester,
  String label,
  String value,
) async {
  final Finder field = find.byWidgetPredicate((Widget widget) {
    if (widget is TextField) {
      return widget.decoration?.labelText == label ||
          widget.decoration?.hintText == label;
    }
    return false;
  });
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

Session _buildSession({
  required String id,
  required String email,
  required String displayName,
  required String username,
}) {
  return Session(
    accessToken: 'test-token',
    refreshToken: 'refresh-token',
    tokenType: 'bearer',
    user: User(
      id: id,
      appMetadata: const <String, dynamic>{},
      userMetadata: <String, dynamic>{
        'display_name': displayName,
        'username': username,
      },
      aud: 'authenticated',
      email: email,
      createdAt: DateTime(2026, 3, 27).toIso8601String(),
      emailConfirmedAt: DateTime(2026, 3, 27).toIso8601String(),
    ),
  );
}

class _TestAdminAuthService extends SupabaseAuthService {
  _TestAdminAuthService({Session? initialSession})
    : _session = initialSession,
      super(configurationError: null);

  final Map<String, _TestAdminAccount> _accounts =
      <String, _TestAdminAccount>{};
  Session? _session;

  @override
  bool get isConfigured => true;

  @override
  User? get currentUser => _session?.user;

  @override
  Session? get currentSession => _session;

  @override
  Stream<AuthState> authStateChanges() => const Stream<AuthState>.empty();

  @override
  Future<AuthActionResult> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final _TestAdminAccount? account = _accounts[email.trim().toLowerCase()];
    if (account == null || account.password != password) {
      return const AuthActionResult(
        success: false,
        message: 'Email or password was not accepted.',
      );
    }

    _session = _buildSession(
      id: account.id,
      email: account.email,
      displayName: account.displayName,
      username: account.username,
    );
    return const AuthActionResult(
      success: true,
      message: 'Signed in and collector profile synced.',
    );
  }

  @override
  Future<void> signOut() async {
    _session = null;
  }

  void seedAccount({
    required String email,
    required String password,
    required String displayName,
    required String username,
  }) {
    final String normalizedEmail = email.trim().toLowerCase();
    _accounts[normalizedEmail] = _TestAdminAccount(
      id: 'admin_${_accounts.length + 1}',
      email: normalizedEmail,
      password: password,
      displayName: displayName,
      username: username,
    );
  }
}

class _TestAdminAccount {
  const _TestAdminAccount({
    required this.id,
    required this.email,
    required this.password,
    required this.displayName,
    required this.username,
  });

  final String id;
  final String email;
  final String password;
  final String displayName;
  final String username;
}

class _FakeAdminRepository implements AdminOperationsRepository {
  _FakeAdminRepository() {
    _customers = <AdminCustomerRecord>[
      AdminCustomerRecord(
        userId: 'user_1',
        displayName: 'Avery Collector',
        username: 'avery',
        role: 'customer',
        createdAt: DateTime(2026, 3, 10),
        ownedItemCount: 2,
        openDisputeCount: 1,
        buyOrderCount: 4,
        sellOrderCount: 1,
        lastActivityAt: DateTime(2026, 3, 26),
      ),
    ];
    _listings = <AdminListingRecord>[
      AdminListingRecord(
        listingId: 'listing_1',
        itemId: 'item_1',
        sellerUserId: 'seller_1',
        listingStatus: 'active',
        askingPriceCents: 180000,
        createdAt: DateTime(2026, 3, 21),
        serialNumber: 'OOO-AG-0001',
        itemState: 'claimed',
        garmentName: 'Collector Tee',
        artworkTitle: 'Afterglow No. 01',
        artistName: 'Maya Vale',
        sellerDisplayName: 'Private Seller',
        sellerUsername: 'seller',
      ),
    ];
    _disputes = <AdminDisputeRecord>[
      AdminDisputeRecord(
        disputeId: 'dispute_1',
        itemId: 'item_1',
        orderId: 'order_1',
        disputeStatus: 'open',
        reason: 'Condition review',
        details: 'Collector requested a manual condition review.',
        createdAt: DateTime(2026, 3, 22),
        reportedByUserId: 'user_1',
        reporterDisplayName: 'Avery Collector',
        reporterUsername: 'avery',
        serialNumber: 'OOO-AG-0001',
        itemState: 'claimed',
        garmentName: 'Collector Tee',
        artworkTitle: 'Afterglow No. 01',
        artistName: 'Maya Vale',
        latestListingStatus: 'active',
      ),
    ];
    _orders = <AdminOrderRecord>[
      AdminOrderRecord(
        orderId: 'order_1',
        listingId: 'listing_1',
        orderStatus: 'paid',
        subtotalCents: 180000,
        totalCents: 180000,
        createdAt: DateTime(2026, 3, 20),
        itemId: 'item_1',
        serialNumber: 'OOO-AG-0001',
        itemState: 'claimed',
        garmentName: 'Collector Tee',
        artworkTitle: 'Afterglow No. 01',
        artistName: 'Maya Vale',
        buyerDisplayName: 'Avery Collector',
        sellerDisplayName: 'Private Seller',
        listingStatus: 'active',
        paymentStatus: 'captured',
        paymentProvider: 'stripe',
        shipmentStatus: 'delivered',
        shipmentCarrier: 'DHL',
        trackingNumber: 'TRACK123',
        sellerPayoutStatus: 'pending',
        royaltyStatus: 'pending',
        platformFeeStatus: 'captured',
      ),
    ];
    _artists = <AdminArtistRecord>[
      const AdminArtistRecord(
        artistId: 'artist_1',
        displayName: 'Maya Vale',
        slug: 'maya-vale',
        royaltyBps: 1200,
        isActive: true,
        artworkCount: 1,
        inventoryCount: 2,
      ),
    ];
    _artworks = <AdminArtworkRecord>[
      AdminArtworkRecord(
        artworkId: 'artwork_1',
        artistId: 'artist_1',
        artistName: 'Maya Vale',
        title: 'Afterglow No. 01',
        creationDate: DateTime(2026, 3, 1),
        inventoryCount: 2,
      ),
    ];
    _inventory = <AdminInventoryRecord>[
      const AdminInventoryRecord(
        itemId: 'item_1',
        serialNumber: 'OOO-AG-0001',
        artistName: 'Maya Vale',
        artworkTitle: 'Afterglow No. 01',
        garmentName: 'Collector Tee',
        itemState: 'claimed',
        ownerDisplayLabel: 'Avery Collector',
        hasAuthenticityRecord: true,
        authenticityStatus: 'verified_human_made',
        listingId: 'listing_1',
        listingStatus: 'active',
        askingPriceCents: 180000,
        customerVisible: true,
        buyable: true,
      ),
      const AdminInventoryRecord(
        itemId: 'item_2',
        serialNumber: 'OOO-NEW-0002',
        artistName: 'Maya Vale',
        artworkTitle: 'Afterglow No. 01',
        garmentName: 'Collector Tee',
        itemState: 'in_inventory',
        ownerDisplayLabel: 'Unassigned',
        hasAuthenticityRecord: false,
        authenticityStatus: null,
        listingId: null,
        listingStatus: null,
        askingPriceCents: null,
        customerVisible: false,
        buyable: false,
      ),
    ];
    _garmentProducts = <AdminGarmentProductRecord>[
      const AdminGarmentProductRecord(
        garmentProductId: 'garment_1',
        sku: 'OOO-TEE-BLK-M',
        name: 'Collector Tee',
        silhouette: 'tee',
        sizeLabel: 'M',
        colorway: 'black',
        basePriceCents: 180000,
      ),
    ];
    _finance = <AdminFinanceRecord>[
      const AdminFinanceRecord(
        orderId: 'order_1',
        paymentStatus: 'captured',
        shipmentStatus: 'delivered',
        sellerPayoutStatus: 'pending',
        royaltyStatus: 'pending',
        platformFeeStatus: 'captured',
        totalCents: 180000,
      ),
    ];
    _audits = <AdminAuditRecord>[
      AdminAuditRecord(
        auditId: 'audit_1',
        createdAt: DateTime(2026, 3, 20),
        entityType: 'system',
        entityId: 'seed',
        action: 'seed_audit',
        payload: const <String, dynamic>{'source': 'fixture'},
        actorDisplayName: 'system',
        actorUsername: null,
      ),
    ];
    _settings = const PlatformSettingsSnapshot(
      platformFeeBps: 1000,
      defaultRoyaltyBps: 1200,
      marketplaceRules: <String, dynamic>{'resale_only': true},
      brandSettings: <String, dynamic>{'theme': 'gold'},
    );
    _rebuildSnapshot();
  }

  late List<AdminCustomerRecord> _customers;
  late List<AdminListingRecord> _listings;
  late List<AdminDisputeRecord> _disputes;
  late List<AdminOrderRecord> _orders;
  late List<AdminArtistRecord> _artists;
  late List<AdminArtworkRecord> _artworks;
  late List<AdminInventoryRecord> _inventory;
  late List<AdminGarmentProductRecord> _garmentProducts;
  late List<AdminFinanceRecord> _finance;
  late List<AdminAuditRecord> _audits;
  late PlatformSettingsSnapshot _settings;
  late AdminOperationsSnapshot _snapshot;

  @override
  AdminOperationsSnapshot snapshot() => _snapshot;

  @override
  Future<MarketplaceActionResult<AdminOperationsSnapshot>> refresh() async {
    _rebuildSnapshot();
    return MarketplaceActionResult<AdminOperationsSnapshot>(
      success: true,
      message: 'Admin operations refreshed from Supabase.',
      data: _snapshot,
    );
  }

  @override
  Future<MarketplaceActionResult<AdminDisputeRecord>> updateDisputeStatus({
    required String disputeId,
    required String status,
    required String note,
    required bool releaseItem,
    String? releaseTargetState,
  }) async {
    final int index = _disputes.indexWhere(
      (AdminDisputeRecord dispute) => dispute.disputeId == disputeId,
    );
    if (index == -1) {
      return const MarketplaceActionResult<AdminDisputeRecord>(
        success: false,
        message: 'Dispute not found.',
      );
    }

    final AdminDisputeRecord current = _disputes[index];
    _disputes[index] = AdminDisputeRecord(
      disputeId: current.disputeId,
      itemId: current.itemId,
      orderId: current.orderId,
      disputeStatus: status,
      reason: current.reason,
      details: current.details,
      createdAt: current.createdAt,
      reportedByUserId: current.reportedByUserId,
      reporterDisplayName: current.reporterDisplayName,
      reporterUsername: current.reporterUsername,
      serialNumber: current.serialNumber,
      itemState: releaseItem ? (releaseTargetState ?? current.itemState) : current.itemState,
      garmentName: current.garmentName,
      artworkTitle: current.artworkTitle,
      artistName: current.artistName,
      latestListingStatus: current.latestListingStatus,
    );
    _addAudit(
      action: 'update_dispute_status',
      entityType: 'dispute',
      entityId: disputeId,
      payload: <String, dynamic>{'status': status, 'note': note},
    );
    _rebuildSnapshot();
    return MarketplaceActionResult<AdminDisputeRecord>(
      success: true,
      message: 'Dispute status updated.',
      data: _disputes[index],
    );
  }

  @override
  Future<MarketplaceActionResult<AdminListingRecord>> moderateListing({
    required String listingId,
    required String action,
    required String note,
  }) async {
    final int index = _listings.indexWhere(
      (AdminListingRecord listing) => listing.listingId == listingId,
    );
    if (index == -1) {
      return const MarketplaceActionResult<AdminListingRecord>(
        success: false,
        message: 'Listing not found.',
      );
    }

    final AdminListingRecord current = _listings[index];
    final String nextStatus = switch (action) {
      'block' => 'blocked_by_admin',
      'restore' => 'active',
      'cancel' => 'cancelled',
      _ => current.listingStatus,
    };
    _listings[index] = AdminListingRecord(
      listingId: current.listingId,
      itemId: current.itemId,
      sellerUserId: current.sellerUserId,
      listingStatus: nextStatus,
      askingPriceCents: current.askingPriceCents,
      createdAt: current.createdAt,
      serialNumber: current.serialNumber,
      itemState: current.itemState,
      garmentName: current.garmentName,
      artworkTitle: current.artworkTitle,
      artistName: current.artistName,
      sellerDisplayName: current.sellerDisplayName,
      sellerUsername: current.sellerUsername,
    );
    _addAudit(
      action: 'moderate_listing',
      entityType: 'listing',
      entityId: listingId,
      payload: <String, dynamic>{'action': action, 'note': note},
    );
    _syncDisputeListingStatus(current.itemId, nextStatus);
    _rebuildSnapshot();
    return MarketplaceActionResult<AdminListingRecord>(
      success: true,
      message: 'Listing moderation was saved.',
      data: _listings[index],
    );
  }

  @override
  Future<MarketplaceActionResult<PlatformSettingsSnapshot>> updateSettings({
    required int platformFeeBps,
    required int defaultRoyaltyBps,
    required Map<String, dynamic> marketplaceRules,
    required Map<String, dynamic> brandSettings,
  }) async {
    _settings = PlatformSettingsSnapshot(
      platformFeeBps: platformFeeBps,
      defaultRoyaltyBps: defaultRoyaltyBps,
      marketplaceRules: marketplaceRules,
      brandSettings: brandSettings,
    );
    _addAudit(
      action: 'update_platform_settings',
      entityType: 'settings',
      entityId: 'platform',
      payload: <String, dynamic>{
        'platform_fee_bps': platformFeeBps,
        'default_royalty_bps': defaultRoyaltyBps,
      },
    );
    _rebuildSnapshot();
    return MarketplaceActionResult<PlatformSettingsSnapshot>(
      success: true,
      message: 'Platform settings saved.',
      data: _settings,
    );
  }

  @override
  Future<MarketplaceActionResult<AdminCustomerRecord>> setUserRole({
    required String userId,
    required String role,
  }) async {
    final int index = _customers.indexWhere(
      (AdminCustomerRecord customer) => customer.userId == userId,
    );
    if (index == -1) {
      return const MarketplaceActionResult<AdminCustomerRecord>(
        success: false,
        message: 'Customer not found.',
      );
    }

    final AdminCustomerRecord current = _customers[index];
    _customers[index] = AdminCustomerRecord(
      userId: current.userId,
      displayName: current.displayName,
      username: current.username,
      role: role,
      createdAt: current.createdAt,
      ownedItemCount: current.ownedItemCount,
      openDisputeCount: current.openDisputeCount,
      buyOrderCount: current.buyOrderCount,
      sellOrderCount: current.sellOrderCount,
      lastActivityAt: DateTime(2026, 3, 27),
    );
    _addAudit(
      action: 'set_user_role',
      entityType: 'customer',
      entityId: userId,
      payload: <String, dynamic>{'role': role},
    );
    _rebuildSnapshot();
    return MarketplaceActionResult<AdminCustomerRecord>(
      success: true,
      message: 'Customer role updated.',
      data: _customers[index],
    );
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
    return const MarketplaceActionResult<AdminArtistRecord>(
      success: false,
      message: 'Not used in this verification test.',
    );
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
    return const MarketplaceActionResult<AdminArtworkRecord>(
      success: false,
      message: 'Not used in this verification test.',
    );
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
    return const MarketplaceActionResult<AdminInventoryRecord>(
      success: false,
      message: 'Not used in this verification test.',
    );
  }

  @override
  Future<MarketplaceActionResult<AdminInventoryRecord>> createAuthenticityRecord({
    required String itemId,
  }) async {
    final int index = _inventory.indexWhere(
      (AdminInventoryRecord item) => item.itemId == itemId,
    );
    if (index == -1) {
      return const MarketplaceActionResult<AdminInventoryRecord>(
        success: false,
        message: 'Inventory item not found.',
      );
    }

    final AdminInventoryRecord current = _inventory[index];
    _inventory[index] = AdminInventoryRecord(
      itemId: current.itemId,
      serialNumber: current.serialNumber,
      artistName: current.artistName,
      artworkTitle: current.artworkTitle,
      garmentName: current.garmentName,
      itemState: current.itemState,
      ownerDisplayLabel: current.ownerDisplayLabel,
      hasAuthenticityRecord: true,
      authenticityStatus: 'verified_human_made',
      listingId: current.listingId,
      listingStatus: current.listingStatus,
      askingPriceCents: current.askingPriceCents,
      customerVisible: true,
      buyable: current.buyable,
    );
    _addAudit(
      action: 'admin_create_item_authenticity_record',
      entityType: 'authenticity_record',
      entityId: itemId,
      payload: <String, dynamic>{'item_id': itemId},
    );
    _rebuildSnapshot();
    return MarketplaceActionResult<AdminInventoryRecord>(
      success: true,
      message: 'Authenticity record linked to inventory item.',
      data: _inventory[index],
    );
  }

  @override
  Future<MarketplaceActionResult<AdminInventoryRecord>> upsertInventoryListing({
    required String itemId,
    required int askingPriceCents,
    required String status,
  }) async {
    final int index = _inventory.indexWhere(
      (AdminInventoryRecord item) => item.itemId == itemId,
    );
    if (index == -1) {
      return const MarketplaceActionResult<AdminInventoryRecord>(
        success: false,
        message: 'Inventory item not found.',
      );
    }

    final AdminInventoryRecord current = _inventory[index];
    final String listingId = current.listingId ?? 'listing_${_listings.length + 1}';
    _inventory[index] = AdminInventoryRecord(
      itemId: current.itemId,
      serialNumber: current.serialNumber,
      artistName: current.artistName,
      artworkTitle: current.artworkTitle,
      garmentName: current.garmentName,
      itemState: status == 'active' ? 'listed_for_resale' : current.itemState,
      ownerDisplayLabel: current.ownerDisplayLabel == 'Unassigned'
          ? 'Admin Operator'
          : current.ownerDisplayLabel,
      hasAuthenticityRecord: current.hasAuthenticityRecord,
      authenticityStatus: current.authenticityStatus,
      listingId: listingId,
      listingStatus: status,
      askingPriceCents: askingPriceCents,
      customerVisible: current.customerVisible,
      buyable: current.hasAuthenticityRecord && status == 'active',
    );

    final int listingIndex = _listings.indexWhere(
      (AdminListingRecord listing) => listing.itemId == itemId,
    );
    final AdminListingRecord nextListing = AdminListingRecord(
      listingId: listingId,
      itemId: itemId,
      sellerUserId: 'admin_1',
      listingStatus: status,
      askingPriceCents: askingPriceCents,
      createdAt: DateTime(2026, 3, 27),
      serialNumber: current.serialNumber,
      itemState: status == 'active' ? 'listed_for_resale' : current.itemState,
      garmentName: current.garmentName,
      artworkTitle: current.artworkTitle,
      artistName: current.artistName,
      sellerDisplayName: 'Admin Operator',
      sellerUsername: 'adminoperator',
    );
    if (listingIndex == -1) {
      _listings = <AdminListingRecord>[nextListing, ..._listings];
    } else {
      _listings[listingIndex] = nextListing;
    }

    _addAudit(
      action: 'admin_upsert_item_listing',
      entityType: 'listing',
      entityId: listingId,
      payload: <String, dynamic>{
        'item_id': itemId,
        'asking_price_cents': askingPriceCents,
        'status': status,
      },
    );
    _rebuildSnapshot();
    return MarketplaceActionResult<AdminInventoryRecord>(
      success: true,
      message: status == 'active'
          ? 'Listing published for sale.'
          : 'Listing saved.',
      data: _inventory[index],
    );
  }

  @override
  Future<MarketplaceActionResult<void>> flagItemStatus({
    required String itemId,
    required String targetState,
    required String note,
  }) async {
    _listings = _listings.map((AdminListingRecord listing) {
      if (listing.itemId != itemId) {
        return listing;
      }
      return AdminListingRecord(
        listingId: listing.listingId,
        itemId: listing.itemId,
        sellerUserId: listing.sellerUserId,
        listingStatus: listing.listingStatus,
        askingPriceCents: listing.askingPriceCents,
        createdAt: listing.createdAt,
        serialNumber: listing.serialNumber,
        itemState: targetState,
        garmentName: listing.garmentName,
        artworkTitle: listing.artworkTitle,
        artistName: listing.artistName,
        sellerDisplayName: listing.sellerDisplayName,
        sellerUsername: listing.sellerUsername,
      );
    }).toList();
    _inventory = _inventory.map((AdminInventoryRecord item) {
      if (item.itemId != itemId) {
        return item;
      }
      return AdminInventoryRecord(
        itemId: item.itemId,
        serialNumber: item.serialNumber,
        artistName: item.artistName,
        artworkTitle: item.artworkTitle,
        garmentName: item.garmentName,
        itemState: targetState,
        ownerDisplayLabel: item.ownerDisplayLabel,
        hasAuthenticityRecord: item.hasAuthenticityRecord,
        authenticityStatus: item.authenticityStatus,
        listingId: item.listingId,
        listingStatus: item.listingStatus,
        askingPriceCents: item.askingPriceCents,
        customerVisible: item.customerVisible,
        buyable: item.buyable && targetState != 'frozen',
      );
    }).toList();
    _disputes = _disputes.map((AdminDisputeRecord dispute) {
      if (dispute.itemId != itemId) {
        return dispute;
      }
      return AdminDisputeRecord(
        disputeId: dispute.disputeId,
        itemId: dispute.itemId,
        orderId: dispute.orderId,
        disputeStatus: dispute.disputeStatus,
        reason: dispute.reason,
        details: dispute.details,
        createdAt: dispute.createdAt,
        reportedByUserId: dispute.reportedByUserId,
        reporterDisplayName: dispute.reporterDisplayName,
        reporterUsername: dispute.reporterUsername,
        serialNumber: dispute.serialNumber,
        itemState: targetState,
        garmentName: dispute.garmentName,
        artworkTitle: dispute.artworkTitle,
        artistName: dispute.artistName,
        latestListingStatus: dispute.latestListingStatus,
      );
    }).toList();
    _orders = _orders.map((AdminOrderRecord order) {
      if (order.itemId != itemId) {
        return order;
      }
      return AdminOrderRecord(
        orderId: order.orderId,
        listingId: order.listingId,
        orderStatus: order.orderStatus,
        subtotalCents: order.subtotalCents,
        totalCents: order.totalCents,
        createdAt: order.createdAt,
        itemId: order.itemId,
        serialNumber: order.serialNumber,
        itemState: targetState,
        garmentName: order.garmentName,
        artworkTitle: order.artworkTitle,
        artistName: order.artistName,
        buyerDisplayName: order.buyerDisplayName,
        sellerDisplayName: order.sellerDisplayName,
        listingStatus: order.listingStatus,
        paymentStatus: order.paymentStatus,
        paymentProvider: order.paymentProvider,
        shipmentStatus: order.shipmentStatus,
        shipmentCarrier: order.shipmentCarrier,
        trackingNumber: order.trackingNumber,
        sellerPayoutStatus: order.sellerPayoutStatus,
        royaltyStatus: order.royaltyStatus,
        platformFeeStatus: order.platformFeeStatus,
      );
    }).toList();
    _addAudit(
      action: 'flag_item_status',
      entityType: 'item',
      entityId: itemId,
      payload: <String, dynamic>{'target_state': targetState, 'note': note},
    );
    _rebuildSnapshot();
    return const MarketplaceActionResult<void>(
      success: true,
      message: 'Item status updated by admin control.',
    );
  }

  void _syncDisputeListingStatus(String itemId, String listingStatus) {
    _disputes = _disputes.map((AdminDisputeRecord dispute) {
      if (dispute.itemId != itemId) {
        return dispute;
      }
      return AdminDisputeRecord(
        disputeId: dispute.disputeId,
        itemId: dispute.itemId,
        orderId: dispute.orderId,
        disputeStatus: dispute.disputeStatus,
        reason: dispute.reason,
        details: dispute.details,
        createdAt: dispute.createdAt,
        reportedByUserId: dispute.reportedByUserId,
        reporterDisplayName: dispute.reporterDisplayName,
        reporterUsername: dispute.reporterUsername,
        serialNumber: dispute.serialNumber,
        itemState: dispute.itemState,
        garmentName: dispute.garmentName,
        artworkTitle: dispute.artworkTitle,
        artistName: dispute.artistName,
        latestListingStatus: listingStatus,
      );
    }).toList();
  }

  void _addAudit({
    required String action,
    required String entityType,
    required String entityId,
    required Map<String, dynamic> payload,
  }) {
    _audits = <AdminAuditRecord>[
      AdminAuditRecord(
        auditId: 'audit_${_audits.length + 1}',
        createdAt: DateTime(2026, 3, 27, 12, _audits.length + 1),
        entityType: entityType,
        entityId: entityId,
        action: action,
        payload: payload,
        actorDisplayName: 'Admin Operator',
        actorUsername: 'adminoperator',
      ),
      ..._audits,
    ];
  }

  void _rebuildSnapshot() {
    final int frozenCount = _inventory
        .where((AdminInventoryRecord item) => item.itemState == 'frozen')
        .length;
    final int openDisputes = _disputes
        .where(
          (AdminDisputeRecord dispute) =>
              dispute.disputeStatus == 'open' ||
              dispute.disputeStatus == 'under_review',
        )
        .length;
    final int activeListings = _listings
        .where((AdminListingRecord listing) => listing.listingStatus == 'active')
        .length;

    _snapshot = AdminOperationsSnapshot(
      dashboard: AdminDashboardSnapshot(
        openDisputes: openDisputes,
        activeListings: activeListings,
        paymentPendingOrders: 0,
        deliveryPendingOrders: 0,
        payoutPendingOrders: 1,
        refundPendingOrders: 0,
        grossSalesCents: 180000,
        royaltyCents: 21600,
        platformFeeCents: 18000,
        frozenItems: frozenCount,
        stolenItems: _inventory
            .where((AdminInventoryRecord item) => item.itemState == 'stolen_flagged')
            .length,
      ),
      customers: List<AdminCustomerRecord>.unmodifiable(_customers),
      listings: List<AdminListingRecord>.unmodifiable(_listings),
      disputes: List<AdminDisputeRecord>.unmodifiable(_disputes),
      orders: List<AdminOrderRecord>.unmodifiable(_orders),
      artists: List<AdminArtistRecord>.unmodifiable(_artists),
      artworks: List<AdminArtworkRecord>.unmodifiable(_artworks),
      inventory: List<AdminInventoryRecord>.unmodifiable(_inventory),
      garmentProducts: List<AdminGarmentProductRecord>.unmodifiable(
        _garmentProducts,
      ),
      finance: List<AdminFinanceRecord>.unmodifiable(_finance),
      audits: List<AdminAuditRecord>.unmodifiable(_audits),
      settings: _settings,
    );
  }
}
