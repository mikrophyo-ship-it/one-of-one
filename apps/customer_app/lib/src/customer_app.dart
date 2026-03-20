import 'package:core_ui/core_ui.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:services/services.dart';
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
  late final CustomerController controller;

  @override
  void initState() {
    super.initState();
    repository = DemoCatalog();
    workflowService = MarketplaceWorkflowService(
      repository: repository,
      paymentProvider: const MockPaymentProvider(),
    );
    controller = CustomerController(
      repository: repository,
      workflowService: workflowService,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, _) {
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
                      border: Border.all(color: OneOfOneTheme.gold.withOpacity(0.25)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: controller.notifications.isEmpty
                          ? <Widget>[const Text('No new notifications.')]
                          : controller.notifications
                              .map((String note) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Text(note),
                                  ))
                              .toList(),
                    ),
                  ),
                ),
              if (controller.isBusy)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.35),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: controller.index,
            onDestinationSelected: controller.setIndex,
            destinations: const <Widget>[
              NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.auto_awesome_mosaic_outlined), label: 'Shop'),
              NavigationDestination(icon: Icon(Icons.qr_code_scanner_outlined), label: 'Scan'),
              NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'Vault'),
              NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
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
  })  : _repository = repository,
        _workflowService = workflowService;

  final MarketplaceRepository _repository;
  final MarketplaceWorkflowService _workflowService;

  bool isAuthenticated = false;
  bool showInbox = false;
  bool isBusy = false;
  int index = 0;
  String currentUserId = 'user_collector_1';
  String? statusMessage;
  String? errorMessage;
  final List<String> notifications = <String>[
    'Afterglow No. 01 has new resale interest.',
    'Ownership certificate ready for download.',
  ];

  List<Artist> get artists => _repository.featuredArtists();
  List<Artwork> get artworks => _repository.artworks();
  List<UniqueItem> get items => _repository.items();
  List<Listing> get listings => _repository.activeListings();
  List<UniqueItem> get vaultItems =>
      items.where((UniqueItem item) => item.currentOwnerUserId == currentUserId).toList();

  Artwork artworkFor(UniqueItem item) =>
      _repository.artworkById(item.artworkId) ?? artworks.first;

  List<OwnershipRecord> historyFor(String itemId) => _repository.ownershipHistory(itemId);

  UniqueItem? itemById(String itemId) => _repository.itemById(itemId);

  FeeBreakdown breakdownFor(UniqueItem item) {
    return MarketplaceRules(
      platformFeeBps: 1000,
      defaultRoyaltyBps: artists.first.royaltyBps,
    ).calculateResaleBreakdown(
      resalePrice: item.askingPrice ?? 0,
      royaltyBps: artists.first.royaltyBps,
    );
  }

  void signIn() {
    isAuthenticated = true;
    statusMessage = 'Signed in. Critical ownership actions now route through the backend workflow layer.';
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

  Future<String> claimItem({
    required String itemId,
    required String claimCode,
  }) async {
    return _runAction<UniqueItem>(
      operation: () => _workflowService.claimOwnership(
        itemId: itemId,
        claimCode: claimCode,
        userId: currentUserId,
      ),
      onSuccess: (UniqueItem? item, String message) {
        if (item != null) {
          notifications.insert(0, 'Ownership refreshed for ${item.serialNumber}.');
        }
        return message;
      },
    );
  }

  Future<String> createResale({
    required String itemId,
    required int priceCents,
  }) async {
    return _runAction<Listing>(
      operation: () => _workflowService.createResaleListing(
        itemId: itemId,
        userId: currentUserId,
        priceCents: priceCents,
      ),
      onSuccess: (Listing? listing, String message) {
        if (listing != null) {
          notifications.insert(0, 'Listing ${listing.id} is live for on-platform resale.');
        }
        return message;
      },
    );
  }

  Future<String> buyResale({required String itemId}) async {
    return _runAction<UniqueItem>(
      operation: () => _workflowService.buyResaleItem(
        itemId: itemId,
        buyerUserId: 'user_buyer_v1',
      ),
      onSuccess: (UniqueItem? item, String message) {
        if (item != null) {
          notifications.insert(0, '${item.serialNumber} transferred after successful on-platform checkout.');
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
    return _runAction<UniqueItem>(
      operation: () => _workflowService.openDispute(
        itemId: itemId,
        userId: currentUserId,
        reason: reason,
        freeze: freeze,
      ),
      onSuccess: (UniqueItem? item, String message) {
        if (item != null) {
          notifications.insert(0, '${item.serialNumber} moved to ${item.state.key.replaceAll('_', ' ')} for review.');
        }
        return message;
      },
    );
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
}

class AuthScreen extends StatelessWidget {
  const AuthScreen({required this.controller, super.key});

  final CustomerController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Collect the original.', style: Theme.of(context).textTheme.displaySmall),
                    const SizedBox(height: 12),
                    Text(
                      'Sign in to claim ownership, access your vault, and resell authenticated pieces on-platform only.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
                    const TextField(decoration: InputDecoration(labelText: 'Email')),
                    const SizedBox(height: 12),
                    const TextField(obscureText: true, decoration: InputDecoration(labelText: 'Password')),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: controller.signIn,
                        child: const Text('Sign In'),
                      ),
                    ),
                    TextButton(onPressed: controller.signIn, child: const Text('Create account')),
                    TextButton(onPressed: controller.signIn, child: const Text('Forgot password')),
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
        Text('Featured artists', style: Theme.of(context).textTheme.headlineSmall),
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
        Text('Recent resale activity', style: Theme.of(context).textTheme.headlineSmall),
        if (controller.listings.isEmpty)
          const Card(child: ListTile(title: Text('No live resale listings right now.'))),
        ...controller.listings.map(
          (Listing listing) => Card(
            child: ListTile(
              title: Text('Verified resale ${formatCurrency(listing.askingPrice)}'),
              subtitle: Text('Listing ${listing.id} for item ${listing.itemId}'),
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
          Text('Latest collectible drop', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Text(item.productName, style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 8),
          Text('Public serial ${item.serialNumber} • ${item.state.key.replaceAll('_', ' ')}'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ItemDetailScreen(controller: controller, itemId: item.id),
              ));
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
        const TextField(decoration: InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Filter by artist, price, availability')),
        const SizedBox(height: 16),
        ...controller.items.map(
          (UniqueItem item) => Card(
            child: ListTile(
              title: Text(item.productName),
              subtitle: Text('${item.serialNumber} • ${item.state.key.replaceAll('_', ' ')}'),
              trailing: Text(item.askingPrice == null ? 'Held' : formatCurrency(item.askingPrice!)),
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => ItemDetailScreen(controller: controller, itemId: item.id),
                ));
              },
            ),
          ),
        ),
      ],
    );
  }
}

class ItemDetailScreen extends StatelessWidget {
  const ItemDetailScreen({required this.controller, required this.itemId, super.key});

  final CustomerController controller;
  final String itemId;

  @override
  Widget build(BuildContext context) {
    final UniqueItem? item = controller.itemById(itemId);
    if (item == null) {
      return const Scaffold(body: Center(child: Text('Collectible not found.')));
    }

    final Artwork artwork = controller.artworkFor(item);
    final FeeBreakdown breakdown = controller.breakdownFor(item);
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
              border: Border.all(color: OneOfOneTheme.gold.withOpacity(0.3)),
            ),
            child: const Center(child: Text('Editorial garment image / human-made proof media')),
          ),
          const SizedBox(height: 16),
          Text(artwork.title, style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 8),
          Text('Artist: ${controller.artists.first.displayName}'),
          Text('Serial: ${item.serialNumber}'),
          Text('Authenticity: verified human-made artwork'),
          const SizedBox(height: 12),
          Text(artwork.story),
          const SizedBox(height: 12),
          Text('Provenance proof', style: Theme.of(context).textTheme.headlineSmall),
          ...artwork.humanMadeProof.map((String proof) => ListTile(title: Text(proof))),
          const SizedBox(height: 12),
          Text('Ownership history summary', style: Theme.of(context).textTheme.headlineSmall),
          ...controller.historyFor(item.id).map(
            (OwnershipRecord record) => ListTile(
              title: Text(record.ownerUserId),
              subtitle: Text('Acquired ${record.acquiredAt.toIso8601String().split('T').first}'),
            ),
          ),
          if (item.askingPrice != null) ...<Widget>[
            const SizedBox(height: 12),
            Text('Resale financials', style: Theme.of(context).textTheme.headlineSmall),
            ListTile(title: const Text('Asking price'), trailing: Text(formatCurrency(breakdown.grossAmount))),
            ListTile(title: const Text('Platform fee'), trailing: Text(formatCurrency(breakdown.platformFee))),
            ListTile(title: const Text('Artist royalty'), trailing: Text(formatCurrency(breakdown.artistRoyalty))),
            ListTile(title: const Text('Seller payout'), trailing: Text(formatCurrency(breakdown.sellerPayout))),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              if (item.askingPrice != null && !item.state.isRestricted)
                ElevatedButton(
                  onPressed: () async {
                    final String message = await controller.buyResale(itemId: item.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
                    }
                  },
                  child: const Text('Buy resale item'),
                ),
              if (item.currentOwnerUserId == controller.currentUserId && !item.state.isRestricted)
                OutlinedButton(
                  onPressed: () async {
                    final String message = await controller.createResale(itemId: item.id, priceCents: 225000);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
                    }
                  },
                  child: const Text('Resell item'),
                ),
              OutlinedButton(
                onPressed: () async {
                  final String message = await controller.openDispute(
                    itemId: item.id,
                    reason: 'Collector requested review of ownership condition.',
                    freeze: item.state == ItemState.stolenFlagged || item.state == ItemState.frozen,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
  final TextEditingController _claimCodeController = TextEditingController();

  @override
  void dispose() {
    _claimCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final UniqueItem scanned = widget.controller.items[1];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Scan authenticity QR', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                const Text('V1 flow opens a privacy-safe authenticity route and requires a separate hidden claim code for ownership.'),
                const SizedBox(height: 12),
                Text('Detected item: ${scanned.serialNumber}'),
                Text('Public status: ${scanned.state.key.replaceAll('_', ' ')}'),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => PublicAuthenticityPage(controller: widget.controller, itemId: scanned.id),
                    ));
                  },
                  child: const Text('Open public authenticity page'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _claimCodeController,
                  decoration: const InputDecoration(
                    labelText: 'Enter hidden claim code',
                    helperText: 'Packaged separately from the public QR.',
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () async {
                    final String message = await widget.controller.claimItem(
                      itemId: scanned.id,
                      claimCode: _claimCodeController.text,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
                    }
                    _claimCodeController.clear();
                  },
                  child: const Text('Claim ownership'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class PublicAuthenticityPage extends StatelessWidget {
  const PublicAuthenticityPage({required this.controller, required this.itemId, super.key});

  final CustomerController controller;
  final String itemId;

  @override
  Widget build(BuildContext context) {
    final UniqueItem? item = controller.itemById(itemId);
    if (item == null) {
      return const Scaffold(body: Center(child: Text('Authenticity record unavailable.')));
    }
    final Artwork artwork = controller.artworkFor(item);
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
                  const Text('Verified collectible status'),
                  const SizedBox(height: 8),
                  Text(item.serialNumber, style: Theme.of(context).textTheme.displaySmall),
                  Text(artwork.title),
                  Text(controller.artists.first.displayName),
                  Text('Marketplace status: ${item.state.key.replaceAll('_', ' ')}'),
                  const SizedBox(height: 12),
                  Text(artwork.story),
                  const SizedBox(height: 12),
                  const Text('Ownership visibility: current owner hidden, platform verification only.'),
                  Text('Resale history summary: ${controller.historyFor(item.id).length - 1} verified transfer(s).'),
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
        if (controller.vaultItems.isEmpty)
          const Card(
            child: ListTile(
              title: Text('No claimed collectibles yet.'),
              subtitle: Text('Claim with the hidden packaged code after scanning a verified item.'),
            ),
          ),
        ...controller.vaultItems.map(
          (UniqueItem item) => Card(
            child: ListTile(
              title: Text(item.productName),
              subtitle: Text('Certificate active • ${item.state.key.replaceAll('_', ' ')}'),
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
        Text('Collector profile', style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            title: const Text('Account settings'),
            subtitle: Text('Signed in as ${controller.currentUserId}. Profile creation should call upsert_my_profile next.'),
          ),
        ),
        const Card(
          child: ListTile(
            title: Text('Transaction history'),
            subtitle: Text('Primary purchase, resale activity, royalty-aware transfers'),
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






