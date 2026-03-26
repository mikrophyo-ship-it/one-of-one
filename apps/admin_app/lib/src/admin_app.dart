import 'dart:async';

import 'package:core_ui/core_ui.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:services/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:utils/utils.dart';

import 'features/audit/audit_panel.dart';
import 'features/catalog/catalog_panel.dart';
import 'features/customers/customers_panel.dart';
import 'features/dashboard/overview_panel.dart';
import 'features/disputes/disputes_panel.dart';
import 'features/finance/finance_panel.dart';
import 'features/listings/listings_panel.dart';
import 'features/orders/orders_panel.dart';
import 'features/settings/settings_panel.dart';
import 'widgets/admin_shared.dart';

class OneOfOneAdminApp extends StatelessWidget {
  const OneOfOneAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    final AdminAppBootstrap bootstrap = AdminAppBootstrap.fromEnvironment();
    return MaterialApp(
      title: 'One of One Admin',
      debugShowCheckedModeBanner: false,
      theme: OneOfOneTheme.adminTheme(),
      home: bootstrap.configurationError != null
          ? ConfigState(message: bootstrap.configurationError!)
          : AdminShell(
              client: bootstrap.client!,
              configurationError: bootstrap.configurationError,
            ),
    );
  }
}

class AdminAppBootstrap {
  const AdminAppBootstrap({
    required this.client,
    required this.configurationError,
  });

  final SupabaseClient? client;
  final String? configurationError;

  static AdminAppBootstrap fromEnvironment() {
    const String url = String.fromEnvironment('SUPABASE_URL');
    const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
    if (url.isEmpty || anonKey.isEmpty) {
      return const AdminAppBootstrap(
        client: null,
        configurationError:
            'Provide SUPABASE_URL and SUPABASE_ANON_KEY to run the admin console.',
      );
    }
    return AdminAppBootstrap(
      client: Supabase.instance.client,
      configurationError: null,
    );
  }
}

class AdminShell extends StatefulWidget {
  const AdminShell({required this.client, this.configurationError, super.key});

  final SupabaseClient client;
  final String? configurationError;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  static const List<String> _labels = <String>[
    'Overview',
    'Customers',
    'Orders',
    'Finance',
    'Listings',
    'Disputes',
    'Catalog',
    'Audit',
    'Settings',
  ];

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final GlobalKey<FormState> _authFormKey = GlobalKey<FormState>();

  late final SupabaseAuthService _authService;
  late final AdminOperationsService _adminService;
  StreamSubscription<AuthState>? _authSubscription;

  int _index = 0;
  bool _authBusy = false;
  bool _refreshing = false;
  String? _bannerMessage;
  bool _bannerIsError = false;
  AdminOperationsSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _authService = SupabaseAuthService(
      client: widget.client,
      configurationError: widget.configurationError,
    );
    _adminService = AdminOperationsService(
      repository: SupabaseAdminOperationsRepository(
        client: widget.client,
        configurationError: widget.configurationError,
      ),
    );
    _snapshot = _adminService.snapshot();
    _authSubscription = _authService.authStateChanges().listen((AuthState _) {
      if (!mounted) {
        return;
      }
      setState(() {
        _bannerMessage = null;
      });
      if (_authService.currentSession != null) {
        _refreshAdminData();
      } else {
        setState(() {
          _snapshot = null;
        });
      }
    });
    if (_authService.currentSession != null) {
      _refreshAdminData();
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_authService.currentSession == null) {
      return AdminSignInView(
        formKey: _authFormKey,
        emailController: _emailController,
        passwordController: _passwordController,
        isBusy: _authBusy,
        message: _bannerMessage,
        messageIsError: _bannerIsError,
        onSubmit: _signIn,
      );
    }

