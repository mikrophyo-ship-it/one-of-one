import 'dart:async';

import 'package:core_ui/core_ui.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:services/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:utils/utils.dart';

class OneOfOneCustomerApp extends StatelessWidget {
  const OneOfOneCustomerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'One of One',
      debugShowCheckedModeBanner: false,
      theme: OneOfOneTheme.customerTheme(),
      home: const CustomerRoot(),
    );
  }
}

class CustomerRoot extends StatefulWidget {
  const CustomerRoot({super.key});

  @override
  State<CustomerRoot> createState() => _CustomerRootState();
}

class _CustomerRootState extends State<CustomerRoot> {
  late final MarketplaceRepository repository;
  late final MarketplaceWorkflowService workflowService;
  late final SupabaseAuthService authService;
  late final CustomerController controller;

  @override
  void initState() {
    super.initState();
    const String url = String.fromEnvironment('SUPABASE_URL');
    const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
    final String? configurationError = url.isEmpty || anonKey.isEmpty
        ? 'Supabase is not configured. Pass SUPABASE_URL and SUPABASE_ANON_KEY via dart-define.'
        : null;

    if (configurationError == null) {
      repository = SupabaseMarketplaceRepository(
        client: Supabase.instance.client,
      );
      authService = SupabaseAuthService(client: Supabase.instance.client);
    } else {
      repository = SupabaseMarketplaceRepository(
        configurationError: configurationError,
      );
      authService = SupabaseAuthService(configurationError: configurationError);
    }

    workflowService = MarketplaceWorkflowService(
      repository: repository,
      paymentProvider: const StripePaymentProvider(),
    );
    controller = CustomerController(
      repository: repository,
      workflowService: workflowService,
      authService: authService,
    );
    unawaited(controller.initialize());
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, _) {
        if (controller.isInitializing) {
          return const _StartupScreen();
        }
        if (!controller.isAuthenticated) {
          return AuthScreen(controller: controller);
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('ONE OF ONE'),
            actions: <Widget>[
              IconButton(
                onPressed: controller.toggleInbox,
                icon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.notifications_none),
                    const SizedBox(width: 6),
                    Text('${controller.notifications.length}'),
                  ],
                ),
              ),
            ],
          ),
          body: Stack(
            children: <Widget>[
              IndexedStack(
                index: controller.index,
                children: <Widget>[
                  HomeScreen(controller: controller),
                  ExploreScreen(controller: controller),
                  ScanScreen(controller: controller),
                  VaultScreen(controller: controller),
                  ProfileScreen(controller: controller),
                ],
              ),
              if (controller.showInbox)
                Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    width: 320,
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF151515),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: OneOfOneTheme.gold.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: controller.notifications.isEmpty
                          ? <Widget>[const Text('No new notifications.')]
                          : controller.notifications
                                .map(
                                  (String note) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Text(note),
                                  ),
                                )
                                .toList(),
                    ),
                  ),
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
          bottomNavigationBar: NavigationBar(
            selectedIndex: controller.index,
            onDestinationSelected: controller.setIndex,
            destinations: const <Widget>[
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.auto_awesome_mosaic_outlined),
                label: 'Shop',
              ),
              NavigationDestination(
                icon: Icon(Icons.qr_code_scanner_outlined),
                label: 'Scan',
              ),
              NavigationDestination(
                icon: Icon(Icons.inventory_2_outlined),
                label: 'Vault',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                label: 'Profile',
              ),
            ],
          ),
        );
      },
    );
  }
}

class CustomerController extends ChangeNotifier {
  CustomerController({
    required MarketplaceRepository repository,
    required MarketplaceWorkflowService workflowService,
    required SupabaseAuthService authService,
  }) : _repository = repository,
       _workflowService = workflowService,
       _authService = authService;

  final MarketplaceRepository _repository;
  final MarketplaceWorkflowService _workflowService;
  final SupabaseAuthService _authService;

  StreamSubscription<AuthState>? _authSubscription;

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
  PublicAuthenticityRecord? scannedAuthenticity;
  List<CollectorNotification> notificationFeed = const <CollectorNotification>[];
  Set<String> savedItemIds = <String>{};

  bool get authConfigured => _authService.isConfigured;

  List<Artist> get artists => _repository.featuredArtists();
  List<Artwork> get artworks => _repository.artworks();
  List<UniqueItem> get items => _repository.items();
  List<Listing> get listings => _repository.activeListings();
  List<String> get notifications => notificationFeed
      .map((CollectorNotification item) => '${item.title}: ${item.body}')
      .toList(growable: false);
  List<UniqueItem> get vaultItems => items
      .where((UniqueItem item) => item.currentOwnerUserId == currentUserId)
      .toList();
  List<UniqueItem> get savedItems => items
      .where((UniqueItem item) => savedItemIds.contains(item.id))
      .toList();

