import 'dart:async';
import 'package:core_ui/core_ui.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:services/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:utils/utils.dart';

import 'app_environment.dart';
import 'authenticity_link_source.dart';

typedef PaymentProofPicker = Future<SelectedPaymentProof?> Function();

class SelectedPaymentProof {
  const SelectedPaymentProof({
    required this.bytes,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
  });

  final Uint8List bytes;
  final String fileName;
  final String contentType;
  final int sizeBytes;
}

class OneOfOneCustomerApp extends StatelessWidget {
  const OneOfOneCustomerApp({
    super.key,
    this.repository,
    this.workflowService,
    this.authService,
    this.checkoutConfig,
    this.authenticityLinkSource,
    this.paymentProofPicker,
    this.enableCameraScanner = true,
  });

  final MarketplaceRepository? repository;
  final MarketplaceWorkflowService? workflowService;
  final SupabaseAuthService? authService;
  final CheckoutPresentationConfig? checkoutConfig;
  final AuthenticityLinkSource? authenticityLinkSource;
  final PaymentProofPicker? paymentProofPicker;
  final bool enableCameraScanner;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'One of One',
      debugShowCheckedModeBanner: false,
      theme: OneOfOneTheme.customerTheme(),
      home: CustomerRoot(
        repository: repository,
        workflowService: workflowService,
        authService: authService,
        checkoutConfig: checkoutConfig,
        authenticityLinkSource: authenticityLinkSource,
        paymentProofPicker: paymentProofPicker,
        enableCameraScanner: enableCameraScanner,
      ),
    );
  }
}

class CustomerRoot extends StatefulWidget {
  const CustomerRoot({
    super.key,
    this.repository,
    this.workflowService,
    this.authService,
    this.checkoutConfig,
    this.authenticityLinkSource,
    this.paymentProofPicker,
    this.enableCameraScanner = true,
  });

  final MarketplaceRepository? repository;
  final MarketplaceWorkflowService? workflowService;
  final SupabaseAuthService? authService;
  final CheckoutPresentationConfig? checkoutConfig;
  final AuthenticityLinkSource? authenticityLinkSource;
  final PaymentProofPicker? paymentProofPicker;
  final bool enableCameraScanner;

  @override
  State<CustomerRoot> createState() => _CustomerRootState();
}

class _CustomerRootState extends State<CustomerRoot>
    with WidgetsBindingObserver {
  late final MarketplaceRepository repository;
  late final MarketplaceWorkflowService workflowService;
  late final SupabaseAuthService authService;
  late final CustomerController controller;
  late final CheckoutPresentationConfig checkoutConfig;
  late final AuthenticityLinkSource authenticityLinkSource;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    repository = widget.repository ?? _defaultRepository();
    authService = widget.authService ?? _defaultAuthService();
    checkoutConfig =
        widget.checkoutConfig ?? CheckoutPresentationConfig.fromEnvironment();
    authenticityLinkSource =
        widget.authenticityLinkSource ?? AppAuthenticityLinkSource();
    workflowService =
        widget.workflowService ??
        MarketplaceWorkflowService(
          repository: repository,
          paymentProvider: const ManualPaymentProvider(),
        );
    controller = CustomerController(
      repository: repository,
      workflowService: workflowService,
      authService: authService,
      checkoutConfig: checkoutConfig,
      authenticityLinkSource: authenticityLinkSource,
      paymentProofPicker:
          widget.paymentProofPicker ?? _defaultPaymentProofPicker,
    );
    unawaited(controller.initialize());
  }

  MarketplaceRepository _defaultRepository() {
    final String? configurationError = !AppEnvironment.hasSupabaseConfig
        ? 'Supabase is not configured. Pass SUPABASE_URL and SUPABASE_ANON_KEY via dart-define.'
        : null;

    if (configurationError == null) {
      return SupabaseMarketplaceRepository(client: Supabase.instance.client);
    }
    return SupabaseMarketplaceRepository(
      configurationError: configurationError,
    );
  }

  SupabaseAuthService _defaultAuthService() {
    final String? configurationError = !AppEnvironment.hasSupabaseConfig
        ? 'Supabase is not configured. Pass SUPABASE_URL and SUPABASE_ANON_KEY via dart-define.'
        : null;

    if (configurationError == null) {
      return SupabaseAuthService(client: Supabase.instance.client);
    }
    return SupabaseAuthService(configurationError: configurationError);
  }

  Future<SelectedPaymentProof?> _defaultPaymentProofPicker() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        return null;
      }
      final PlatformFile file = result.files.first;
      if (file.bytes == null) {
        throw StateError(
          'The selected image could not be read. Please choose another screenshot.',
        );
      }
      return SelectedPaymentProof(
        bytes: file.bytes!,
        fileName: file.name.trim().isEmpty ? 'payment-proof.jpg' : file.name,
        contentType: _contentTypeForProofFileName(file.name),
        sizeBytes: file.size,
      );
    } catch (error) {
      throw StateError(
        error is StateError
            ? error.toString().replaceFirst('Bad state: ', '')
            : 'Unable to open the screenshot picker right now.',
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(controller.handleAppResumed());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, _) {
        if (controller.isInitializing) {
          return const _StartupScreen();
        }
        if (controller.publicAuthenticityRoute != null) {
          return PublicAuthenticityScaffold(controller: controller);
        }
        if (!controller.isAuthenticated) {
          return AuthScreen(controller: controller);
        }
        return Scaffold(
          extendBody: true,
          appBar: AppBar(
            toolbarHeight: 64,
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            titleSpacing: 20,
            title: Text(
              'ONE OF ONE',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFFF2EBDD),
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            actions: <Widget>[
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: _PremiumNotificationButton(
                  unreadCount: controller.unreadNotificationCount,
                  onPressed: controller.toggleInbox,
                ),
              ),
            ],
          ),
          body: Stack(
            children: <Widget>[
              IndexedStack(
                index: controller.index,
                children: <Widget>[
                  PremiumHomeScreen(controller: controller),
                  ExploreScreen(controller: controller),
                  ScanScreen(
                    controller: controller,
                    enableCameraScanner: widget.enableCameraScanner,
                  ),
                  VaultScreen(controller: controller),
                  ProfileScreen(controller: controller),
                ],
              ),
              if (controller.showInbox)
                Align(
                  alignment: Alignment.topRight,
                  child: _NotificationCenterPanel(controller: controller),
                ),
              if (controller.isBusy)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.35),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: _LuxuryBottomDock(
            selectedIndex: controller.index,
            onDestinationSelected: controller.setIndex,
          ),
        );
      },
    );
  }
}

class _PremiumNotificationButton extends StatelessWidget {
  const _PremiumNotificationButton({
    required this.unreadCount,
    required this.onPressed,
  });