    final List<Widget> views = <Widget>[
      OverviewPanel(snapshot: _snapshot),
      CustomersPanel(
        customers: _snapshot?.customers ?? const <AdminCustomerRecord>[],
        onSetRole: _setUserRole,
      ),
      OrdersPanel(orders: _snapshot?.orders ?? const <AdminOrderRecord>[]),
      FinancePanel(finance: _snapshot?.finance ?? const <AdminFinanceRecord>[]),
      ListingsPanel(
        listings: _snapshot?.listings ?? const <AdminListingRecord>[],
        onModerateListing: _moderateListing,
        onFlagItem: _flagItem,
      ),
      DisputesPanel(
        disputes: _snapshot?.disputes ?? const <AdminDisputeRecord>[],
        onUpdateDispute: _updateDispute,
        onFlagItem: _flagItem,
      ),
      CatalogPanel(
        artists: _snapshot?.artists ?? const <AdminArtistRecord>[],
        artworks: _snapshot?.artworks ?? const <AdminArtworkRecord>[],
        inventory: _snapshot?.inventory ?? const <AdminInventoryRecord>[],
        garmentProducts:
            _snapshot?.garmentProducts ?? const <AdminGarmentProductRecord>[],
        onCreateArtist: _createArtist,
        onCreateArtwork: _createArtwork,
        onCreateInventory: _createInventory,
      ),
      AuditPanel(audits: _snapshot?.audits ?? const <AdminAuditRecord>[]),
      SettingsPanel(settings: _snapshot?.settings, onSave: _saveSettings),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('ONE OF ONE ADMIN'),
        actions: <Widget>[
          TextButton.icon(
            onPressed: _refreshing ? null : _refreshAdminData,
            icon: _refreshing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: _authBusy ? null : _signOut,
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Row(
        children: <Widget>[
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (int value) {
              setState(() {
                _index = value;
              });
            },
            labelType: NavigationRailLabelType.all,
            minWidth: 88,
            destinations: _labels
                .map(
                  (String label) => NavigationRailDestination(
                    icon: const Icon(Icons.chevron_right),
                    label: Text(label),
                  ),
                )
                .toList(),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[Color(0xFF121212), Color(0xFF1B1710)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                children: <Widget>[
                  if (_bannerMessage != null)
                    BannerStrip(
                      message: _bannerMessage!,
                      isError: _bannerIsError,
                      onDismiss: () {
                        setState(() {
                          _bannerMessage = null;
                        });
                      },
                    ),
                  Expanded(
                    child: _snapshot == null && _refreshing
                        ? const Center(child: CircularProgressIndicator())
                        : views[_index],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshAdminData() async {
    setState(() {
      _refreshing = true;
    });
    final MarketplaceActionResult<AdminOperationsSnapshot> result =
        await _adminService.refresh();
    if (!mounted) {
      return;
    }
    setState(() {
      _refreshing = false;
      _bannerMessage = result.message;
      _bannerIsError = !result.success;
      if (result.success) {
        _snapshot = result.data;
      }
    });
  }

  Future<void> _signIn() async {
    if (!_authFormKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _authBusy = true;
      _bannerMessage = null;
    });

    final AuthActionResult result = await _authService.signInWithPassword(
      email: _emailController.text,
      password: _passwordController.text,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _authBusy = false;
      _bannerMessage = result.message;
      _bannerIsError = !result.success;
    });
    if (result.success) {
      await _refreshAdminData();
    }
  }

  Future<void> _signOut() async {
    await _authService.signOut();
    if (!mounted) {
      return;
    }
    setState(() {
      _snapshot = null;
      _bannerMessage = 'Admin session ended.';
      _bannerIsError = false;
    });
  }

  Future<void> _setUserRole(AdminCustomerRecord customer, String role) async {
    final MarketplaceActionResult<AdminCustomerRecord> result =
        await _adminService.setUserRole(userId: customer.userId, role: role);
    if (!mounted) {
      return;
    }
    setState(() {
      _snapshot = _adminService.snapshot();
      _bannerMessage = result.message;
      _bannerIsError = !result.success;
    });
  }

  Future<void> _moderateListing(
    AdminListingRecord listing,
    String action,
  ) async {
    final String? note = await _promptForNote(
      title: action == 'restore'
          ? 'Restore listing'
          : action == 'cancel'
          ? 'Cancel listing'
          : 'Block listing',
      hint: 'Add an internal moderation note',
      confirmLabel: action == 'restore' ? 'Restore' : 'Confirm',
    );
    if (note == null) {
      return;
    }
    final MarketplaceActionResult<AdminListingRecord> result =
        await _adminService.moderateListing(
          listingId: listing.listingId,
          action: action,
          note: note,
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _snapshot = _adminService.snapshot();
      _bannerMessage = result.message;
      _bannerIsError = !result.success;
    });
  }

  Future<void> _updateDispute(AdminDisputeRecord dispute) async {
    final DisputeActionInput? input = await promptForDisputeAction(
      context,
      dispute,
    );
    if (input == null) {
      return;
    }
    final MarketplaceActionResult<AdminDisputeRecord> result =
        await _adminService.updateDisputeStatus(
          disputeId: dispute.disputeId,
          status: input.status,
          note: input.note,
          releaseItem: input.releaseItem,
          releaseTargetState: input.releaseTargetState,
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _snapshot = _adminService.snapshot();
      _bannerMessage = result.message;
      _bannerIsError = !result.success;
    });
  }

  Future<void> _flagItem(
    String itemId,
    String targetState,
    String title,
  ) async {
    final String? note = await _promptForNote(
      title: title,
      hint: 'Add an internal note for this item action',
      confirmLabel: 'Apply',
    );
    if (note == null) {
      return;
    }
    final MarketplaceActionResult<void> result = await _adminService
        .flagItemStatus(itemId: itemId, targetState: targetState, note: note);
    if (!mounted) {
      return;
    }
    setState(() {
      _snapshot = _adminService.snapshot();
      _bannerMessage = result.message;
      _bannerIsError = !result.success;
    });
  }

  Future<void> _saveSettings(
    int platformFeeBps,
    int defaultRoyaltyBps,
    Map<String, dynamic> marketplaceRules,
    Map<String, dynamic> brandSettings,
  ) async {
    final MarketplaceActionResult<PlatformSettingsSnapshot> result =
        await _adminService.updateSettings(
          platformFeeBps: platformFeeBps,
          defaultRoyaltyBps: defaultRoyaltyBps,
          marketplaceRules: marketplaceRules,
          brandSettings: brandSettings,
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _snapshot = _adminService.snapshot();
      _bannerMessage = result.message;
      _bannerIsError = !result.success;
    });
  }

  Future<void> _createArtist() async {
    final _CatalogArtistInput? input = await promptForArtist(context);
    if (input == null) {
      return;
    }
    final MarketplaceActionResult<AdminArtistRecord> result = await _adminService
        .upsertArtist(
          displayName: input.displayName,
          slug: input.slug,
          royaltyBps: input.royaltyBps,
          authenticityStatement: input.authenticityStatement,
          isActive: input.isActive,
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _snapshot = _adminService.snapshot();
      _bannerMessage = result.message;
      _bannerIsError = !result.success;
    });
  }

  Future<void> _createArtwork() async {
    final _CatalogArtworkInput? input = await promptForArtwork(
      context,
      _snapshot?.artists ?? const <AdminArtistRecord>[],
    );
    if (input == null) {
      return;
    }
    final MarketplaceActionResult<AdminArtworkRecord> result = await _adminService
        .upsertArtwork(
          artistId: input.artistId,
          title: input.title,
          story: input.story,
          provenanceProof: input.provenanceProof,
          creationDate: input.creationDate,
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _snapshot = _adminService.snapshot();
      _bannerMessage = result.message;
      _bannerIsError = !result.success;
    });
  }

  Future<void> _createInventory() async {
    final List<AdminArtistRecord> artists =
        _snapshot?.artists ?? const <AdminArtistRecord>[];
    final List<AdminArtworkRecord> artworks =
        _snapshot?.artworks ?? const <AdminArtworkRecord>[];
    final List<AdminGarmentProductRecord> garmentProducts =
        _snapshot?.garmentProducts ?? const <AdminGarmentProductRecord>[];

    final List<String> missingRequirements = <String>[
      if (artists.isEmpty) 'at least one artist',
      if (artworks.isEmpty) 'at least one artwork',
      if (garmentProducts.isEmpty) 'at least one garment product',
    ];
    if (missingRequirements.isNotEmpty) {
      setState(() {
        _bannerMessage =
            'Inventory creation needs ${missingRequirements.join(', ')}. '
            'Refresh the admin console and make sure migrations and seed data are applied.';
        _bannerIsError = true;
      });
      return;
    }

    final _CatalogInventoryInput? input = await promptForInventory(
      context,
      artists,
      artworks,
      garmentProducts,
    );
    if (input == null) {
      return;
    }
    final MarketplaceActionResult<AdminInventoryRecord> result =
        await _adminService.upsertInventoryItem(
          artistId: input.artistId,
          artworkId: input.artworkId,
          garmentProductId: input.garmentProductId,
          serialNumber: input.serialNumber,
          itemState: input.itemState,
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _snapshot = _adminService.snapshot();
      _bannerMessage = result.message;
      _bannerIsError = !result.success;
    });
  }