  Future<void> initialize() async {
    _authSubscription ??= _authService.authStateChanges().listen((AuthState _) {
      unawaited(_syncSessionState());
    });
    await _syncSessionState(
      restoredMessage: _authService.currentSession == null
          ? null
          : 'Collector session restored from Supabase.',
    );
    unawaited(handleInitialAuthenticityLink());
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
    final String? qrToken = Uri.base.queryParameters['qr'];
    if (qrToken == null || qrToken.trim().isEmpty) {
      return;
    }
    await lookupPublicAuthenticity(qrToken: qrToken);
    index = 2;
    notifyListeners();
  }

  void setIndex(int value) {
    index = value;
    notifyListeners();
  }

  void toggleInbox() {
    showInbox = !showInbox;
    notifyListeners();
  }

  Future<PublicAuthenticityRecord?> lookupPublicAuthenticity({
    required String qrToken,
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
      statusMessage = 'Authenticity verified for ${result.data!.serialNumber}.';
      notifyListeners();
      return result.data;
    }

    scannedAuthenticity = null;
    errorMessage = result.message;
    notifyListeners();
    return null;
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

    return _runAction<UniqueItem>(
      operation: () => _workflowService.buyResaleItem(
        itemId: itemId,
        buyerUserId: currentUserId,
      ),
      onSuccess: (UniqueItem? item, String message) {
        if (item != null) {
          _prependLocalNotification(
            title: 'Checkout started',
            body:
                '${item.serialNumber} payment is authorized. Ownership transfers only after delivery review.',
          );
        }
        return message;
      },
    );
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

  Future<void> _refreshCompanionData() async {
    final MarketplaceActionResult<List<CollectorNotification>> notifications =
        await _workflowService.fetchNotifications();
    if (notifications.success && notifications.data != null) {
      notificationFeed = notifications.data!;
    }

    final MarketplaceActionResult<List<SavedCollectible>> saved =
        await _workflowService.fetchSavedItems();
    if (saved.success && saved.data != null) {
      savedItemIds = saved.data!
          .map((SavedCollectible item) => item.itemId)
          .toSet();
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
    super.dispose();
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              Color(0xFF060606),
              Color(0xFF191109),
              Color(0xFF060606),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Collect the original.',
                            style: Theme.of(context).textTheme.displaySmall,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _headlineCopy(),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: <Widget>[
                              _modeButton(context, AuthMode.signIn, 'Sign in'),
                              _modeButton(
                                context,
                                AuthMode.signUp,
                                'Create account',
                              ),
                              _modeButton(
                                context,
                                AuthMode.resetPassword,
                                'Reset password',
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
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
                              icon: Icons.settings_ethernet,
                              message:
                                  'Supabase configuration is required for real collector authentication.',
                            ),
                          if (_mode == AuthMode.signUp) ...<Widget>[
                            TextFormField(
                              controller: _displayNameController,
                              decoration: const InputDecoration(
                                labelText: 'Display name',
                              ),
                              textInputAction: TextInputAction.next,
                              validator: (String? value) => validateRequired(
                                value ?? '',
                                field: 'Display name',
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _usernameController,
                              decoration: const InputDecoration(
                                labelText: 'Username',
                              ),
                              textInputAction: TextInputAction.next,
                              validator: (String? value) =>
                                  validateUsername(value ?? ''),
                            ),
                            const SizedBox(height: 12),
                          ],
                          TextFormField(
                            controller: _emailController,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                            ),
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: _mode == AuthMode.resetPassword
                                ? TextInputAction.done
                                : TextInputAction.next,
                            validator: (String? value) =>
                                validateEmail(value ?? ''),
                          ),
                          if (_mode != AuthMode.resetPassword) ...<Widget>[
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _passwordController,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                suffixIcon: IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
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
                          ],
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed:
                                  isBusy || !widget.controller.authConfigured
                                  ? null
                                  : _submit,
                              child: Text(_primaryActionLabel()),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _footnoteCopy(),
                            style: Theme.of(context).textTheme.bodySmall,
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
      ),
    );
  }

  Widget _modeButton(BuildContext context, AuthMode mode, String label) {
    final bool selected = _mode == mode;
    return OutlinedButton(
      onPressed: () {
        setState(() {
          _mode = mode;
        });
      },
      style: OutlinedButton.styleFrom(
        backgroundColor: selected
            ? OneOfOneTheme.gold.withValues(alpha: 0.12)
            : Colors.transparent,
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelLarge),
    );
  }

  String _headlineCopy() {
    switch (_mode) {
      case AuthMode.signIn:
        return 'Sign in to claim ownership, access your vault, and resell authenticated pieces on-platform only.';
      case AuthMode.signUp:
        return 'Create your collector account to bind provenance, ownership certificates, and future resale activity to you.';
      case AuthMode.resetPassword:
        return 'Reset your password to regain access to your verified collection and dispute tools.';
    }
  }

  String _primaryActionLabel() {
    switch (_mode) {
      case AuthMode.signIn:
        return 'Sign In';
      case AuthMode.signUp:
        return 'Create Collector Account';
      case AuthMode.resetPassword:
        return 'Send Reset Email';
    }
  }

  String _footnoteCopy() {
    switch (_mode) {
      case AuthMode.signIn:
        return 'Ownership actions stay server-authoritative and are validated by Supabase before any collectible state changes.';
      case AuthMode.signUp:
        return 'Profile bootstrap runs after account creation so claim, listing, checkout, and dispute RPCs have a verified collector identity.';
      case AuthMode.resetPassword:
        return 'Production deployments may set a dedicated password-reset redirect URL for mobile deep links.';
    }
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
              title: Text(artist.displayName),
              subtitle: Text(artist.authenticityStatement),
              trailing: Text('${artist.royaltyBps / 100}% royalty'),
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
        ...controller.listings.map(
          (Listing listing) => Card(
            child: ListTile(
              title: Text(
                'Verified resale ${formatCurrency(listing.askingPrice)}',
              ),
              subtitle: Text(
                'Listing ${listing.id} for item ${listing.itemId}',
              ),
              trailing: const Text('Private seller'),
            ),
          ),
        ),
      ],
    );
  }
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
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ItemDetailScreen(controller: controller, itemId: item.id),
                ),
              );
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
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        const TextField(
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Filter by artist, price, availability',
          ),
        ),
        const SizedBox(height: 16),
        if (controller.items.isEmpty)
          const Card(
            child: ListTile(
              title: Text('No collectibles available yet.'),
              subtitle: Text(
                'Seed the catalog in Supabase to populate the marketplace.',
              ),
            ),
          ),
        ...controller.items.map(
          (UniqueItem item) => Card(
            child: ListTile(
              title: Text(item.productName),
              subtitle: Text(
                '${item.serialNumber} - ${item.state.key.replaceAll('_', ' ')}',
              ),
              trailing: Text(
                item.askingPrice == null
                    ? 'Held'
                    : formatCurrency(item.askingPrice!),
              ),
              leading: IconButton(
                onPressed: () => controller.toggleSavedItem(item.id),
                icon: Icon(
                  controller.savedItemIds.contains(item.id)
                      ? Icons.bookmark
                      : Icons.bookmark_border,
                ),
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ItemDetailScreen(
                      controller: controller,
                      itemId: item.id,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
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
    final UniqueItem? item = controller.itemById(itemId);
    if (item == null) {
      return const Scaffold(
        body: Center(child: Text('Collectible not found.')),
      );
    }

    final Artwork? artwork = controller.artworkFor(item);
    final Artist? artist = controller.artistFor(item);
    final FeeBreakdown breakdown = controller.breakdownFor(item);
    final List<OwnershipRecord> history = controller.historyFor(item.id);
    return Scaffold(
      appBar: AppBar(title: Text(item.productName)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Container(
            height: 240,
            decoration: BoxDecoration(
              color: const Color(0xFF191919),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: OneOfOneTheme.gold.withValues(alpha: 0.3)),
            ),
            child: const Center(
              child: Text('Editorial garment image / human-made proof media'),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            artwork?.title ?? item.productName,
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 8),
          Text('Artist: ${artist?.displayName ?? 'Unknown artist'}'),
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
            const ListTile(title: Text('No verified ownership records yet.')),
          ...history.map(
            (OwnershipRecord record) => ListTile(
              title: Text(record.ownerUserId),
              subtitle: Text(
                'Acquired ${record.acquiredAt.toIso8601String().split('T').first}',
              ),
            ),
          ),
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
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              if (item.askingPrice != null && !item.state.isRestricted)
                ElevatedButton(
                  onPressed: () async {
                    final String message = await controller.buyResale(
                      itemId: item.id,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(message)));
                    }
                  },
                  child: const Text('Authorize checkout'),
                ),
              if (item.currentOwnerUserId == controller.currentUserId &&
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
      ),
    );
  }
}

class ScanScreen extends StatefulWidget {
  const ScanScreen({required this.controller, super.key});

  final CustomerController controller;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final TextEditingController _qrTokenController = TextEditingController();
  final TextEditingController _claimCodeController = TextEditingController();

  @override
  void dispose() {
    _qrTokenController.dispose();
    _claimCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final PublicAuthenticityRecord? result =
        widget.controller.scannedAuthenticity;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Scan authenticity QR',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Use the camera-ready public token or paste a deep-link token to resolve privacy-safe authenticity details from Supabase. Hidden claim codes stay separate from the public authenticity route.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _qrTokenController,
                  decoration: const InputDecoration(
                    labelText: 'QR token',
                    helperText:
                        'Accepts the token encoded in the QR or a public deep-link query value.',
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final PublicAuthenticityRecord? record = await widget
                          .controller
                          .lookupPublicAuthenticity(
                            qrToken: _qrTokenController.text,
                          );
                      if (!context.mounted || record == null) {
                        return;
                      }
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              PublicAuthenticityPage(record: record),
                        ),
                      );
                    },
                    child: const Text('Verify authenticity'),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.controller.statusMessage != null) ...<Widget>[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.verified_outlined),
              title: Text(widget.controller.statusMessage!),
            ),
          ),
        ],
        if (widget.controller.errorMessage != null) ...<Widget>[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.error_outline),
              title: Text(widget.controller.errorMessage!),
            ),
          ),
        ],
        if (result != null) ...<Widget>[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    result.serialNumber,
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(result.artworkTitle),
                  Text(result.artistName),
                  Text(
                    'Marketplace status: ${result.state.key.replaceAll('_', ' ')}',
                  ),
                  const SizedBox(height: 8),
                  Text(result.ownershipVisibility),
                  Text('${result.verifiedTransferCount} verified transfer(s)'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _claimCodeController,
                    decoration: const InputDecoration(
                      labelText: 'Enter hidden claim code',
                      helperText:
                          'This is packaged separately and never appears in the public authenticity result.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final String message = await widget.controller
                            .claimScannedItem(
                              claimCode: _claimCodeController.text,
                            );
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text(message)));
                        }
                        _claimCodeController.clear();
                      },
                      child: const Text('Claim ownership'),
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