  final int unreadCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey<String>('customer-notifications-button'),
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF171717),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              const Center(
                child: Icon(
                  Icons.notifications_none,
                  size: 22,
                  color: Color(0xFFF2EBDD),
                ),
              ),
              if (unreadCount > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: const Color(0xFF0D0D0D),
                        width: 1.5,
                      ),
                    ),
                    constraints: const BoxConstraints(minWidth: 18),
                    child: Text(
                      unreadCount > 99 ? '99+' : '$unreadCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LuxuryBottomDock extends StatelessWidget {
  const _LuxuryBottomDock({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Padding(
        padding: const EdgeInsets.only(left: 6, right: 6, bottom: 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.24),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Theme(
              data: Theme.of(context).copyWith(
                navigationBarTheme: NavigationBarThemeData(
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  height: 72,
                  labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((
                    Set<WidgetState> states,
                  ) {
                    final bool selected = states.contains(WidgetState.selected);
                    return Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: selected
                          ? const Color(0xFFF2EBDD)
                          : const Color(0xFF9C9385),
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      letterSpacing: 0.2,
                    );
                  }),
                  iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((
                    Set<WidgetState> states,
                  ) {
                    final bool selected = states.contains(WidgetState.selected);
                    return IconThemeData(
                      color: selected ? Colors.black : const Color(0xFFC3BBAD),
                      size: 22,
                    );
                  }),
                  indicatorColor: const Color(0xFFE0C88A),
                ),
              ),
              child: NavigationBar(
                backgroundColor: Colors.transparent,
                selectedIndex: selectedIndex,
                onDestinationSelected: onDestinationSelected,
                destinations: const <Widget>[
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.auto_awesome_mosaic_outlined),
                    selectedIcon: Icon(Icons.auto_awesome_mosaic_rounded),
                    label: 'Shop',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.qr_code_scanner_outlined),
                    selectedIcon: Icon(Icons.qr_code_scanner_rounded),
                    label: 'Scan',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.inventory_2_outlined),
                    selectedIcon: Icon(Icons.inventory_2_rounded),
                    label: 'Vault',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person_rounded),
                    label: 'Profile',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CustomerController extends ChangeNotifier {
  CustomerController({
    required MarketplaceRepository repository,
    required MarketplaceWorkflowService workflowService,
    required SupabaseAuthService authService,
    required CheckoutPresentationConfig checkoutConfig,
    required AuthenticityLinkSource authenticityLinkSource,
    required PaymentProofPicker paymentProofPicker,
  }) : _repository = repository,
       _workflowService = workflowService,
       _authService = authService,
       _checkoutConfig = checkoutConfig,
       _authenticityLinkSource = authenticityLinkSource,
       _paymentProofPicker = paymentProofPicker;

  final MarketplaceRepository _repository;
  final MarketplaceWorkflowService _workflowService;
  final SupabaseAuthService _authService;
  final CheckoutPresentationConfig _checkoutConfig;
  final AuthenticityLinkSource _authenticityLinkSource;
  final PaymentProofPicker _paymentProofPicker;

  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<Uri>? _authenticityLinkSubscription;
  StreamSubscription<void>? _liveSyncSubscription;

  bool isInitializing = true;
  bool isAuthenticated = false;
  bool showInbox = false;
  bool isBusy = false;
  int index = 0;
  String currentUserId = '';
  String? currentUserEmail;
  String? currentDisplayName;
  String? statusMessage;
  String? errorMessage;
  String? lastCheckoutOrderId;
  String? lastCheckoutUrl;
  PublicAuthenticityRecord? scannedAuthenticity;
  PublicAuthenticityRecord? publicAuthenticityRoute;
  List<CollectorNotification> notificationFeed =
      const <CollectorNotification>[];
  Set<String> savedItemIds = <String>{};
  String? _lastResolvedAuthenticityToken;
  bool _isLiveRefreshInFlight = false;

  bool get authConfigured => _authService.isConfigured;

  List<Artist> get artists => _repository.featuredArtists();
  List<Artwork> get artworks => _repository.artworks();
  List<UniqueItem> get items => _repository.items();
  List<Listing> get listings => _repository.activeListings();
  List<String> get notifications => notificationFeed
      .map((CollectorNotification item) => '${item.title}: ${item.body}')
      .toList(growable: false);
  int get unreadNotificationCount =>
      notificationFeed.where((CollectorNotification item) => !item.read).length;
  List<UniqueItem> get vaultItems => items
      .where((UniqueItem item) => item.currentOwnerUserId == currentUserId)
      .toList();
  List<UniqueItem> get savedItems =>
      items.where((UniqueItem item) => savedItemIds.contains(item.id)).toList();
  List<ItemComment> commentsFor(String itemId) =>
      _repository.commentsForItem(itemId);
  ManualPaymentOrder? manualPaymentFor(String itemId) =>
      _repository.manualPaymentForItem(itemId);
  List<_ActivityEntry> get activityLog => _buildActivityLog();

  Future<void> initialize() async {
    _authSubscription ??= _authService.authStateChanges().listen((AuthState _) {
      unawaited(_syncSessionState());
    });
    _authenticityLinkSubscription ??= _authenticityLinkSource.uriStream.listen((
      Uri uri,
    ) {
      unawaited(handleAuthenticityUri(uri));
    });
    await _syncSessionState(
      restoredMessage: _authService.currentSession == null
          ? null
          : 'Collector session restored from Supabase.',
    );
    unawaited(handleInitialAuthenticityLink());
    unawaited(handleInitialCheckoutReturn());
  }

  Artist? artistFor(UniqueItem item) {
    for (final Artist artist in artists) {
      if (artist.id == item.artistId) {
        return artist;
      }
    }
    return artists.isEmpty ? null : artists.first;
  }

  Artwork? artworkFor(UniqueItem item) {
    final Artwork? direct = _repository.artworkById(item.artworkId);
    if (direct != null) {
      return direct;
    }
    return artworks.isEmpty ? null : artworks.first;
  }

  List<Artwork> artworksForArtist(String artistId) => artworks
      .where((Artwork artwork) => artwork.artistId == artistId)
      .toList(growable: false);

  List<UniqueItem> itemsForArtist(String artistId) => items
      .where((UniqueItem item) => item.artistId == artistId)
      .toList(growable: false);

  Listing? listingForItem(String itemId) {
    for (final Listing listing in listings) {
      if (listing.itemId == itemId) {
        return listing;
      }
    }
    return null;
  }

  List<OwnershipRecord> historyFor(String itemId) =>
      _repository.ownershipHistory(itemId);

  UniqueItem? itemById(String itemId) => _repository.itemById(itemId);

  FeeBreakdown breakdownFor(UniqueItem item) {
    return MarketplaceRules(
      platformFeeBps: 1000,
      defaultRoyaltyBps: artistFor(item)?.royaltyBps ?? 0,
    ).calculateResaleBreakdown(
      resalePrice: item.askingPrice ?? 0,
      royaltyBps: artistFor(item)?.royaltyBps ?? 0,
    );
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await _runAuthRequest(
      operation: () =>
          _authService.signInWithPassword(email: email, password: password),
      successMessageFallback: 'Signed in and collector profile synced.',
    );
  }

  Future<void> signUpWithEmail({
    required String displayName,
    required String username,
    required String email,
    required String password,
  }) async {
    await _runAuthRequest(
      operation: () => _authService.signUpWithPassword(
        email: email,
        password: password,
        displayName: displayName,
        username: username,
      ),
      successMessageFallback: 'Collector account created and profile synced.',
    );
  }

  Future<void> sendPasswordReset({required String email}) async {
    isBusy = true;
    errorMessage = null;
    statusMessage = null;
    notifyListeners();

    final AuthActionResult result = await _authService.sendPasswordReset(
      email: email,
    );
    isBusy = false;
    if (result.success) {
      statusMessage = result.message;
    } else {
      errorMessage = result.message;
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    isBusy = true;
    errorMessage = null;
    statusMessage = null;
    notifyListeners();

    await _authService.signOut();
    await _syncSessionState(
      restoredMessage:
          'Signed out. Sign back in to manage ownership and resale.',
    );
  }

  Future<void> handleInitialAuthenticityLink() async {
    final AuthenticityRouteMatch? baseMatch = AuthenticityRouteParser.parseUri(
      Uri.base,
    );
    if (baseMatch != null) {
      await resolveAuthenticityInput(
        rawInput: baseMatch.rawInput,
        openPublicRoute: true,
        switchToScanTab: isAuthenticated,
      );
      return;
    }

    final Uri? initialUri = await _authenticityLinkSource.getInitialUri();
    if (initialUri == null) {
      return;
    }
    await handleAuthenticityUri(initialUri);
  }

  Future<void> handleAuthenticityUri(Uri uri) async {
    final AuthenticityRouteMatch? match = AuthenticityRouteParser.parseUri(uri);
    if (match == null) {
      return;
    }

    await resolveAuthenticityInput(
      rawInput: match.rawInput,
      openPublicRoute: true,
      switchToScanTab: isAuthenticated,
    );
  }

  Future<void> handleInitialCheckoutReturn() async {
    final String? checkoutStatus = Uri.base.queryParameters['checkout_status'];
    final String? orderId = Uri.base.queryParameters['order_id'];
    if (checkoutStatus == null || checkoutStatus.trim().isEmpty) {
      return;
    }

    lastCheckoutOrderId = orderId?.trim();
    if (isAuthenticated && currentUserId.isNotEmpty) {
      await _repository.refresh(userId: currentUserId);
      await _refreshCompanionData();
    }

    if (checkoutStatus == 'success') {
      statusMessage =
          'Returned from Stripe checkout${lastCheckoutOrderId == null ? '' : ' for order $lastCheckoutOrderId'}. Payment authorization will be confirmed by webhook before shipment and settlement updates.';
    } else {
      statusMessage =
          'Stripe checkout was canceled before payment authorization completed.';
    }
    notifyListeners();
  }

  void setIndex(int value) {
    index = value;
    notifyListeners();
  }

  void toggleInbox() {
    showInbox = !showInbox;
    if (showInbox && isAuthenticated && currentUserId.isNotEmpty) {
      unawaited(_refreshCompanionData(notify: true));
    }
    notifyListeners();
  }

  Future<void> handleAppResumed() async {
    if (!isAuthenticated || currentUserId.isEmpty) {
      return;
    }
    await _refreshLiveData(showBusy: false, preserveStatus: true);
  }

  Future<void> markNotificationRead(String notificationId) async {
    if (notificationId.trim().isEmpty) {
      return;
    }
    final CollectorNotification? existing = notificationFeed
        .where((CollectorNotification item) => item.id == notificationId)
        .cast<CollectorNotification?>()
        .firstWhere(
          (CollectorNotification? item) => item != null,
          orElse: () => null,
        );
    if (existing == null || existing.read) {
      return;
    }
    final MarketplaceActionResult<void> result = await _workflowService
        .markNotificationsRead(notificationIds: <String>[notificationId]);
    if (!result.success) {
      return;
    }
    notificationFeed = notificationFeed
        .map((CollectorNotification item) {
          if (item.id != notificationId) {
            return item;
          }
          return CollectorNotification(
            id: item.id,
            title: item.title,
            body: item.body,
            createdAt: item.createdAt,
            read: true,
          );
        })
        .toList(growable: false);
    notifyListeners();
  }

  Future<PublicAuthenticityRecord?> lookupPublicAuthenticity({
    required String qrToken,
    bool openPublicRoute = false,
    bool switchToScanTab = false,
  }) async {
    isBusy = true;
    errorMessage = null;
    statusMessage = null;
    notifyListeners();

    final MarketplaceActionResult<PublicAuthenticityRecord> result =
        await _workflowService.lookupPublicAuthenticity(qrToken: qrToken);
    isBusy = false;
    if (result.success && result.data != null) {
      scannedAuthenticity = result.data;
      if (openPublicRoute) {
        publicAuthenticityRoute = result.data;
      }
      if (switchToScanTab) {
        index = 2;
      }
      _lastResolvedAuthenticityToken = result.data!.qrToken;
      statusMessage = 'Authenticity verified for ${result.data!.serialNumber}.';
      notifyListeners();
      return result.data;
    }

    scannedAuthenticity = null;
    if (openPublicRoute) {
      publicAuthenticityRoute = null;
    }
    errorMessage = result.message;
    notifyListeners();
    return null;
  }

  Future<PublicAuthenticityRecord?> resolveAuthenticityInput({
    required String rawInput,
    bool openPublicRoute = true,
    bool switchToScanTab = true,
  }) async {
    final AuthenticityRouteMatch? match = AuthenticityRouteParser.parseRaw(
      rawInput,
    );
    if (match == null) {
      errorMessage =
          'Scan a valid One of One authenticity QR or paste a public authenticity link.';
      statusMessage = null;
      scannedAuthenticity = null;
      publicAuthenticityRoute = null;
      notifyListeners();
      return null;
    }

    if (_lastResolvedAuthenticityToken == match.qrToken &&
        publicAuthenticityRoute?.qrToken == match.qrToken &&
        openPublicRoute) {
      if (switchToScanTab) {
        index = 2;
      }
      notifyListeners();
      return publicAuthenticityRoute;
    }

    return lookupPublicAuthenticity(
      qrToken: match.qrToken,
      openPublicRoute: openPublicRoute,
      switchToScanTab: switchToScanTab,
    );
  }

  void clearPublicAuthenticityRoute() {
    publicAuthenticityRoute = null;
    notifyListeners();
  }

  void continueFromPublicAuthenticity() {
    publicAuthenticityRoute = null;
    if (isAuthenticated) {
      index = 2;
    }
    notifyListeners();
  }

  Future<String> claimScannedItem({required String claimCode}) async {
    final String? authMessage = _requireAuthenticatedAction();
    if (authMessage != null) {
      return _failAction(authMessage);
    }
    if (scannedAuthenticity == null) {
      return _failAction('Verify a QR token before claiming ownership.');
    }

    return _runAction<UniqueItem>(
      operation: () => _workflowService.claimOwnershipByQrToken(
        qrToken: scannedAuthenticity!.qrToken,
        claimCode: claimCode,
        userId: currentUserId,
      ),
      onSuccess: (UniqueItem? item, String message) {
        if (item != null) {
          _prependLocalNotification(
            title: 'Ownership updated',
            body: 'Ownership refreshed for ${item.serialNumber}.',
          );
        }
        return message;
      },
    );
  }

  Future<String> claimItem({
    required String itemId,
    required String claimCode,
  }) async {
    final String? authMessage = _requireAuthenticatedAction();
    if (authMessage != null) {
      return _failAction(authMessage);
    }

    return _runAction<UniqueItem>(
      operation: () => _workflowService.claimOwnership(
        itemId: itemId,
        claimCode: claimCode,
        userId: currentUserId,
      ),
      onSuccess: (UniqueItem? item, String message) {
        if (item != null) {
          _prependLocalNotification(
            title: 'Ownership updated',
            body: 'Ownership refreshed for ${item.serialNumber}.',
          );
        }
        return message;
      },
    );
  }

  Future<String> createResale({
    required String itemId,
    required int priceCents,
  }) async {
    final String? authMessage = _requireAuthenticatedAction();
    if (authMessage != null) {
      return _failAction(authMessage);
    }

    return _runAction<Listing>(
      operation: () => _workflowService.createResaleListing(
        itemId: itemId,
        userId: currentUserId,
        priceCents: priceCents,
      ),
      onSuccess: (Listing? listing, String message) {
        if (listing != null) {
          _prependLocalNotification(
            title: 'Listing live',
            body: 'Listing ${listing.id} is live for on-platform resale.',
          );
        }
        return message;
      },
    );
  }

  Future<String> buyResale({required String itemId}) async {
    final String? authMessage = _requireAuthenticatedAction();
    if (authMessage != null) {
      return _failAction(authMessage);
    }
    final UniqueItem? item = itemById(itemId);
    if (item == null) {
      return _failAction('Collectible not found.');
    }

    isBusy = true;
    errorMessage = null;
    statusMessage = null;
    notifyListeners();

    final MarketplaceActionResult<ResaleCheckoutSession> result =
        await _workflowService.startResaleCheckout(
          itemId: itemId,
          buyerUserId: currentUserId,
          successUrl: _checkoutConfig.successUrl,
          cancelUrl: _checkoutConfig.cancelUrl,
        );
    isBusy = false;

    if (!result.success || result.data == null) {
      errorMessage = result.message;
      notifyListeners();
      return result.message;
    }

    final ResaleCheckoutSession session = result.data!;
    lastCheckoutOrderId = session.orderId;
    lastCheckoutUrl = session.checkoutUrl;

    bool launched = false;
    if (session.checkoutUrl != null && session.checkoutUrl!.trim().isNotEmpty) {
      launched = await launchUrl(Uri.parse(session.checkoutUrl!));
    }

    _prependLocalNotification(
      title: 'Checkout started',
      body:
          '${item.serialNumber} is in Stripe-hosted checkout. Ownership stays unchanged until webhook authorization and delivery review complete.',
    );

    statusMessage = launched
        ? 'Hosted Stripe checkout opened for ${item.serialNumber}. Return to the app after payment to await webhook confirmation.'
        : 'Hosted Stripe checkout is ready${session.checkoutUrl == null ? '.' : ': ${session.checkoutUrl}'}';
    notifyListeners();
    return statusMessage!;
  }

  Future<MarketplaceActionResult<ResaleCheckoutSession>> startManualCheckout({
    required String itemId,
  }) async {
    final String? authMessage = _requireAuthenticatedAction();
    if (authMessage != null) {
      return MarketplaceActionResult<ResaleCheckoutSession>(
        success: false,
        message: _failAction(authMessage),
      );
    }

    errorMessage = null;
    statusMessage = null;
    notifyListeners();

    final MarketplaceActionResult<ResaleCheckoutSession> result =
        await _workflowService.startResaleCheckout(
          itemId: itemId,
          buyerUserId: currentUserId,
          successUrl: null,
          cancelUrl: null,
        );
    if (result.success && result.data != null) {
      lastCheckoutOrderId = result.data!.orderId;
      statusMessage =
          'Manual payment instructions are ready. Submit your proof after paying with the reference ${result.data!.providerReference}.';
    } else {
      errorMessage = result.message;
    }
    notifyListeners();
    return result;
  }

  Future<MarketplaceActionResult<SelectedPaymentProof>>
  pickPaymentProof() async {
    try {
      final SelectedPaymentProof? proof = await _paymentProofPicker();
      if (proof == null) {
        return const MarketplaceActionResult<SelectedPaymentProof>(
          success: false,
          message: 'No screenshot was selected.',
        );
      }
      return MarketplaceActionResult<SelectedPaymentProof>(
        success: true,
        message: 'Payment screenshot selected.',
        data: proof,
      );
    } catch (error) {
      return MarketplaceActionResult<SelectedPaymentProof>(
        success: false,
        message: error.toString().replaceFirst('Bad state: ', ''),
      );
    }
  }

  Future<MarketplaceActionResult<ManualPaymentOrder>> submitManualPaymentProof({
    required String orderId,
    required String paymentMethod,
    required String payerName,
    required String payerPhone,
    required int paidAmountCents,
    required DateTime paidAt,
    required String? transactionReference,
    required SelectedPaymentProof proof,
  }) async {
    final String? authMessage = _requireAuthenticatedAction();
    if (authMessage != null) {
      return MarketplaceActionResult<ManualPaymentOrder>(
        success: false,
        message: _failAction(authMessage),
      );
    }

    errorMessage = null;
    statusMessage = null;
    notifyListeners();

    final MarketplaceActionResult<ManualPaymentOrder> result =
        await _workflowService.submitManualPaymentProof(
          orderId: orderId,
          paymentMethod: paymentMethod,
          payerName: payerName,
          payerPhone: payerPhone,
          paidAmountCents: paidAmountCents,
          paidAt: paidAt,
          transactionReference: transactionReference,
          proofBytes: proof.bytes,
          proofFileName: proof.fileName,
          proofContentType: proof.contentType,
        );

    if (result.success) {
      statusMessage = result.message;
    } else {
      errorMessage = result.message;
    }
    notifyListeners();
    return result;
  }

  Future<MarketplaceActionResult<ItemComment>> addComment({
    required String itemId,
    required String body,
  }) async {
    final String? authMessage = _requireAuthenticatedAction();
    if (authMessage != null) {
      return MarketplaceActionResult<ItemComment>(
        success: false,
        message: _failAction(authMessage),
      );
    }

    errorMessage = null;
    statusMessage = null;
    notifyListeners();

    final MarketplaceActionResult<ItemComment> result = await _repository
        .addItemComment(itemId: itemId, body: body);

    if (result.success) {
      if (result.data != null) {
        _prependLocalNotification(
          title: 'New comment',
          body:
              'Conversation updated for ${itemById(itemId)?.serialNumber ?? itemId}.',
        );
      }
      statusMessage = result.message;
    } else {
      errorMessage = result.message;
    }

    notifyListeners();
    return result;
  }

  Future<String> confirmDelivery({required String orderId}) async {
    final String? authMessage = _requireAuthenticatedAction();
    if (authMessage != null) {
      return _failAction(authMessage);
    }

    return _runAction<UniqueItem>(
      operation: () => _workflowService.confirmDelivery(
        orderId: orderId,
        userId: currentUserId,
        note: 'Collector confirmed delivery from the customer app.',
      ),
      onSuccess: (UniqueItem? item, String message) {
        if (item != null) {
          _prependLocalNotification(
            title: 'Delivery confirmed',
            body: '${item.serialNumber} is now eligible for payout release.',
          );
        }
        return message;
      },
    );
  }

  Future<String> openDispute({
    required String itemId,
    required String reason,
    required bool freeze,
  }) async {
    final String? authMessage = _requireAuthenticatedAction();
    if (authMessage != null) {
      return _failAction(authMessage);
    }

    return _runAction<UniqueItem>(
      operation: () => _workflowService.openDispute(
        itemId: itemId,
        userId: currentUserId,
        reason: reason,
        freeze: freeze,
      ),
      onSuccess: (UniqueItem? item, String message) {
        if (item != null) {
          _prependLocalNotification(
            title: 'Dispute opened',
            body:
                '${item.serialNumber} moved to ${item.state.key.replaceAll('_', ' ')} for review.',
          );
        }
        return message;
      },
    );
  }

  Future<String> toggleSavedItem(String itemId) async {
    final String? authMessage = _requireAuthenticatedAction();
    if (authMessage != null) {
      return _failAction(authMessage);
    }

    final bool isSaved = savedItemIds.contains(itemId);
    final MarketplaceActionResult<void> result = isSaved
        ? await _workflowService.removeSavedItem(itemId: itemId)
        : await _workflowService.saveItem(itemId: itemId);
    if (result.success) {
      await _refreshCompanionData();
      statusMessage = result.message;
    } else {
      errorMessage = result.message;
    }
    notifyListeners();
    return result.message;
  }

  Future<void> _runAuthRequest({
    required Future<AuthActionResult> Function() operation,
    required String successMessageFallback,
  }) async {
    isBusy = true;
    errorMessage = null;
    statusMessage = null;
    notifyListeners();

    final AuthActionResult result = await operation();
    if (!result.success) {
      isBusy = false;
      errorMessage = result.message;
      notifyListeners();
      return;
    }

    if (result.requiresEmailConfirmation || _authService.currentUser == null) {
      isBusy = false;
      statusMessage = result.message;
      notifyListeners();
      return;
    }

    await _syncSessionState(
      restoredMessage: result.message.isEmpty
          ? successMessageFallback
          : result.message,
    );
  }

  Future<void> _syncSessionState({String? restoredMessage}) async {
    final User? user = _authService.currentUser;
    errorMessage = null;

    if (user == null) {
      await _liveSyncSubscription?.cancel();
      _liveSyncSubscription = null;
      currentUserId = '';
      currentUserEmail = null;
      currentDisplayName = null;
      isAuthenticated = false;
      await _repository.refresh(userId: '');
      notificationFeed = const <CollectorNotification>[];
      savedItemIds = <String>{};
      isInitializing = false;
      isBusy = false;
      if (restoredMessage != null) {
        statusMessage = restoredMessage;
      } else if (!authConfigured) {
        errorMessage =
            'Supabase is not configured. Add SUPABASE_URL and SUPABASE_ANON_KEY to this build.';
      }
      notifyListeners();
      return;
    }

    currentUserId = user.id;
    currentUserEmail = user.email;
    currentDisplayName = _displayNameForUser(user);
    await _repository.refresh(userId: user.id);
    await _refreshCompanionData();
    _startLiveSync(user.id);
    isAuthenticated = true;
    isInitializing = false;
    isBusy = false;
    statusMessage =
        restoredMessage ??
        'Marketplace refreshed from Supabase for the active collector session.';
    notifyListeners();
  }

  String? _requireAuthenticatedAction() {
    if (!authConfigured) {
      return 'Supabase is not configured for this build.';
    }
    if (!isAuthenticated || currentUserId.isEmpty) {
      return 'Sign in with your collector account to continue.';
    }
    return null;
  }

  String _failAction(String message) {
    errorMessage = message;
    notifyListeners();
    return message;
  }

  Future<String> _runAction<T>({
    required Future<MarketplaceActionResult<T>> Function() operation,
    required String Function(T? data, String message) onSuccess,
  }) async {
    isBusy = true;
    errorMessage = null;
    statusMessage = null;
    notifyListeners();

    final MarketplaceActionResult<T> result = await operation();
    isBusy = false;
    if (result.success) {
      statusMessage = onSuccess(result.data, result.message);
      notifyListeners();
      return statusMessage!;
    }

    errorMessage = result.message;
    notifyListeners();
    return result.message;
  }

  String _displayNameForUser(User user) {
    final String? metadataDisplayName = user.userMetadata?['display_name']
        ?.toString();
    if (metadataDisplayName != null && metadataDisplayName.trim().isNotEmpty) {
      return metadataDisplayName.trim();
    }
    final String? email = user.email;
    if (email != null && email.contains('@')) {
      return email.split('@').first;
    }
    return 'Collector';
  }

  Future<void> _refreshCompanionData({bool notify = false}) async {
    final MarketplaceActionResult<List<CollectorNotification>> notifications =
        await _workflowService.fetchNotifications();
    if (notifications.success && notifications.data != null) {
      final List<CollectorNotification> localOnly = notificationFeed
          .where((CollectorNotification item) => item.id.startsWith('local-'))
          .toList(growable: false);
      final Set<String> serverIds = notifications.data!
          .map((CollectorNotification item) => item.id)
          .toSet();
      notificationFeed =
          <CollectorNotification>[
            ...localOnly.where(
              (CollectorNotification item) => !serverIds.contains(item.id),
            ),
            ...notifications.data!,
          ]..sort(
            (CollectorNotification a, CollectorNotification b) =>
                b.createdAt.compareTo(a.createdAt),
          );
    }

    final MarketplaceActionResult<List<SavedCollectible>> saved =
        await _workflowService.fetchSavedItems();
    if (saved.success && saved.data != null) {
      savedItemIds = saved.data!
          .map((SavedCollectible item) => item.itemId)
          .toSet();
    }
    if (notify) {
      notifyListeners();
    }
  }

  void _prependLocalNotification({
    required String title,
    required String body,
  }) {
    notificationFeed = <CollectorNotification>[
      CollectorNotification(
        id: 'local-${DateTime.now().microsecondsSinceEpoch}',
        title: title,
        body: body,
        createdAt: DateTime.now(),
        read: false,
      ),
      ...notificationFeed,
    ];
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _authenticityLinkSubscription?.cancel();
    _liveSyncSubscription?.cancel();
    super.dispose();
  }

  void _startLiveSync(String userId) {
    _liveSyncSubscription?.cancel();
    _liveSyncSubscription = _workflowService
        .watchCustomerData(userId: userId)
        .listen((_) {
          unawaited(_refreshLiveData(showBusy: false, preserveStatus: true));
        });
  }

  Future<void> _refreshLiveData({
    required bool showBusy,
    required bool preserveStatus,
  }) async {
    if (_isLiveRefreshInFlight || currentUserId.isEmpty) {
      return;
    }
    _isLiveRefreshInFlight = true;
    final String? previousStatus = statusMessage;
    final String? previousError = errorMessage;
    if (showBusy) {
      isBusy = true;
      notifyListeners();
    }
    try {
      await _repository.refresh(userId: currentUserId);
      await _refreshCompanionData();
      if (preserveStatus) {
        statusMessage = previousStatus;
        errorMessage = previousError;
      }
      notifyListeners();
    } finally {
      if (showBusy) {
        isBusy = false;
        notifyListeners();
      }
      _isLiveRefreshInFlight = false;
    }
  }

  List<_ActivityEntry> _buildActivityLog() {
    final List<_ActivityEntry> entries = <_ActivityEntry>[];

    for (final CollectorNotification notification in notificationFeed) {
      entries.add(
        _ActivityEntry(
          id: 'notification-${notification.id}',
          title: notification.title,
          detail: notification.body,
          occurredAt: notification.createdAt,
          category: _notificationCategory(notification),
          status: notification.read ? 'read' : 'unread',
        ),
      );
    }

    for (final UniqueItem item in items) {
      final ManualPaymentOrder? paymentOrder = manualPaymentFor(item.id);
      if (paymentOrder != null) {
        entries.add(
          _ActivityEntry(
            id: 'payment-order-${paymentOrder.orderId}',
            title: 'Payment flow started',
            detail:
                'Reference ${paymentOrder.paymentReference} for ${item.serialNumber}.',
            occurredAt: paymentOrder.createdAt,
            category: 'payment',
            status: paymentOrder.orderStatus,
          ),
        );
        if (paymentOrder.submittedAt != null) {
          entries.add(
            _ActivityEntry(
              id: 'payment-submitted-${paymentOrder.orderId}',
              title: 'Payment proof submitted',
              detail:
                  '${paymentOrder.paymentMethod ?? 'Manual transfer'} for ${item.serialNumber}.',
              occurredAt: paymentOrder.submittedAt!,
              category: 'payment',
              status: paymentOrder.reviewStatus ?? paymentOrder.paymentStatus,
            ),
          );
        }
        if (paymentOrder.reviewedAt != null) {
          entries.add(
            _ActivityEntry(
              id: 'payment-reviewed-${paymentOrder.orderId}',
              title: _manualPaymentStatusLabel(paymentOrder),
              detail: _manualPaymentStatusMessage(paymentOrder),
              occurredAt: paymentOrder.reviewedAt!,
              category: 'payment',
              status: paymentOrder.reviewStatus ?? paymentOrder.paymentStatus,
            ),
          );
        }
      }

      for (final OwnershipRecord history in historyFor(item.id)) {
        entries.add(
          _ActivityEntry(
            id: 'ownership-${history.id}-acquired',
            title: 'Ownership recorded',
            detail: '${item.serialNumber} was added to your collector history.',
            occurredAt: history.acquiredAt,
            category: 'claim',
            status: 'acquired',
          ),
        );
        if (history.relinquishedAt != null) {
          entries.add(
            _ActivityEntry(
              id: 'ownership-${history.id}-relinquished',
              title: 'Ownership transferred',
              detail:
                  '${item.serialNumber} left your collector history after an on-platform transfer.',
              occurredAt: history.relinquishedAt!,
              category: 'resale',
              status: 'transferred',
            ),
          );
        }
      }
    }

    entries.sort(
      (_ActivityEntry a, _ActivityEntry b) =>
          b.occurredAt.compareTo(a.occurredAt),
    );
    return entries;
  }
}

class CheckoutPresentationConfig {
  const CheckoutPresentationConfig({
    required this.successUrl,
    required this.cancelUrl,
  });

  final String? successUrl;
  final String? cancelUrl;

  static CheckoutPresentationConfig fromEnvironment() {
    const String configuredSuccess = String.fromEnvironment(
      'CHECKOUT_SUCCESS_URL',
    );
    const String configuredCancel = String.fromEnvironment(
      'CHECKOUT_CANCEL_URL',
    );

    return CheckoutPresentationConfig(
      successUrl: _resolveReturnUrl(
        configured: configuredSuccess,
        status: 'success',
      ),
      cancelUrl: _resolveReturnUrl(
        configured: configuredCancel,
        status: 'cancel',
      ),
    );
  }

  static String? _resolveReturnUrl({
    required String configured,
    required String status,
  }) {
    if (configured.trim().isNotEmpty) {
      final Uri configuredUri = Uri.parse(configured.trim());
      return configuredUri
          .replace(
            queryParameters: <String, String>{
              ...configuredUri.queryParameters,
              'checkout_status': status,
            },
          )
          .toString();
    }

    if (Uri.base.scheme == 'http' || Uri.base.scheme == 'https') {
      return Uri.base
          .replace(
            queryParameters: <String, String>{
              ...Uri.base.queryParameters,
              'checkout_status': status,
            },
          )
          .toString();
    }

    return null;
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[Color(0xFF080808), Color(0xFF21180A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('ONE OF ONE'),
              SizedBox(height: 16),
              CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}

enum AuthMode { signIn, signUp, resetPassword }

class AuthScreen extends StatefulWidget {
  const AuthScreen({required this.controller, super.key});

  final CustomerController controller;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  AuthMode _mode = AuthMode.signIn;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      return;
    }

    switch (_mode) {
      case AuthMode.signIn:
        await widget.controller.signInWithEmail(
          email: _emailController.text,
          password: _passwordController.text,
        );
        return;
      case AuthMode.signUp:
        await widget.controller.signUpWithEmail(
          displayName: _displayNameController.text,
          username: _usernameController.text,
          email: _emailController.text,
          password: _passwordController.text,
        );
        return;
      case AuthMode.resetPassword:
        await widget.controller.sendPasswordReset(email: _emailController.text);
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isBusy = widget.controller.isBusy;
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFF060606)),
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      const Color(0xFF060606),
                      const Color(0xFF1A140D).withValues(alpha: 0.96),
                      const Color(0xFF090909),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -80,
              right: -40,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: <Color>[
                      OneOfOneTheme.gold.withValues(alpha: 0.16),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: -90,
              bottom: 80,
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: <Color>[
                      const Color(0xFF8A6E3D).withValues(alpha: 0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.14,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 26,
                      vertical: 44,
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      runAlignment: WrapAlignment.spaceBetween,
                      spacing: 18,
                      runSpacing: 16,
                      children: List<Widget>.generate(
                        18,
                        (int index) => Text(
                          'OOO-${(index + 1).toString().padLeft(3, '0')}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: const Color(0xFFE0C88A),
                                letterSpacing: 2.4,
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 470),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF111111).withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(34),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.07),
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.28),
                            blurRadius: 40,
                            offset: const Offset(0, 20),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
                        child: Form(
                          key: _formKey,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'ONE OF ONE',
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(
                                      color: const Color(0xFFE0C88A),
                                      letterSpacing: 2.8,
                                    ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                _heroTitle(),
                                style: Theme.of(context).textTheme.displaySmall
                                    ?.copyWith(
                                      color: const Color(0xFFF5F0E6),
                                      height: 1.0,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _headlineCopy(),
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: const Color(0xFFC9C0B3),
                                      height: 1.5,
                                    ),
                              ),
                              const SizedBox(height: 24),
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.04),
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.06),
                                  ),
                                ),
                                child: Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: _modeButton(
                                        context,
                                        AuthMode.signIn,
                                        'Sign in',
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _modeButton(
                                        context,
                                        AuthMode.signUp,
                                        'Create account',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _mode = AuthMode.resetPassword;
                                    });
                                  },
                                  child: Text(
                                    _mode == AuthMode.resetPassword
                                        ? 'Back to sign in'
                                        : 'Forgot password?',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (widget.controller.errorMessage != null)
                                _MessageCard(
                                  icon: Icons.error_outline,
                                  message: widget.controller.errorMessage!,
                                ),
                              if (widget.controller.statusMessage != null)
                                _MessageCard(
                                  icon: Icons.verified_outlined,
                                  message: widget.controller.statusMessage!,
                                ),
                              if (!widget.controller.authConfigured)
                                const _MessageCard(
                                  icon: Icons.lock_outline,
                                  message:
                                      'Collector access is available once the authentication environment is configured.',
                                ),
                              if (_mode == AuthMode.signUp) ...<Widget>[
                                _LuxuryTextField(
                                  child: TextFormField(
                                    controller: _displayNameController,
                                    decoration: const InputDecoration(
                                      labelText: 'Display name',
                                    ),
                                    textInputAction: TextInputAction.next,
                                    validator: (String? value) =>
                                        validateRequired(
                                          value ?? '',
                                          field: 'Display name',
                                        ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _LuxuryTextField(
                                  child: TextFormField(
                                    controller: _usernameController,
                                    decoration: const InputDecoration(
                                      labelText: 'Username',
                                    ),
                                    textInputAction: TextInputAction.next,
                                    validator: (String? value) =>
                                        validateUsername(value ?? ''),
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              _LuxuryTextField(
                                child: TextFormField(
                                  controller: _emailController,
                                  decoration: InputDecoration(
                                    labelText: _mode == AuthMode.resetPassword
                                        ? 'Collector email'
                                        : 'Email',
                                  ),
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction:
                                      _mode == AuthMode.resetPassword
                                      ? TextInputAction.done
                                      : TextInputAction.next,
                                  validator: (String? value) =>
                                      validateEmail(value ?? ''),
                                ),
                              ),
                              if (_mode != AuthMode.resetPassword) ...<Widget>[
                                const SizedBox(height: 12),
                                _LuxuryTextField(
                                  child: TextFormField(
                                    controller: _passwordController,
                                    decoration: InputDecoration(
                                      labelText: 'Password',
                                      suffixIcon: IconButton(
                                        onPressed: () {
                                          setState(() {
                                            _obscurePassword =
                                                !_obscurePassword;
                                          });
                                        },
                                        icon: Icon(
                                          _obscurePassword
                                              ? Icons.visibility_off
                                              : Icons.visibility,
                                        ),
                                      ),
                                    ),
                                    obscureText: _obscurePassword,
                                    textInputAction: TextInputAction.done,
                                    validator: (String? value) =>
                                        validatePassword(value ?? ''),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 22),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed:
                                      isBusy ||
                                          !widget.controller.authConfigured
                                      ? null
                                      : _submit,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFE0C88A),
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                  child: Text(_primaryActionLabel()),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.04),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.05),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Icon(
                                      Icons.verified_outlined,
                                      color: OneOfOneTheme.gold,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _footnoteCopy(),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: const Color(0xFFB8AF9F),
                                              height: 1.45,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeButton(BuildContext context, AuthMode mode, String label) {
    final bool selected = _mode == mode;
    return FilledButton(
      onPressed: () {
        setState(() {
          _mode = mode;
        });
      },
      style: FilledButton.styleFrom(
        backgroundColor: selected
            ? const Color(0xFFE0C88A)
            : Colors.transparent,
        foregroundColor: selected ? Colors.black : const Color(0xFFE3D9C8),
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelLarge),
    );
  }

  String _heroTitle() {
    switch (_mode) {
      case AuthMode.signIn:
        return 'Enter the vault.';
      case AuthMode.signUp:
        return 'Claim authenticated ownership.';
      case AuthMode.resetPassword:
        return 'Restore collector access.';
    }
  }

  String _headlineCopy() {
    switch (_mode) {
      case AuthMode.signIn:
        return 'Access verified collectibles, protected resale, and your private collector archive.';
      case AuthMode.signUp:
        return 'Create your collector identity to hold provenance, ownership, and protected market movement in one place.';
      case AuthMode.resetPassword:
        return 'Reset your password to return to your authenticated archive and verified ownership history.';
    }
  }

  String _primaryActionLabel() {
    switch (_mode) {
      case AuthMode.signIn:
        return 'Enter vault';
      case AuthMode.signUp:
        return 'Create collector account';
      case AuthMode.resetPassword:
        return 'Send reset link';
    }
  }

  String _footnoteCopy() {
    switch (_mode) {
      case AuthMode.signIn:
        return 'Verified collectibles only. Authenticated ownership, protected resale, and platform-validated transfers.';
      case AuthMode.signUp:
        return 'Collector identity keeps ownership, provenance, and future resale access tied to you.';
      case AuthMode.resetPassword:
        return 'Access recovery keeps your verified collection and collector history protected.';
    }
  }
}

class _LuxuryTextField extends StatelessWidget {
  const _LuxuryTextField({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF101010),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: child,
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: ListTile(leading: Icon(icon), title: Text(message)),
      ),
    );
  }
}

class PremiumHomeScreen extends StatelessWidget {
  const PremiumHomeScreen({required this.controller, super.key});

  final CustomerController controller;

  @override
  Widget build(BuildContext context) {
    final List<Artist> featuredArtists = controller.artists.take(6).toList();
    final List<Listing> marketListings = controller.listings.take(4).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: <Widget>[
        _PremiumHeroPanel(controller: controller),
        const SizedBox(height: 24),
        _CollectorUpdatePanel(controller: controller),
        const SizedBox(height: 32),
        const _SectionHeader(
          eyebrow: 'Curated voices',
          title: 'Featured artists',
          caption: 'Discover the makers shaping the latest collectible drop.',
        ),
        const SizedBox(height: 16),
        if (featuredArtists.isEmpty)
          const _EmptyLuxuryCard(
            title: 'Featured artists arriving soon',
            body:
                'Artist profiles will appear here as the next release is prepared.',
          ),
        if (featuredArtists.isNotEmpty)
          SizedBox(
            height: 248,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: featuredArtists.length,
              separatorBuilder: (_, _) => const SizedBox(width: 16),
              itemBuilder: (BuildContext context, int index) {
                final Artist artist = featuredArtists[index];
                return SizedBox(
                  width: 276,
                  child: _FeaturedArtistCard(
                    artist: artist,
                    onTap: () =>
                        _openArtistProfile(context, controller, artist),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 32),
        const _SectionHeader(
          eyebrow: 'Market movement',
          title: 'Recent resale activity',
          caption: 'A quieter view of verified movement across the market.',
        ),
        const SizedBox(height: 16),
        if (marketListings.isEmpty)
          const _EmptyLuxuryCard(
            title: 'No live resale movement',
            body:
                'Verified market activity will appear once collectors list pieces for transfer.',
          ),
        ...marketListings.map((Listing listing) {
          final UniqueItem? item = controller.itemById(listing.itemId);
          final Artist? artist = item == null
              ? null
              : controller.artistFor(item);
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _MarketMovementCard(
              listing: listing,
              item: item,
              artist: artist,
              onTap: item == null
                  ? null
                  : () => _openItemDetail(context, controller, item.id),
            ),
          );
        }),
      ],
    );
  }
}

class _PremiumHeroPanel extends StatelessWidget {
  const _PremiumHeroPanel({required this.controller});

  final CustomerController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: OneOfOneTheme.gold.withValues(alpha: 0.12)),
        ),
        child: const Text('No collectible catalog is available yet.'),
      );
    }

    final UniqueItem item = controller.items.first;
    final Artist? artist = controller.artistFor(item);
    final Artwork? artwork = controller.artworkFor(item);
    final List<String> descriptors = <String>[
      if (item.askingPrice != null) 'Limited',
      if (item.claimCodeConsumed || item.currentOwnerUserId != null) 'Verified',
      if (artist != null) 'Hand-finished',
    ];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E0E),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: OneOfOneTheme.gold.withValues(alpha: 0.14)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.26),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AspectRatio(
              aspectRatio: 0.92,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  _EditorialImage(
                    imageUrl: item.imageUrls.isEmpty
                        ? null
                        : item.imageUrls.first,
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Colors.black.withValues(alpha: 0.06),
                          Colors.black.withValues(alpha: 0.18),
                          const Color(0xFF090909).withValues(alpha: 0.96),
                        ],
                        stops: const <double>[0.0, 0.42, 1.0],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 18,
                    left: 18,
                    right: 18,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        const _HeroMetaChip(label: 'Latest drop'),
                        ...descriptors.map(
                          (String descriptor) =>
                              _HeroMetaChip(label: descriptor),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 22,
                    right: 22,
                    bottom: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (artist != null)
                          Text(
                            artist.displayName.toUpperCase(),
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  letterSpacing: 1.6,
                                  color: const Color(0xFFE5D3A3),
                                ),
                          ),
                        const SizedBox(height: 10),
                        Text(
                          artwork?.title ?? item.productName,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                fontSize: 34,
                                height: 1.04,
                                color: const Color(0xFFF5F1E8),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          item.productName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: const Color(0xFFD4CCC0),
                                height: 1.45,
                              ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            _LuxuryInfoChip(label: item.serialNumber),
                            _LuxuryInfoChip(
                              label: item.state.key.replaceAll('_', ' '),
                            ),
                            if (item.askingPrice != null)
                              _LuxuryInfoChip(
                                label: formatCurrency(item.askingPrice!),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      artist?.authenticityStatement ??
                          'Verified ownership, provenance, and collector-first transfer integrity.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFC9C1B6),
                        height: 1.45,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  FilledButton(
                    onPressed: () {
                      _openItemDetail(context, controller, item.id);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE0C88A),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Text('Explore piece'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectorUpdatePanel extends StatelessWidget {
  const _CollectorUpdatePanel({required this.controller});

  final CustomerController controller;

  @override
  Widget build(BuildContext context) {
    final _ActivityEntry? latestActivity = controller.activityLog.isEmpty
        ? null
        : controller.activityLog.first;
    final List<_UpdateTileData> updates = <_UpdateTileData>[
      if (controller.unreadNotificationCount > 0)
        _UpdateTileData(
          icon: Icons.notifications_active_outlined,
          label: 'Unread updates',
          value: '${controller.unreadNotificationCount}',
          detail: controller.unreadNotificationCount == 1
              ? 'One private notification is waiting.'
              : '${controller.unreadNotificationCount} private notifications are waiting.',
          accent: const Color(0xFFC25656),
        ),
      if (controller.statusMessage != null)
        _UpdateTileData(
          icon: Icons.verified_outlined,
          label: 'Latest status',
          value: 'Updated',
          detail: controller.statusMessage!,
          accent: OneOfOneTheme.gold,
        ),
      if (controller.errorMessage != null)
        _UpdateTileData(
          icon: Icons.priority_high_outlined,
          label: 'Needs attention',
          value: 'Review',
          detail: controller.errorMessage!,
          accent: const Color(0xFFB36A58),
        ),
      if (latestActivity != null)
        _UpdateTileData(
          icon: Icons.history_toggle_off,
          label: 'Activity',
          value: latestActivity.status,
          detail: latestActivity.title,
          accent: const Color(0xFF8E7F5C),
        ),
    ];

    if (updates.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: OneOfOneTheme.gold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.auto_awesome_outlined,
                color: OneOfOneTheme.gold,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Your collector profile is quiet for now. New movement will surface here in a calmer, editorial way.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFD0C8BC),
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: updates
          .take(3)
          .map(
            (_UpdateTileData update) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CollectorUpdateTile(update: update),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _CollectorUpdateTile extends StatelessWidget {
  const _CollectorUpdateTile({required this.update});

  final _UpdateTileData update;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: update.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(update.icon, color: update.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        update.label,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: const Color(0xFFE9E1D2),
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    Text(
                      update.value,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: update.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  update.detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFBEB6AB),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.eyebrow,
    required this.title,
    required this.caption,
  });

  final String eyebrow;
  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          eyebrow.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: OneOfOneTheme.gold,
            letterSpacing: 1.8,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: const Color(0xFFF5F0E6),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          caption,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: const Color(0xFFAEA79B),
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _FeaturedArtistCard extends StatelessWidget {
  const _FeaturedArtistCard({required this.artist, required this.onTap});

  final Artist artist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: const Color(0xFF151515),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFF1A1814), Color(0xFF121212)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: OneOfOneTheme.gold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.auto_awesome, color: OneOfOneTheme.gold),
              ),
              const Spacer(),
              Text(
                artist.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: const Color(0xFFF4EEDF),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _artistSummaryLine(artist),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFC6BEB1),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  _LuxuryInfoChip(label: '${artist.royaltyBps / 100}% royalty'),
                  Text(
                    'Discover artist',
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: OneOfOneTheme.gold),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarketMovementCard extends StatelessWidget {
  const _MarketMovementCard({
    required this.listing,
    required this.item,
    required this.artist,
    required this.onTap,
  });

  final Listing listing;
  final UniqueItem? item;
  final Artist? artist;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final String title = item?.productName ?? 'Verified collectible';
    final String subtitle = item == null
        ? 'Available now for verified on-platform resale.'
        : '${artist?.displayName ?? 'Private seller'} · ${item!.serialNumber}';
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: <Widget>[
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: OneOfOneTheme.gold.withValues(alpha: 0.1),
                ),
                child: Icon(
                  Icons.north_east,
                  color: OneOfOneTheme.gold.withValues(alpha: 0.92),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFFF2EBDC),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFB7AF9F),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    formatCurrency(listing.askingPrice),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: OneOfOneTheme.gold,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'View collection',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: const Color(0xFFD7CDBA),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LuxuryInfoChip extends StatelessWidget {
  const _LuxuryInfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: const Color(0xFFE8E0D0)),
      ),
    );
  }
}

class _HeroMetaChip extends StatelessWidget {
  const _HeroMetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: const Color(0xFFF2E7C9),
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _EmptyLuxuryCard extends StatelessWidget {
  const _EmptyLuxuryCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xFFF2EBDC),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFFBFB7AA),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdateTileData {
  const _UpdateTileData({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final Color accent;
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({required this.controller, super.key});

  final CustomerController controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        _HeroPanel(controller: controller),
        const SizedBox(height: 16),
        if (controller.statusMessage != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.verified_outlined),
              title: Text(controller.statusMessage!),
            ),
          ),
        if (controller.errorMessage != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.error_outline),
              title: Text(controller.errorMessage!),
            ),
          ),
        const SizedBox(height: 16),
        Text(
          'Featured artists',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (controller.artists.isEmpty)
          const Card(
            child: ListTile(
              title: Text('No featured artists are available yet.'),
            ),
          ),
        ...controller.artists.map(
          (Artist artist) => Card(
            child: ListTile(
              onTap: () => _openArtistProfile(context, controller, artist),
              title: Text(artist.displayName),
              subtitle: Text(artist.authenticityStatement),
              trailing: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text('${artist.royaltyBps / 100}% royalty'),
                  const SizedBox(height: 4),
                  Text('View', style: Theme.of(context).textTheme.labelMedium),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Recent resale activity',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (controller.listings.isEmpty)
          const Card(
            child: ListTile(title: Text('No live resale listings right now.')),
          ),
        ...controller.listings.map((Listing listing) {
          final UniqueItem? item = controller.itemById(listing.itemId);
          final Artist? artist = item == null
              ? null
              : controller.artistFor(item);
          final String title = item == null
              ? 'Verified resale ${formatCurrency(listing.askingPrice)}'
              : '${item.productName} ${formatCurrency(listing.askingPrice)}';
          final String subtitle = item == null
              ? 'Available now for verified on-platform resale.'
              : '${artist?.displayName ?? 'Private seller'} • ${item.serialNumber}';
          return Card(
            child: ListTile(
              onTap: item == null
                  ? null
                  : () => _openItemDetail(context, controller, item.id),
              title: Text(title),
              subtitle: Text(subtitle),
              trailing: const Text('View'),
            ),
          );
        }),
      ],
    );
  }
}

void _openItemDetail(
  BuildContext context,
  CustomerController controller,
  String itemId,
) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ItemDetailScreen(controller: controller, itemId: itemId),
    ),
  );
}