  Future<String?> _promptForNote({
    required String title,
    required String hint,
    required String confirmLabel,
  }) async {
    final TextEditingController controller = TextEditingController();
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1712),
          title: Text(title),
          content: TextField(
            controller: controller,
            minLines: 3,
            maxLines: 5,
            decoration: InputDecoration(hintText: hint),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return value;
  }
}

class ConfigState extends StatelessWidget {
  const ConfigState({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Admin configuration required',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(message),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CatalogArtistInput {
  const _CatalogArtistInput({
    required this.displayName,
    required this.slug,
    required this.royaltyBps,
    required this.authenticityStatement,
    required this.isActive,
  });

  final String displayName;
  final String slug;
  final int royaltyBps;
  final String authenticityStatement;
  final bool isActive;
}

class _CatalogArtworkInput {
  const _CatalogArtworkInput({
    required this.artistId,
    required this.title,
    required this.story,
    required this.provenanceProof,
    required this.creationDate,
  });

  final String artistId;
  final String title;
  final String story;
  final List<String> provenanceProof;
  final DateTime? creationDate;
}

class _CatalogInventoryInput {
  const _CatalogInventoryInput({
    required this.artistId,
    required this.artworkId,
    required this.garmentProductId,
    required this.serialNumber,
    required this.itemState,
  });

  final String artistId;
  final String artworkId;
  final String garmentProductId;
  final String serialNumber;
  final String itemState;
}

class AdminSignInView extends StatelessWidget {
  const AdminSignInView({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.isBusy,
    required this.message,
    required this.messageIsError,
    required this.onSubmit,
    super.key,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool isBusy;
  final String? message;
  final bool messageIsError;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Operational access',
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Sign in with an approved admin, owner, support, or artist-manager account. Ownership and restriction controls remain server-authoritative.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
                    if (message != null)
                      InlineMessage(message: message!, isError: messageIsError),
                    TextFormField(
                      controller: emailController,
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (String? value) => validateEmail(value ?? ''),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                      validator: (String? value) =>
                          validatePassword(value ?? ''),
                      onFieldSubmitted: (_) => onSubmit(),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: isBusy ? null : onSubmit,
                        child: isBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Enter admin console'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DisputeActionInput {
  const DisputeActionInput({
    required this.status,
    required this.note,
    required this.releaseItem,
    required this.releaseTargetState,
  });

  final String status;
  final String note;
  final bool releaseItem;
  final String? releaseTargetState;
}

Future<_CatalogArtistInput?> promptForArtist(BuildContext context) async {
  final TextEditingController displayName = TextEditingController();
  final TextEditingController slug = TextEditingController();
  final TextEditingController royalty = TextEditingController(text: '1200');
  final TextEditingController statement = TextEditingController();
  bool isActive = true;

  final _CatalogArtistInput? value = await showDialog<_CatalogArtistInput>(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1712),
            title: const Text('Create artist'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextField(
                    controller: displayName,
                    decoration: const InputDecoration(labelText: 'Display name'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: slug,
                    decoration: const InputDecoration(labelText: 'Slug'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: royalty,
                    decoration: const InputDecoration(labelText: 'Royalty bps'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: statement,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Authenticity statement',
                    ),
                  ),
                  CheckboxListTile(
                    value: isActive,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active artist'),
                    onChanged: (bool? value) {
                      setDialogState(() {
                        isActive = value ?? true;
                      });
                    },
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(
                  _CatalogArtistInput(
                    displayName: displayName.text.trim(),
                    slug: slug.text.trim(),
                    royaltyBps: int.tryParse(royalty.text.trim()) ?? 1200,
                    authenticityStatement: statement.text.trim(),
                    isActive: isActive,
                  ),
                ),
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );
  displayName.dispose();
  slug.dispose();
  royalty.dispose();
  statement.dispose();
  return value;
}

Future<_CatalogArtworkInput?> promptForArtwork(
  BuildContext context,
  List<AdminArtistRecord> artists,
) async {
  if (artists.isEmpty) {
    return null;
  }

  final TextEditingController title = TextEditingController();
  final TextEditingController story = TextEditingController();
  final TextEditingController proof = TextEditingController();
  final TextEditingController created = TextEditingController();
  String artistId = artists.first.artistId;

  final _CatalogArtworkInput? value = await showDialog<_CatalogArtworkInput>(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1712),
            title: const Text('Create artwork'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  DropdownButtonFormField<String>(
                    initialValue: artistId,
                    decoration: const InputDecoration(labelText: 'Artist'),
                    items: artists
                        .map(
                          (AdminArtistRecord artist) => DropdownMenuItem<String>(
                            value: artist.artistId,
                            child: Text(artist.displayName),
                          ),
                        )
                        .toList(),
                    onChanged: (String? value) {
                      if (value != null) {
                        setDialogState(() {
                          artistId = value;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: story,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(labelText: 'Story'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: proof,
                    decoration: const InputDecoration(
                      labelText: 'Provenance proof (comma separated)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: created,
                    decoration: const InputDecoration(
                      labelText: 'Creation date (YYYY-MM-DD)',
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(
                  _CatalogArtworkInput(
                    artistId: artistId,
                    title: title.text.trim(),
                    story: story.text.trim(),
                    provenanceProof: proof.text
                        .split(',')
                        .map((String item) => item.trim())
                        .where((String item) => item.isNotEmpty)
                        .toList(),
                    creationDate: DateTime.tryParse(created.text.trim()),
                  ),
                ),
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );
  title.dispose();
  story.dispose();
  proof.dispose();
  created.dispose();
  return value;
}

Future<_CatalogInventoryInput?> promptForInventory(
  BuildContext context,
  List<AdminArtistRecord> artists,
  List<AdminArtworkRecord> artworks,
  List<AdminGarmentProductRecord> garmentProducts,
) async {
  if (artists.isEmpty || artworks.isEmpty || garmentProducts.isEmpty) {
    return null;
  }

  final TextEditingController serialNumber = TextEditingController();
  String artistId = artists.first.artistId;
  String artworkId = artworks.first.artworkId;
  String garmentProductId = garmentProducts.first.garmentProductId;
  String itemState = 'minted';

  final _CatalogInventoryInput? value = await showDialog<_CatalogInventoryInput>(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1712),
            title: const Text('Create inventory item'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  DropdownButtonFormField<String>(
                    initialValue: artistId,
                    decoration: const InputDecoration(labelText: 'Artist'),
                    items: artists
                        .map(
                          (AdminArtistRecord artist) => DropdownMenuItem<String>(
                            value: artist.artistId,
                            child: Text(artist.displayName),
                          ),
                        )
                        .toList(),
                    onChanged: (String? value) {
                      if (value != null) {
                        setDialogState(() {
                          artistId = value;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: artworkId,
                    decoration: const InputDecoration(labelText: 'Artwork'),
                    items: artworks
                        .map(
                          (AdminArtworkRecord artwork) =>
                              DropdownMenuItem<String>(
                                value: artwork.artworkId,
                                child: Text(artwork.title),
                              ),
                        )
                        .toList(),
                    onChanged: (String? value) {
                      if (value != null) {
                        setDialogState(() {
                          artworkId = value;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: garmentProductId,
                    decoration: const InputDecoration(
                      labelText: 'Garment product',
                    ),
                    items: garmentProducts
                        .map(
                          (
                            AdminGarmentProductRecord garmentProduct,
                          ) => DropdownMenuItem<String>(
                            value: garmentProduct.garmentProductId,
                            child: Text(
                              '${garmentProduct.name} (${garmentProduct.sku})',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (String? value) {
                      if (value != null) {
                        setDialogState(() {
                          garmentProductId = value;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: serialNumber,
                    decoration: const InputDecoration(labelText: 'Serial number'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: itemState,
                    decoration: const InputDecoration(labelText: 'Item state'),
                    items: const <String>[
                      'drafted',
                      'minted',
                      'in_inventory',
                      'sold_unclaimed',
                      'claimed',
                    ].map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                    onChanged: (String? value) {
                      if (value != null) {
                        setDialogState(() {
                          itemState = value;
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(
                  _CatalogInventoryInput(
                    artistId: artistId,
                    artworkId: artworkId,
                    garmentProductId: garmentProductId,
                    serialNumber: serialNumber.text.trim(),
                    itemState: itemState,
                  ),
                ),
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );
  serialNumber.dispose();
  return value;
}

Future<DisputeActionInput?> promptForDisputeAction(
  BuildContext context,
  AdminDisputeRecord dispute,
) async {
  final TextEditingController controller = TextEditingController();
  String status = dispute.disputeStatus == 'open'
      ? 'under_review'
      : dispute.disputeStatus;
  bool releaseItem = false;
  String releaseTargetState = 'claimed';

  final DisputeActionInput? value = await showDialog<DisputeActionInput>(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1712),
            title: Text('Update dispute ${dispute.serialNumber}'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(
                      labelText: 'Dispute status',
                    ),
                    items:
                        const <String>[
                          'open',
                          'under_review',
                          'resolved',
                          'rejected',
                        ].map((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          );
                        }).toList(),
                    onChanged: (String? value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() {
                        status = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: releaseItem,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Release item from restricted state'),
                    subtitle: const Text(
                      'Use only when the dispute outcome allows the item to return to a safe non-restricted lifecycle state.',
                    ),
                    onChanged: (bool? value) {
                      setDialogState(() {
                        releaseItem = value ?? false;
                      });
                    },
                  ),
                  if (releaseItem) ...<Widget>[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: releaseTargetState,
                      decoration: const InputDecoration(
                        labelText: 'Release target state',
                      ),
                      items:
                          const <String>[
                            'claimed',
                            'transferred',
                            'sold_unclaimed',
                            'in_inventory',
                            'archived',
                          ].map((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            );
                          }).toList(),
                      onChanged: (String? value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() {
                          releaseTargetState = value;
                        });
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Admin note',
                      hintText: 'Document the resolution rationale',
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop(
                    DisputeActionInput(
                      status: status,
                      note: controller.text.trim(),
                      releaseItem: releaseItem,
                      releaseTargetState: releaseItem
                          ? releaseTargetState
                          : null,
                    ),
                  );
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      );
    },
  );
  controller.dispose();
  return value;
}