class PublicAuthenticityPage extends StatelessWidget {
  const PublicAuthenticityPage({required this.record, super.key});

  final PublicAuthenticityRecord record;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Authenticity verified')),
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
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text('My collection', style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 12),
        if (controller.savedItems.isNotEmpty) ...<Widget>[
          const Card(
            child: ListTile(
              title: Text('Saved items'),
              subtitle: Text(
                'Watchlisted collectibles for future resale drops and alerts.',
              ),
            ),
          ),
          ...controller.savedItems.map(
            (UniqueItem item) => Card(
              child: ListTile(
                title: Text(item.productName),
                subtitle: Text(item.serialNumber),
                trailing: const Icon(Icons.bookmark),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (controller.vaultItems.isEmpty)
          const Card(
            child: ListTile(
              title: Text('No claimed collectibles yet.'),
              subtitle: Text(
                'Claim with the hidden packaged code after scanning a verified item.',
              ),
            ),
          ),
        ...controller.vaultItems.map(
          (UniqueItem item) => Card(
            child: ListTile(
              title: Text(item.productName),
              subtitle: Text(
                'Certificate active - ${item.state.key.replaceAll('_', ' ')}',
              ),
              trailing: Text(item.serialNumber),
            ),
          ),
        ),
      ],
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({required this.controller, super.key});

  final CustomerController controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text(
          'Collector profile',
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            title: Text(controller.currentDisplayName ?? 'Collector'),
            subtitle: Text(
              controller.currentUserEmail ?? controller.currentUserId,
            ),
            trailing: TextButton(
              onPressed: () async {
                await controller.signOut();
              },
              child: const Text('Sign out'),
            ),
          ),
        ),
        const Card(
          child: ListTile(
            title: Text('Transaction history'),
            subtitle: Text(
              'Primary purchase, delivery-gated resale activity, royalty-aware transfers',
            ),
          ),
        ),
        Card(
          child: ListTile(
            title: const Text('Saved items'),
            subtitle: Text('${controller.savedItemIds.length} collectible(s) tracked'),
          ),
        ),
        Card(
          child: ListTile(
            title: const Text('Notifications'),
            subtitle: Text('${controller.notifications.length} update(s) ready'),
          ),
        ),
        const Card(
          child: ListTile(
            title: Text('Disputes'),
            subtitle: Text('Lost/stolen reporting and review queue tracking'),
          ),
        ),
      ],
    );
  }
}