void _openArtistProfile(
  BuildContext context,
  CustomerController controller,
  Artist artist,
) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          ArtistProfileScreen(controller: controller, artist: artist),
    ),
  );
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.controller});

  final CustomerController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: <Color>[Color(0xFF20170A), Color(0xFF0A0A0A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(28),
        ),
        child: const Text('No collectible catalog is available yet.'),
      );
    }

    final UniqueItem item = controller.items.first;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF20170A), Color(0xFF0A0A0A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Latest collectible drop',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            item.productName,
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Public serial ${item.serialNumber} - ${item.state.key.replaceAll('_', ' ')}',
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              _openItemDetail(context, controller, item.id);
            },
            child: const Text('View collectible'),
          ),
        ],
      ),
    );
  }
}

class ExploreScreen extends StatelessWidget {
  const ExploreScreen({required this.controller, super.key});

  final CustomerController controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Curated shop',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFFF4EEDF),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Browse verified pieces by artist, collectible, or serial.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFB9B1A5),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: InputDecoration(
                  hintText: 'Search artist, collectible, or serial',
                  hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF8E867A),
                  ),
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: const Color(0xFF101010),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(
                      color: OneOfOneTheme.gold.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    _ShopQuickFilterChip(label: 'Available now'),
                    SizedBox(width: 10),
                    _ShopQuickFilterChip(label: 'Verified resale'),
                    SizedBox(width: 10),
                    _ShopQuickFilterChip(label: 'Artist-led drops'),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (controller.items.isEmpty)
          const Card(
            child: ListTile(
              title: Text('No collectibles available yet.'),
              subtitle: Text(
                'Seed the catalog in Supabase to populate the marketplace.',
              ),
            ),
          ),
        if (controller.items.isNotEmpty)
          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.53,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: controller.items.map((UniqueItem item) {
              return _ShopItemCard(controller: controller, item: item);
            }).toList(),
          ),
      ],
    );
  }
}

class _ShopItemCard extends StatelessWidget {
  const _ShopItemCard({required this.controller, required this.item});

  final CustomerController controller;
  final UniqueItem item;

  @override
  Widget build(BuildContext context) {
    final Artist? artist = controller.artistFor(item);
    final String availabilityLabel = _shopAvailabilityLabel(item);
    final bool isSaved = controller.savedItemIds.contains(item.id);
    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: () => _openItemDetail(context, controller, item.id),
      child: Ink(
        decoration: BoxDecoration(
          color: const Color(0xFF171717),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: OneOfOneTheme.gold.withValues(alpha: 0.18)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AspectRatio(
              aspectRatio: 0.86,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                    child: _EditorialImage(
                      imageUrl: item.imageUrls.isEmpty
                          ? null
                          : item.imageUrls.first,
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Colors.black.withValues(alpha: 0.04),
                          Colors.black.withValues(alpha: 0.14),
                          Colors.black.withValues(alpha: 0.6),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: _HeroMetaChip(label: availabilityLabel),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => controller.toggleSavedItem(item.id),
                        child: Ink(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.26),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Icon(
                            isSaved ? Icons.bookmark : Icons.bookmark_border,
                            size: 18,
                            color: isSaved
                                ? const Color(0xFFE0C88A)
                                : const Color(0xFFF1EBDD),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (artist != null)
                    Text(
                      artist.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: const Color(0xFFD8C89C),
                        letterSpacing: 0.5,
                      ),
                    ),
                  if (artist != null) const SizedBox(height: 8),
                  Text(
                    item.productName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: const Color(0xFFF3ECDD),
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    item.askingPrice == null
                        ? availabilityLabel
                        : formatCurrency(item.askingPrice!),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: item.askingPrice == null
                          ? const Color(0xFFE9DFCA)
                          : OneOfOneTheme.gold,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      _LuxuryInfoChip(label: item.serialNumber),
                      _LuxuryInfoChip(label: availabilityLabel),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShopQuickFilterChip extends StatelessWidget {
  const _ShopQuickFilterChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: const Color(0xFFD9D0C1)),
      ),
    );
  }
}

String _shopAvailabilityLabel(UniqueItem item) {
  if (item.askingPrice != null) {
    return 'Available now';
  }
  switch (item.state) {
    case ItemState.listedForResale:
      return 'Listed for resale';
    case ItemState.soldUnclaimed:
      return 'Sold unclaimed';
    case ItemState.claimed:
      return 'Held';
    case ItemState.transferred:
      return 'Collector held';
    default:
      return item.state.key.replaceAll('_', ' ');
  }
}

class ItemDetailScreen extends StatelessWidget {
  const ItemDetailScreen({
    required this.controller,
    required this.itemId,
    super.key,
  });

  final CustomerController controller;
  final String itemId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(controller.itemById(itemId)?.productName ?? 'Collectible'),
      ),
      body: AnimatedBuilder(
        animation: controller,
        builder: (BuildContext context, _) {
          final UniqueItem? item = controller.itemById(itemId);
          if (item == null) {
            return const Center(child: Text('Collectible not found.'));
          }

          final Artwork? artwork = controller.artworkFor(item);
          final Artist? artist = controller.artistFor(item);
          final FeeBreakdown breakdown = controller.breakdownFor(item);
          final List<OwnershipRecord> history = controller.historyFor(item.id);
          final List<ItemComment> comments = controller.commentsFor(item.id);
          final ManualPaymentOrder? paymentOrder = controller.manualPaymentFor(
            item.id,
          );
          return ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              SizedBox(
                height: 320,
                child: _InteractiveCollectiblePreview(item: item),
              ),
              const SizedBox(height: 16),
              Text(
                artwork?.title ?? item.productName,
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: artist == null
                    ? null
                    : () => _openArtistProfile(context, controller, artist),
                child: Text(
                  'Artist: ${artist?.displayName ?? 'Unknown artist'}',
                  style: TextStyle(
                    color: artist == null ? null : OneOfOneTheme.gold,
                    decoration: artist == null
                        ? TextDecoration.none
                        : TextDecoration.underline,
                    decorationColor: OneOfOneTheme.gold,
                  ),
                ),
              ),
              Text('Serial: ${item.serialNumber}'),
              const Text('Authenticity: verified human-made artwork'),
              const SizedBox(height: 12),
              Text(
                artwork?.story ??
                    'Story and concept note will appear here once published.',
              ),
              const SizedBox(height: 12),
              Text(
                'Provenance proof',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (artwork == null || artwork.humanMadeProof.isEmpty)
                const ListTile(title: Text('No proof assets published yet.')),
              if (artwork != null)
                ...artwork.humanMadeProof.map(
                  (String proof) => ListTile(title: Text(proof)),
                ),
              const SizedBox(height: 12),
              Text(
                'Ownership history summary',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (history.isEmpty)
                const ListTile(
                  title: Text('No verified ownership records yet.'),
                ),
              ...history.map(
                (OwnershipRecord record) => ListTile(
                  title: Text(record.ownerUserId),
                  subtitle: Text(
                    'Acquired ${record.acquiredAt.toIso8601String().split('T').first}',
                  ),
                ),
              ),
              if (artist != null) ...<Widget>[
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    onTap: () =>
                        _openArtistProfile(context, controller, artist),
                    title: Text(artist.displayName),
                    subtitle: Text(
                      artist.authenticityStatement,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16,
                    ),
                  ),
                ),
              ],
              if (item.askingPrice != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  'Resale financials',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                ListTile(
                  title: const Text('Asking price'),
                  trailing: Text(formatCurrency(breakdown.grossAmount)),
                ),
                ListTile(
                  title: const Text('Platform fee'),
                  trailing: Text(formatCurrency(breakdown.platformFee)),
                ),
                ListTile(
                  title: const Text('Artist royalty'),
                  trailing: Text(formatCurrency(breakdown.artistRoyalty)),
                ),
                ListTile(
                  title: const Text('Seller payout'),
                  trailing: Text(formatCurrency(breakdown.sellerPayout)),
                ),
              ],
              if (paymentOrder != null) ...<Widget>[
                const SizedBox(height: 12),
                _ManualPaymentStatusCard(
                  controller: controller,
                  item: item,
                  paymentOrder: paymentOrder,
                ),
              ],
              const SizedBox(height: 16),
              _CommentsSection(
                controller: controller,
                item: item,
                comments: comments,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  if (_manualPaymentActionLabel(
                        item: item,
                        controller: controller,
                        paymentOrder: paymentOrder,
                      )
                      case final String paymentActionLabel)
                    ElevatedButton(
                      onPressed: () async {
                        await _openManualPaymentSheet(
                          context,
                          controller,
                          item,
                        );
                      },
                      child: Text(paymentActionLabel),
                    ),
                  if (item.currentOwnerUserId == controller.currentUserId &&
                      (item.state == ItemState.claimed ||
                          item.state == ItemState.transferred) &&
                      !item.state.isRestricted)
                    OutlinedButton(
                      onPressed: () async {
                        final String message = await controller.createResale(
                          itemId: item.id,
                          priceCents: 225000,
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text(message)));
                        }
                      },
                      child: const Text('Resell item'),
                    ),
                  OutlinedButton(
                    onPressed: () async {
                      final String message = await controller.toggleSavedItem(
                        item.id,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(message)));
                      }
                    },
                    child: Text(
                      controller.savedItemIds.contains(item.id)
                          ? 'Unsave'
                          : 'Save item',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      final String message = await controller.openDispute(
                        itemId: item.id,
                        reason:
                            'Collector requested review of ownership condition.',
                        freeze:
                            item.state == ItemState.stolenFlagged ||
                            item.state == ItemState.frozen,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(message)));
                      }
                    },
                    child: const Text('Report dispute'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

Future<void> _openManualPaymentSheet(
  BuildContext context,
  CustomerController controller,
  UniqueItem item,
) async {
  ManualPaymentOrder? paymentOrder = controller.manualPaymentFor(item.id);
  if (paymentOrder == null) {
    final MarketplaceActionResult<ResaleCheckoutSession> checkout =
        await controller.startManualCheckout(itemId: item.id);
    if (!context.mounted) {
      return;
    }
    if (!checkout.success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(checkout.message)));
      return;
    }
    paymentOrder = controller.manualPaymentFor(item.id);
    if (paymentOrder == null) {
      paymentOrder = ManualPaymentOrder(
        orderId: checkout.data!.orderId,
        itemId: item.id,
        orderStatus: 'payment_pending',
        paymentStatus: 'pending',
        paymentProvider: checkout.data!.provider,
        paymentReference: checkout.data!.providerReference,
        amountCents: item.askingPrice ?? 0,
        createdAt: DateTime.now(),
      );
    }
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    backgroundColor: const Color(0xFF14110D),
    builder: (BuildContext context) {
      return _ManualPaymentSheet(
        controller: controller,
        item: item,
        paymentOrder: paymentOrder!,
      );
    },
  );
}

class _ManualPaymentStatusCard extends StatelessWidget {
  const _ManualPaymentStatusCard({
    required this.controller,
    required this.item,
    required this.paymentOrder,
  });

  final CustomerController controller;
  final UniqueItem item;
  final ManualPaymentOrder paymentOrder;

  @override
  Widget build(BuildContext context) {
    final String statusLabel = _manualPaymentStatusLabel(paymentOrder);
    final String statusMessage = _manualPaymentStatusMessage(paymentOrder);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Payment verification',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: OneOfOneTheme.gold.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: OneOfOneTheme.gold.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Text(statusLabel),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Order ref ${paymentOrder.paymentReference}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text('Amount due: ${formatCurrency(paymentOrder.amountCents)}'),
            const SizedBox(height: 8),
            Text(statusMessage),
            if (paymentOrder.paymentMethod != null)
              Text('Method: ${paymentOrder.paymentMethod}'),
            if (paymentOrder.payerName != null)
              Text('Payer: ${paymentOrder.payerName}'),
            if (paymentOrder.payerPhone != null)
              Text('Phone: ${paymentOrder.payerPhone}'),
            if (paymentOrder.reviewNote != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  paymentOrder.reviewNote!,
                  style: TextStyle(
                    color: OneOfOneTheme.gold.withValues(alpha: 0.9),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            if (paymentOrder.canSubmitProof)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () =>
                      _openManualPaymentSheet(context, controller, item),
                  child: Text(
                    paymentOrder.reviewStatus == 'resubmission_requested'
                        ? 'Resubmit proof'
                        : 'Continue payment',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ManualPaymentSheet extends StatefulWidget {
  const _ManualPaymentSheet({
    required this.controller,
    required this.item,
    required this.paymentOrder,
  });

  final CustomerController controller;
  final UniqueItem item;
  final ManualPaymentOrder paymentOrder;

  @override
  State<_ManualPaymentSheet> createState() => _ManualPaymentSheetState();
}

class _ManualPaymentSheetState extends State<_ManualPaymentSheet> {
  static const int _maxProofBytes = 8 * 1024 * 1024;
  static const Set<String> _supportedProofContentTypes = <String>{
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
  };
  static const List<String> _methods = <String>[
    'WavePay',
    'KBZPay',
    'Bank transfer',
  ];

  late final TextEditingController _payerNameController;
  late final TextEditingController _payerPhoneController;
  late final TextEditingController _amountController;
  late final TextEditingController _paidAtController;
  late final TextEditingController _referenceController;
  String _paymentMethod = _methods.first;
  bool _submitting = false;
  String? _message;
  bool _messageIsError = false;
  SelectedPaymentProof? _proof;

  bool get _canSubmit =>
      !_submitting &&
      _proof != null &&
      _payerNameController.text.trim().isNotEmpty &&
      _payerPhoneController.text.trim().isNotEmpty &&
      int.tryParse(_amountController.text.trim()) != null &&
      _parsePaidAt() != null;

  @override
  void initState() {
    super.initState();
    _payerNameController = TextEditingController(
      text: widget.controller.currentDisplayName ?? '',
    );
    _payerPhoneController = TextEditingController();
    _amountController = TextEditingController(
      text: widget.paymentOrder.amountCents.toString(),
    );
    _paidAtController = TextEditingController(
      text: DateTime.now().toLocal().toIso8601String().substring(0, 16),
    );
    _referenceController = TextEditingController();
  }

  @override
  void dispose() {
    _payerNameController.dispose();
    _payerPhoneController.dispose();
    _amountController.dispose();
    _paidAtController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  DateTime? _parsePaidAt() {
    final String raw = _paidAtController.text.trim();
    if (raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw.replaceFirst(' ', 'T'))?.toUtc();
  }

  String? _validateProof(SelectedPaymentProof proof) {
    if (!_supportedProofContentTypes.contains(proof.contentType)) {
      return 'Choose a PNG, JPG, WEBP, or GIF screenshot.';
    }
    if (proof.sizeBytes > _maxProofBytes) {
      return 'Payment screenshots must be 8 MB or smaller.';
    }
    return null;
  }

  Future<void> _pickProof() async {
    final MarketplaceActionResult<SelectedPaymentProof> result = await widget
        .controller
        .pickPaymentProof();
    if (!mounted) {
      return;
    }
    if (!result.success || result.data == null) {
      setState(() {
        _message = result.message == 'No screenshot was selected.'
            ? null
            : result.message;
        _messageIsError = result.message != 'No screenshot was selected.';
      });
      return;
    }
    final String? validationMessage = _validateProof(result.data!);
    if (validationMessage != null) {
      setState(() {
        _proof = null;
        _message = validationMessage;
        _messageIsError = true;
      });
      return;
    }
    setState(() {
      _proof = result.data!;
      _message = result.message;
      _messageIsError = false;
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit) {
      setState(() {
        _message =
            'Add payer details, paid amount/time, and a screenshot proof before submitting.';
        _messageIsError = true;
      });
      return;
    }

    setState(() {
      _submitting = true;
      _message = null;
      _messageIsError = false;
    });

    final MarketplaceActionResult<ManualPaymentOrder> result = await widget
        .controller
        .submitManualPaymentProof(
          orderId: widget.paymentOrder.orderId,
          paymentMethod: _paymentMethod,
          payerName: _payerNameController.text.trim(),
          payerPhone: _payerPhoneController.text.trim(),
          paidAmountCents: int.parse(_amountController.text.trim()),
          paidAt: _parsePaidAt()!,
          transactionReference: _referenceController.text.trim().isEmpty
              ? null
              : _referenceController.text.trim(),
          proof: _proof!,
        );

    if (!mounted) {
      return;
    }

    setState(() {
      _submitting = false;
      _message = result.success
          ? 'Payment proof submitted. Admin review will update this order status.'
          : result.message;
      _messageIsError = !result.success;
    });

    if (result.success) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets bottomInset = EdgeInsets.only(
      bottom: MediaQuery.of(context).viewInsets.bottom,
    );
    return SafeArea(
      child: Padding(
        padding: bottomInset,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Manual payment verification',
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close payment sheet',
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Send ${formatCurrency(widget.paymentOrder.amountCents)} using your local transfer method, then submit the proof below with reference ${widget.paymentOrder.paymentReference}.',
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text('Accepted methods'),
                      const SizedBox(height: 8),
                      Text(_methods.join(' | ')),
                      const SizedBox(height: 8),
                      Text(
                        'Payment reference: ${widget.paymentOrder.paymentReference}',
                      ),
                      Text(
                        'Amount due: ${formatCurrency(widget.paymentOrder.amountCents)}',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _paymentMethod,
                items: _methods
                    .map(
                      (String method) => DropdownMenuItem<String>(
                        value: method,
                        child: Text(method),
                      ),
                    )
                    .toList(),
                onChanged: _submitting
                    ? null
                    : (String? value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _paymentMethod = value;
                        });
                      },
                decoration: const InputDecoration(labelText: 'Payment method'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _payerNameController,
                enabled: !_submitting,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Payer name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _payerPhoneController,
                enabled: !_submitting,
                keyboardType: TextInputType.phone,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Payer phone'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amountController,
                enabled: !_submitting,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Paid amount (MMK)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _paidAtController,
                enabled: !_submitting,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Paid time',
                  helperText: 'Use YYYY-MM-DDTHH:MM or YYYY-MM-DD HH:MM',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _referenceController,
                enabled: !_submitting,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Transaction / reference number (optional)',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _submitting ? null : _pickProof,
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(
                  _proof == null
                      ? 'Upload payment screenshot'
                      : _proof!.fileName,
                ),
              ),
              if (_message != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _message!,
                  style: TextStyle(
                    color: _messageIsError
                        ? Theme.of(context).colorScheme.error
                        : OneOfOneTheme.gold,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _canSubmit ? _submit : null,
                    child: _submitting
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 10),
                              Text('Submitting...'),
                            ],
                          )
                        : const Text('Submit payment proof'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ArtistProfileScreen extends StatelessWidget {
  const ArtistProfileScreen({
    required this.controller,
    required this.artist,
    super.key,
  });

  final CustomerController controller;
  final Artist artist;

  @override
  Widget build(BuildContext context) {
    final List<Artwork> works = controller.artworksForArtist(artist.id);
    final List<UniqueItem> items = controller.itemsForArtist(artist.id);
    final String? heroImage = items.isEmpty || items.first.imageUrls.isEmpty
        ? null
        : items.first.imageUrls.first;
    final String artistStatement =
        artist.artistStatement?.trim().isNotEmpty == true
        ? artist.artistStatement!.trim()
        : artist.authenticityStatement;
    return Scaffold(
      appBar: AppBar(title: Text(artist.displayName)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[Color(0xFF20170A), Color(0xFF0A0A0A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: OneOfOneTheme.gold.withValues(alpha: 0.25),
              ),
            ),
            child: Stack(
              children: <Widget>[
                SizedBox(
                  height: 360,
                  width: double.infinity,
                  child: _EditorialImage(imageUrl: heroImage),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: <Color>[
                          Colors.black.withValues(alpha: 0.08),
                          Colors.black.withValues(alpha: 0.82),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        artist.displayName,
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _artistEditorialBio(artist, works.length, items.length),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: OneOfOneTheme.gold.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Artist statement',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 8),
                            Text(artistStatement),
                          ],
                        ),
                      ),
                      if (artist.fullBio?.trim().isNotEmpty == true) ...<Widget>[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.34),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Profile',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(artist.fullBio!.trim()),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Available works',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (items.isEmpty)
            const Card(
              child: ListTile(
                title: Text('No published works available right now.'),
              ),
            ),
          ...items.map((UniqueItem item) {
            final Artwork? artwork = controller.artworkFor(item);
            return Card(
              child: ListTile(
                onTap: () => _openItemDetail(context, controller, item.id),
                title: Text(artwork?.title ?? item.productName),
                subtitle: Text(
                  artwork?.story ?? item.serialNumber,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: SizedBox(
                  width: 72,
                  height: 72,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: _EditorialImage(
                      imageUrl: item.imageUrls.isEmpty
                          ? null
                          : item.imageUrls.first,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

String _artistEditorialBio(Artist artist, int artworkCount, int itemCount) {
  final String? shortBio = artist.shortBio?.trim();
  if (shortBio != null && shortBio.isNotEmpty) {
    return shortBio;
  }
  final String worksLabel = artworkCount == 1 ? 'work' : 'works';
  final String piecesLabel = itemCount == 1 ? 'piece' : 'pieces';
  return '${artist.displayName} is featured on One of One with '
      '$artworkCount published $worksLabel and $itemCount collectible $piecesLabel. '
      'Every release remains platform-verified and tied to the artist statement below.';
}

String _artistSummaryLine(Artist artist) {
  final String? shortBio = artist.shortBio?.trim();
  if (shortBio != null && shortBio.isNotEmpty) {
    return shortBio;
  }
  final String? statement = artist.artistStatement?.trim();
  if (statement != null && statement.isNotEmpty) {
    return statement;
  }
  return artist.authenticityStatement;
}

class _EditorialImage extends StatelessWidget {
  const _EditorialImage({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[Color(0xFF2A2112), Color(0xFF0F0F0F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Center(child: Text('Editorial image coming soon')),
      );
    }

    return Image.network(
      imageUrl!,
      fit: BoxFit.cover,
      errorBuilder:
          (BuildContext context, Object error, StackTrace? stackTrace) {
            return const Center(child: Text('Image unavailable'));
          },
    );
  }
}

class _InteractiveCollectiblePreview extends StatefulWidget {
  const _InteractiveCollectiblePreview({required this.item});

  final UniqueItem item;

  @override
  State<_InteractiveCollectiblePreview> createState() =>
      _InteractiveCollectiblePreviewState();
}

class _InteractiveCollectiblePreviewState
    extends State<_InteractiveCollectiblePreview> {
  double _rotationX = 0;
  double _rotationY = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (DragUpdateDetails details) {
        setState(() {
          _rotationY += details.delta.dx * 0.01;
          _rotationX -= details.delta.dy * 0.01;
        });
      },
      onDoubleTap: () {
        setState(() {
          _rotationX = 0;
          _rotationY = 0;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF191919),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: OneOfOneTheme.gold.withValues(alpha: 0.3)),
        ),
        child: Stack(
          children: <Widget>[
            Center(
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001)
                  ..rotateX(_rotationX)
                  ..rotateY(_rotationY),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: SizedBox(
                    width: 220,
                    height: 280,
                    child: _EditorialImage(
                      imageUrl: widget.item.imageUrls.isEmpty
                          ? null
                          : widget.item.imageUrls.first,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  'Drag to inspect the collectible in a 3D-style preview. Double-tap to reset.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _manualPaymentStatusLabel(ManualPaymentOrder order) {
  if (order.orderStatus == 'cancelled') {
    return 'cancelled';
  }
  if (order.orderStatus == 'fulfilled') {
    return 'completed';
  }
  if (order.orderStatus == 'failed' || order.paymentStatus == 'failed') {
    return 'payment_rejected';
  }
  if (order.orderStatus == 'paid') {
    return 'ready_to_ship';
  }
  if (order.paymentStatus == 'under_review') {
    return 'under_review';
  }
  return switch (order.reviewStatus) {
    'submitted' => 'payment_submitted',
    'approved' => 'approved',
    'resubmission_requested' => 'resubmission_needed',
    'rejected' => 'payment_rejected',
    _ => 'awaiting_payment',
  };
}

String? _manualPaymentActionLabel({
  required UniqueItem item,
  required CustomerController controller,
  required ManualPaymentOrder? paymentOrder,
}) {
  if (paymentOrder != null) {
    if (paymentOrder.canSubmitProof) {
      return paymentOrder.reviewStatus == 'resubmission_requested'
          ? 'Resubmit payment proof'
          : 'Continue payment';
    }
    return null;
  }
  if (item.askingPrice != null &&
      item.state == ItemState.listedForResale &&
      item.currentOwnerUserId != controller.currentUserId &&
      !item.state.isRestricted) {
    return 'Start payment';
  }
  return null;
}

String _manualPaymentStatusMessage(ManualPaymentOrder order) {
  if (order.orderStatus == 'cancelled') {
    return 'This order was cancelled after admin review.';
  }
  if (order.orderStatus == 'paid') {
    return 'Payment verified. The order is ready for the next fulfillment step.';
  }
  if (order.orderStatus == 'failed' || order.paymentStatus == 'failed') {
    return 'This payment was rejected after review. The order is closed.';
  }
  if (order.reviewStatus == 'resubmission_requested') {
    return 'Admin requested an updated screenshot or payment detail. Reopen the flow to resubmit.';
  }
  if (order.reviewStatus == 'rejected' || order.paymentStatus == 'rejected') {
    return 'This payment proof was rejected. Contact support or submit a new proof if allowed.';
  }
  if (order.paymentStatus == 'under_review' ||
      order.reviewStatus == 'submitted') {
    return 'Payment proof submitted. Admin review is in progress.';
  }
  return 'Your order reference is ready. Complete the transfer, then continue here to submit proof.';
}

String _contentTypeForProofFileName(String fileName) {
  final String lowerName = fileName.toLowerCase();
  if (lowerName.endsWith('.png')) {
    return 'image/png';
  }
  if (lowerName.endsWith('.webp')) {
    return 'image/webp';
  }
  if (lowerName.endsWith('.gif')) {
    return 'image/gif';
  }
  return 'image/jpeg';
}

String _notificationCategory(CollectorNotification notification) {
  final String haystack = '${notification.title} ${notification.body}'
      .toLowerCase();
  if (haystack.contains('payment') ||
      haystack.contains('proof') ||
      haystack.contains('review')) {
    return 'payment';
  }
  if (haystack.contains('ship') ||
      haystack.contains('delivery') ||
      haystack.contains('tracking')) {
    return 'shipping';
  }
  if (haystack.contains('claim') || haystack.contains('ownership')) {
    return 'claim';
  }
  if (haystack.contains('listing') ||
      haystack.contains('resale') ||
      haystack.contains('order')) {
    return 'resale';
  }
  return 'general';
}

String _formatCustomerTimestamp(DateTime timestamp) {
  final DateTime local = timestamp.toLocal();
  final String twoDigitMonth = local.month.toString().padLeft(2, '0');
  final String twoDigitDay = local.day.toString().padLeft(2, '0');
  final String twoDigitHour = local.hour.toString().padLeft(2, '0');
  final String twoDigitMinute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$twoDigitMonth-$twoDigitDay $twoDigitHour:$twoDigitMinute';
}

class _ActivityEntry {
  const _ActivityEntry({
    required this.id,
    required this.title,
    required this.detail,
    required this.occurredAt,
    required this.category,
    required this.status,
  });

  final String id;
  final String title;
  final String detail;
  final DateTime occurredAt;
  final String category;
  final String status;
}

class _NotificationCenterPanel extends StatelessWidget {
  const _NotificationCenterPanel({required this.controller});

  final CustomerController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 380,
      height: 520,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: OneOfOneTheme.gold.withValues(alpha: 0.25)),
      ),
      child: DefaultTabController(
        length: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Notifications',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                if (controller.unreadNotificationCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('${controller.unreadNotificationCount} unread'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const TabBar(
              tabs: <Widget>[
                Tab(text: 'Inbox'),
                Tab(text: 'Activity'),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(
                children: <Widget>[
                  controller.notificationFeed.isEmpty
                      ? const Center(child: Text('No notifications yet.'))
                      : ListView.separated(
                          itemCount: controller.notificationFeed.length,
                          separatorBuilder: (_, _) => Divider(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                          itemBuilder: (BuildContext context, int index) {
                            final CollectorNotification notification =
                                controller.notificationFeed[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              onTap: () async {
                                await controller.markNotificationRead(
                                  notification.id,
                                );
                                if (!context.mounted) {
                                  return;
                                }
                                await showModalBottomSheet<void>(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: const Color(0xFF14110D),
                                  builder: (BuildContext context) {
                                    return _NotificationDetailSheet(
                                      notification: notification.copyWithRead(),
                                      latestPaymentOrder:
                                          controller.activityLog.isEmpty
                                          ? null
                                          : controller.items
                                                .map(
                                                  (UniqueItem item) =>
                                                      controller
                                                          .manualPaymentFor(
                                                            item.id,
                                                          ),
                                                )
                                                .whereType<ManualPaymentOrder>()
                                                .fold<ManualPaymentOrder?>(
                                                  null,
                                                  (
                                                    ManualPaymentOrder? latest,
                                                    ManualPaymentOrder current,
                                                  ) {
                                                    if (latest == null) {
                                                      return current;
                                                    }
                                                    return current.createdAt
                                                            .isAfter(
                                                              latest.createdAt,
                                                            )
                                                        ? current
                                                        : latest;
                                                  },
                                                ),
                                    );
                                  },
                                );
                              },
                              leading: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: notification.read
                                      ? Colors.transparent
                                      : Colors.redAccent,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: notification.read
                                        ? Colors.white.withValues(alpha: 0.2)
                                        : Colors.redAccent,
                                  ),
                                ),
                              ),
                              title: Text(notification.title),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  const SizedBox(height: 4),
                                  Text(
                                    notification.body,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _formatCustomerTimestamp(
                                      notification.createdAt,
                                    ),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                  controller.activityLog.isEmpty
                      ? const Center(child: Text('No activity yet.'))
                      : ListView.separated(
                          itemCount: controller.activityLog.length,
                          separatorBuilder: (_, _) => Divider(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                          itemBuilder: (BuildContext context, int index) {
                            final _ActivityEntry entry =
                                controller.activityLog[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(entry.title),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  const SizedBox(height: 4),
                                  Text(
                                    entry.detail,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${entry.category} • ${_formatCustomerTimestamp(entry.occurredAt)}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                              trailing: Text(entry.status),
                            );
                          },
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension on CollectorNotification {
  CollectorNotification copyWithRead() {
    return CollectorNotification(
      id: id,
      title: title,
      body: body,
      createdAt: createdAt,
      read: true,
    );
  }
}

class _NotificationDetailSheet extends StatelessWidget {
  const _NotificationDetailSheet({
    required this.notification,
    required this.latestPaymentOrder,
  });

  final CollectorNotification notification;
  final ManualPaymentOrder? latestPaymentOrder;

  @override
  Widget build(BuildContext context) {
    final EdgeInsets bottomInset = EdgeInsets.only(
      bottom: MediaQuery.of(context).viewInsets.bottom,
    );
    final String category = _notificationCategory(notification);
    return SafeArea(
      child: Padding(
        padding: bottomInset,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      notification.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: OneOfOneTheme.gold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(category),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(_formatCustomerTimestamp(notification.createdAt)),
              const SizedBox(height: 16),
              Text(notification.body),
              if (latestPaymentOrder != null &&
                  (category == 'payment' || category == 'resale')) ...<Widget>[
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Current order context',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Order ref ${latestPaymentOrder!.paymentReference}',
                        ),
                        Text(
                          'Order status: ${latestPaymentOrder!.orderStatus}',
                        ),
                        Text(
                          'Payment status: ${latestPaymentOrder!.paymentStatus}',
                        ),
                        if (latestPaymentOrder!.reviewStatus != null)
                          Text(
                            'Review status: ${latestPaymentOrder!.reviewStatus}',
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentsSection extends StatefulWidget {
  const _CommentsSection({
    required this.controller,
    required this.item,
    required this.comments,
  });

  final CustomerController controller;
  final UniqueItem item;
  final List<ItemComment> comments;

  @override
  State<_CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<_CommentsSection> {
  final TextEditingController _commentController = TextEditingController();
  bool _isPosting = false;
  String? _composerMessage;
  bool _composerMessageIsError = false;

  bool get _canSubmit =>
      !_isPosting && _commentController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _isPosting = false;
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitComment() async {
    if (!_canSubmit) {
      return;
    }

    final String draft = _commentController.text.trim();
    setState(() {
      _isPosting = true;
      _composerMessage = null;
      _composerMessageIsError = false;
    });

    final MarketplaceActionResult<ItemComment> result = await widget.controller
        .addComment(itemId: widget.item.id, body: draft);

    if (!mounted) {
      return;
    }

    setState(() {
      _isPosting = false;
      _composerMessage = result.success
          ? 'Comment posted to the collector conversation.'
          : result.message;
      _composerMessageIsError = !result.success;
      if (result.success) {
        _commentController.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color feedbackColor = _composerMessageIsError
        ? theme.colorScheme.error
        : OneOfOneTheme.gold;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Collector conversation', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        TextField(
          controller: _commentController,
          minLines: 2,
          maxLines: 4,
          textInputAction: TextInputAction.newline,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Share your thoughts on this collectible',
            helperText: _isPosting
                ? 'Posting your comment to the verified collector conversation...'
                : 'Thoughtful collector notes help establish provenance and context.',
            suffixIcon: _isPosting
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
          enabled: !_isPosting,
        ),
        if (_composerMessage != null) ...<Widget>[
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Row(
              key: ValueKey<String>(
                '${_composerMessageIsError ? 'error' : 'success'}:${_composerMessage!}',
              ),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  _composerMessageIsError
                      ? Icons.error_outline_rounded
                      : Icons.check_circle_outline_rounded,
                  size: 18,
                  color: feedbackColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _composerMessage!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: feedbackColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _canSubmit ? _submitComment : null,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _isPosting
                  ? const Row(
                      key: ValueKey<String>('posting'),
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text('Posting...'),
                      ],
                    )
                  : const Text('Post comment', key: ValueKey<String>('idle')),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (widget.comments.isEmpty)
          const Card(
            child: ListTile(
              title: Text('No comments yet.'),
              subtitle: Text('Start the conversation around this release.'),
            ),
          ),
        ...widget.comments.map(
          (ItemComment comment) => Card(
            child: ListTile(
              title: Text(comment.userDisplayName),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(comment.body),
              ),
              trailing: Text(
                comment.createdAt.toIso8601String().split('T').first,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ScanScreen extends StatefulWidget {
  const ScanScreen({
    required this.controller,
    required this.enableCameraScanner,
    super.key,
  });

  final CustomerController controller;
  final bool enableCameraScanner;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final TextEditingController _qrTokenController = TextEditingController();
  final TextEditingController _claimCodeController = TextEditingController();
  final MobileScannerController _cameraController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handlingScan = false;
  String? _lastScanPayload;

  @override
  void dispose() {
    _cameraController.dispose();
    _qrTokenController.dispose();
    _claimCodeController.dispose();
    super.dispose();
  }

  Future<void> _verifyManualInput() async {
    await widget.controller.resolveAuthenticityInput(
      rawInput: _qrTokenController.text,
      openPublicRoute: true,
      switchToScanTab: true,
    );
  }

  Future<void> _handleBarcodeCapture(BarcodeCapture capture) async {
    if (_handlingScan) {
      return;
    }

    String? rawValue;
    for (final Barcode barcode in capture.barcodes) {
      final String? candidate = barcode.rawValue?.trim();
      if (candidate != null && candidate.isNotEmpty) {
        rawValue = candidate;
        break;
      }
    }
    if (rawValue == null || rawValue.isEmpty || rawValue == _lastScanPayload) {
      return;
    }

    _handlingScan = true;
    _lastScanPayload = rawValue;
    await widget.controller.resolveAuthenticityInput(
      rawInput: rawValue,
      openPublicRoute: true,
      switchToScanTab: true,
    );
    _handlingScan = false;
  }

  @override
  Widget build(BuildContext context) {
    final PublicAuthenticityRecord? result =
        widget.controller.scannedAuthenticity;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: <Widget>[
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'AUTHENTICITY',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: OneOfOneTheme.gold,
                    letterSpacing: 2.2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Scan authenticity QR',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: const Color(0xFFF4EEDF),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Resolve a public verification token, inspect ownership-safe authenticity details, and continue only with packaged private claim material.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFFBCB3A6),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: const <Widget>[
                    _HeroMetaChip(label: 'Verified route'),
                    _HeroMetaChip(label: 'Claim code stays private'),
                  ],
                ),
                const SizedBox(height: 18),
                if (widget.enableCameraScanner && !kIsWeb) ...<Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          MobileScanner(
                            controller: _cameraController,
                            onDetect: _handleBarcodeCapture,
                          ),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: <Color>[
                                  Colors.black.withValues(alpha: 0.1),
                                  Colors.black.withValues(alpha: 0.2),
                                  Colors.black.withValues(alpha: 0.55),
                                ],
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.center,
                            child: Container(
                              width: 188,
                              height: 188,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(
                                  color: OneOfOneTheme.gold.withValues(
                                    alpha: 0.7,
                                  ),
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              margin: const EdgeInsets.all(16),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.62),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.08),
                                ),
                              ),
                              child: Text(
                                'Point the camera at a One of One authenticity QR to open the public authenticity record.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: const Color(0xFFE8DECD),
                                      height: 1.4,
                                    ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                _LuxuryTextField(
                  child: TextField(
                    controller: _qrTokenController,
                    decoration: const InputDecoration(
                      labelText: 'QR token',
                      helperText:
                          'Accepts the token encoded in the QR or a public deep-link query value.',
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _verifyManualInput,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE0C88A),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Text('Verify authenticity'),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.controller.statusMessage != null) ...<Widget>[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF151515),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.verified_outlined, color: OneOfOneTheme.gold),
                const SizedBox(width: 12),
                Expanded(child: Text(widget.controller.statusMessage!)),
              ],
            ),
          ),
        ],
        if (widget.controller.errorMessage != null) ...<Widget>[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF151515),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(widget.controller.errorMessage!)),
              ],
            ),
          ),
        ],
        if (result != null) ...<Widget>[
          const SizedBox(height: 18),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF151515),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Authenticity verified',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: OneOfOneTheme.gold,
                      letterSpacing: 1.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    result.serialNumber,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: const Color(0xFFF4EEDF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    result.artworkTitle,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: const Color(0xFFF1EADB),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    result.artistName,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFFD7C79B),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      _LuxuryInfoChip(
                        label: result.state.key.replaceAll('_', ' '),
                      ),
                      _LuxuryInfoChip(label: result.ownershipVisibility),
                      _LuxuryInfoChip(
                        label:
                            '${result.verifiedTransferCount} verified transfer(s)',
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Private claim continuation',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: const Color(0xFFF3ECDE),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Enter hidden claim code',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: const Color(0xFFD9CFBA)),
                        ),
                        const SizedBox(height: 10),
                        _LuxuryTextField(
                          child: TextField(
                            controller: _claimCodeController,
                            decoration: const InputDecoration(
                              labelText: 'Enter hidden claim code',
                              helperText:
                                  'This is packaged separately and never appears in the public authenticity result.',
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () async {
                              final String message = await widget.controller
                                  .claimScannedItem(
                                    claimCode: _claimCodeController.text,
                                  );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(message)),
                                );
                              }
                              _claimCodeController.clear();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE0C88A),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Text('Claim ownership'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class PublicAuthenticityScaffold extends StatelessWidget {
  const PublicAuthenticityScaffold({required this.controller, super.key});

  final CustomerController controller;

  @override
  Widget build(BuildContext context) {
    final PublicAuthenticityRecord record = controller.publicAuthenticityRoute!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Authenticity verified'),
        leading: IconButton(
          onPressed: controller.clearPublicAuthenticityRoute,
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    record.serialNumber,
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(record.artworkTitle),
                  Text(record.artistName),
                  const SizedBox(height: 12),
                  Text('Authenticity: ${record.authenticityStatus}'),
                  Text(
                    'Marketplace status: ${record.state.key.replaceAll('_', ' ')}',
                  ),
                  const SizedBox(height: 12),
                  Text(record.publicStory),
                  const SizedBox(height: 12),
                  Text('Garment: ${record.garmentName}'),
                  Text('Ownership visibility: ${record.ownershipVisibility}'),
                  Text(
                    'Verified resale history: ${record.verifiedTransferCount} transfer(s).',
                  ),
                  const SizedBox(height: 16),
                  Card(
                    color: const Color(0xFF151515),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text('Claim remains private'),
                          const SizedBox(height: 8),
                          Text(
                            controller.isAuthenticated
                                ? 'Use the packaged hidden claim code from the Scan tab to request ownership. That code never appears in the public authenticity result.'
                                : 'The public authenticity route verifies the collectible only. Hidden claim codes stay packaged separately and require a signed-in collector flow.',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: controller.continueFromPublicAuthenticity,
                      child: Text(
                        controller.isAuthenticated
                            ? 'Continue to scan and claim'
                            : 'Back to collector sign in',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class VaultScreen extends StatelessWidget {
  const VaultScreen({required this.controller, super.key});

  final CustomerController controller;

  @override
  Widget build(BuildContext context) {
    final List<UniqueItem> ownedItems = controller.vaultItems;
    final List<UniqueItem> savedItems = controller.savedItems;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'My vault',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: const Color(0xFFF4EEDF),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'A private archive of verified ownership, saved watchlist pieces, and collector resale readiness.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFB9B1A5),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  _VaultSummaryChip(
                    label: 'Owned pieces',
                    value: '${ownedItems.length}',
                  ),
                  _VaultSummaryChip(
                    label: 'Saved items',
                    value: '${savedItems.length}',
                  ),
                  _VaultSummaryChip(
                    label: 'Ready for resale',
                    value:
                        '${ownedItems.where((UniqueItem item) => !item.state.isRestricted).length}',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const _SectionHeader(
          eyebrow: 'Owned archive',
          title: 'Claimed collectibles',
          caption:
              'Your verified pieces, certificates, and resale readiness in one private view.',
        ),
        const SizedBox(height: 16),
        if (ownedItems.isEmpty)
          const _EmptyLuxuryCard(
            title: 'No claimed collectibles yet',
            body:
                'Claim with the hidden packaged code after scanning a verified item.',
          ),
        ...ownedItems.map(
          (UniqueItem item) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _OwnedVaultCard(controller: controller, item: item),
          ),
        ),
        const SizedBox(height: 20),
        const _SectionHeader(
          eyebrow: 'Saved for watchlist',
          title: 'Saved items',
          caption:
              'Quietly track future resale movement and return when the right piece opens.',
        ),
        const SizedBox(height: 16),
        if (savedItems.isEmpty)
          const _EmptyLuxuryCard(
            title: 'No saved items yet',
            body:
                'Bookmark collectible pieces in the shop to keep a refined watchlist here.',
          ),
        ...savedItems.map(
          (UniqueItem item) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _SavedVaultCard(controller: controller, item: item),
          ),
        ),
      ],
    );
  }
}

class _VaultSummaryChip extends StatelessWidget {
  const _VaultSummaryChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xFFF0E5CB),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFFB7AE9F)),
          ),
        ],
      ),
    );
  }
}

class _OwnedVaultCard extends StatelessWidget {
  const _OwnedVaultCard({required this.controller, required this.item});

  final CustomerController controller;
  final UniqueItem item;

  @override
  Widget build(BuildContext context) {
    final Artist? artist = controller.artistFor(item);
    final bool canManageResale =
        item.currentOwnerUserId == controller.currentUserId &&
        !item.state.isRestricted;
    return InkWell(
      borderRadius: BorderRadius.circular(30),
      onTap: () => _openItemDetail(context, controller, item.id),
      child: Ink(
        decoration: BoxDecoration(
          color: const Color(0xFF151515),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: OneOfOneTheme.gold.withValues(alpha: 0.14)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.24),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AspectRatio(
              aspectRatio: 1.22,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(30),
                    ),
                    child: _EditorialImage(
                      imageUrl: item.imageUrls.isEmpty
                          ? null
                          : item.imageUrls.first,
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(30),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Colors.black.withValues(alpha: 0.04),
                          Colors.black.withValues(alpha: 0.16),
                          Colors.black.withValues(alpha: 0.58),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 14,
                    left: 14,
                    child: _HeroMetaChip(label: _vaultStateLabel(item)),
                  ),
                  Positioned(
                    left: 18,
                    right: 18,
                    bottom: 18,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (artist != null)
                          Text(
                            artist.displayName.toUpperCase(),
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: const Color(0xFFE4D29F),
                                  letterSpacing: 1.1,
                                ),
                          ),
                        if (artist != null) const SizedBox(height: 8),
                        Text(
                          item.productName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: const Color(0xFFF5F0E6),
                                fontWeight: FontWeight.w600,
                                height: 1.08,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      _LuxuryInfoChip(label: item.serialNumber),
                      const _LuxuryInfoChip(label: 'Certificate active'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Private ownership is recorded server-side and prepared for verified transfer only.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFFBEB6AB),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () =>
                              _openItemDetail(context, controller, item.id),
                          child: const Text('Open piece'),
                        ),
                      ),
                      if (canManageResale) ...<Widget>[
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: () =>
                                _openItemDetail(context, controller, item.id),
                            child: const Text('Manage resale'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedVaultCard extends StatelessWidget {
  const _SavedVaultCard({required this.controller, required this.item});

  final CustomerController controller;
  final UniqueItem item;

  @override
  Widget build(BuildContext context) {
    final Artist? artist = controller.artistFor(item);
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => _openItemDetail(context, controller, item.id),
      child: Ink(
        decoration: BoxDecoration(
          color: const Color(0xFF131313),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Container(
                width: 58,
                height: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.white.withValues(alpha: 0.04),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _EditorialImage(
                    imageUrl: item.imageUrls.isEmpty
                        ? null
                        : item.imageUrls.first,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.productName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFFF2ECDC),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      artist?.displayName ?? 'Collector selection',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFBAAF9D),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Saved for watchlist · ${item.serialNumber}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF9C9385),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    Icons.bookmark,
                    color: OneOfOneTheme.gold.withValues(alpha: 0.95),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'View collectible',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: const Color(0xFFD7CDBA),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _vaultStateLabel(UniqueItem item) {
  if (item.state == ItemState.claimed) {
    return 'Collector held';
  }
  if (item.state == ItemState.transferred) {
    return 'Transferred';
  }
  if (item.state == ItemState.listedForResale) {
    return 'Listed for resale';
  }
  return item.state.key.replaceAll('_', ' ');
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({required this.controller, super.key});

  final CustomerController controller;

  @override
  Widget build(BuildContext context) {
    final String displayName = controller.currentDisplayName ?? 'Collector';
    final String secondaryIdentity =
        controller.currentUserEmail ?? controller.currentUserId;
    final String initials = displayName
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .take(2)
        .map((String part) => part.characters.first.toUpperCase())
        .join();
    final int listedCount = controller.vaultItems
        .where((UniqueItem item) => item.state == ItemState.listedForResale)
        .length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: <Color>[
                              OneOfOneTheme.gold.withValues(alpha: 0.92),
                              const Color(0xFF8C7343),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(26),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          initials.isEmpty ? 'C' : initials,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: Colors.black,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1B1B1B),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Icon(
                            Icons.photo_camera_outlined,
                            size: 16,
                            color: OneOfOneTheme.gold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          displayName,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: const Color(0xFFF5F0E6),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          secondaryIdentity,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: const Color(0xFFBBB2A6)),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Collector identity active · private member archive',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFF9E9588)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _showComingSoon(
                        context,
                        'Profile editing will land in a future collector update.',
                      ),
                      child: const Text('Edit profile'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () => _showComingSoon(
                        context,
                        'Avatar and collector identity settings are preparing for release.',
                      ),
                      child: const Text('Identity settings'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  _VaultSummaryChip(
                    label: 'Owned pieces',
                    value: '${controller.vaultItems.length}',
                  ),
                  _VaultSummaryChip(
                    label: 'Saved items',
                    value: '${controller.savedItemIds.length}',
                  ),
                  _VaultSummaryChip(label: 'Listed', value: '$listedCount'),
                  _VaultSummaryChip(
                    label: 'Unread updates',
                    value: '${controller.unreadNotificationCount}',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const _SectionHeader(
          eyebrow: 'Account & preferences',
          title: 'Identity and settings',
          caption:
              'Future-ready account controls for profile, security, and collector preferences.',
        ),
        const SizedBox(height: 16),
        _ProfileGroupCard(
          children: <Widget>[
            _ProfileMenuRow(
              icon: Icons.manage_accounts_outlined,
              title: 'Account settings',
              subtitle:
                  'Manage profile details, collector handle, and member identity.',
              onTap: () => _showComingSoon(
                context,
                'Account settings are being prepared for a future collector release.',
              ),
            ),
            _ProfileMenuRow(
              icon: Icons.notifications_none_rounded,
              title: 'Notification preferences',
              subtitle: 'Unread updates: ${controller.unreadNotificationCount}',
              trailingText: controller.unreadNotificationCount > 0
                  ? '${controller.unreadNotificationCount}'
                  : null,
              onTap: controller.toggleInbox,
            ),
            _ProfileMenuRow(
              icon: Icons.shield_outlined,
              title: 'Security',
              subtitle:
                  'Session, sign-in, and future account protection controls.',
              onTap: () => _showComingSoon(
                context,
                'Security settings are planned for a future collector update.',
              ),
            ),
            _ProfileMenuRow(
              icon: Icons.lock_outline_rounded,
              title: 'Privacy settings',
              subtitle:
                  'Control how collector identity and ownership visibility evolve.',
              onTap: () => _showComingSoon(
                context,
                'Privacy preferences will arrive with expanded collector controls.',
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        const _SectionHeader(
          eyebrow: 'Collector activity',
          title: 'History and movement',
          caption:
              'Keep personal shortcuts to transactions, saved watchlist pieces, disputes, and activity.',
        ),
        const SizedBox(height: 16),
        _ProfileGroupCard(
          children: <Widget>[
            _ProfileMenuRow(
              icon: Icons.receipt_long_outlined,
              title: 'Transaction history',
              subtitle:
                  'Primary purchase, delivery-gated resale activity, and royalty-aware transfers.',
              onTap: () => _showComingSoon(
                context,
                'Transaction history will expand into a dedicated collector ledger.',
              ),
            ),
            _ProfileMenuRow(
              icon: Icons.bookmark_border_rounded,
              title: 'Saved items',
              subtitle:
                  '${controller.savedItemIds.length} collectible(s) tracked for watchlist movement.',
              trailingText: controller.savedItemIds.isEmpty
                  ? null
                  : '${controller.savedItemIds.length}',
              onTap: () => controller.setIndex(3),
            ),
            _ProfileMenuRow(
              icon: Icons.history_rounded,
              title: 'Activity log',
              subtitle:
                  '${controller.activityLog.length} collector activity entry/entries recorded.',
              onTap: controller.toggleInbox,
            ),
            _ProfileMenuRow(
              icon: Icons.gavel_outlined,
              title: 'Disputes',
              subtitle:
                  'Lost, stolen, and reporting follow-up for protected ownership.',
              onTap: () => _showComingSoon(
                context,
                'Dedicated dispute tracking shortcuts are being prepared.',
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        const _SectionHeader(
          eyebrow: 'Support & session',
          title: 'Help and access',
          caption:
              'Get assistance, review support paths, or close the current collector session.',
        ),
        const SizedBox(height: 16),
        _ProfileGroupCard(
          children: <Widget>[
            _ProfileMenuRow(
              icon: Icons.help_outline_rounded,
              title: 'Help & support',
              subtitle:
                  'Contact support for claims, resale questions, or account help.',
              onTap: () => _showComingSoon(
                context,
                'Support shortcuts will connect into a future collector help flow.',
              ),
            ),
            _ProfileMenuRow(
              icon: Icons.logout_rounded,
              title: 'Sign out',
              subtitle: 'End this collector session on the current device.',
              onTap: () async {
                await controller.signOut();
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _ProfileGroupCard extends StatelessWidget {
  const _ProfileGroupCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: children
            .expand(
              (Widget child) => <Widget>[
                child,
                if (child != children.last)
                  Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.06),
                    indent: 18,
                    endIndent: 18,
                  ),
              ],
            )
            .toList(growable: false),
      ),
    );
  }
}

class _ProfileMenuRow extends StatelessWidget {
  const _ProfileMenuRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailingText,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? trailingText;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(26),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: OneOfOneTheme.gold, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: const Color(0xFFF3ECDE),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFB8AF9F),
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (trailingText != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  trailingText!,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: const Color(0xFFE5D6AF),
                  ),
                ),
              ),
            const SizedBox(width: 10),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: Color(0xFF908779),
            ),
          ],
        ),
      ),
    );
  }
}

void _showComingSoon(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
