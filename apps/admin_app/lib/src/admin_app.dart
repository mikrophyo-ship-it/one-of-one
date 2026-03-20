import 'package:core_ui/core_ui.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:utils/utils.dart';

class OneOfOneAdminApp extends StatelessWidget {
  const OneOfOneAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'One of One Admin',
      debugShowCheckedModeBanner: false,
      theme: OneOfOneTheme.adminTheme(),
      home: const AdminShell(),
    );
  }
}

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int index = 0;
  final DemoCatalog catalog = DemoCatalog();

  static const List<String> labels = <String>[
    'Overview',
    'Artists',
    'Artworks',
    'Minting',
    'Inventory',
    'Customers',
    'Orders',
    'Listings',
    'Disputes',
    'Audit',
    'Settings',
  ];

  @override
  Widget build(BuildContext context) {
    final List<Widget> views = <Widget>[
      OverviewPanel(catalog: catalog),
      ArtistsPanel(catalog: catalog),
      ArtworksPanel(catalog: catalog),
      MintingPanel(catalog: catalog),
      InventoryPanel(catalog: catalog),
      const GenericPanel(title: 'Customer management', description: 'Review account status, ownership, and privacy-safe activity history.'),
      const GenericPanel(title: 'Order management', description: 'Track primary and resale orders, payment state, and payout readiness.'),
      const GenericPanel(title: 'Listing moderation', description: 'Moderate resale listings and automatically suppress restricted items.'),
      const GenericPanel(title: 'Dispute management', description: 'Review disputes, hold payout, and escalate stolen or frozen state controls.'),
      const GenericPanel(title: 'Audit log viewer', description: 'Inspect claims, state changes, payout holds, and admin interventions.'),
      const SettingsPanel(),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('ONE OF ONE ADMIN')),
      body: Row(
        children: <Widget>[
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: (int value) => setState(() => index = value),
            destinations: labels
                .map((String label) => NavigationRailDestination(icon: const Icon(Icons.chevron_right), label: Text(label)))
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
              child: views[index],
            ),
          ),
        ],
      ),
    );
  }
}

class OverviewPanel extends StatelessWidget {
  const OverviewPanel({required this.catalog, super.key});

  final DemoCatalog catalog;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text('Operational overview', style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            _MetricCard(title: 'Sales', value: formatCurrency(520000)),
            _MetricCard(title: 'Resale volume', value: formatCurrency(180000)),
            _MetricCard(title: 'Royalties', value: formatCurrency(21600)),
            _MetricCard(title: 'Open disputes', value: '2'),
          ],
        ),
        const SizedBox(height: 20),
        const GenericPanel(
          title: 'Marketplace guardrails',
          description: 'Ownership stays server-authoritative. Off-platform sales are not recognized. Restricted items cannot be listed, sold, transferred, or claimed.',
        ),
      ],
    );
  }
}

class ArtistsPanel extends StatelessWidget {
  const ArtistsPanel({required this.catalog, super.key});

  final DemoCatalog catalog;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text('Artists', style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 12),
        ...catalog.featuredArtists().map(
          (Artist artist) => Card(
            child: ListTile(
              title: Text(artist.displayName),
              subtitle: Text(artist.authenticityStatement),
              trailing: Text('${artist.royaltyBps / 100}% royalty'),
            ),
          ),
        ),
        const GenericPanel(
          title: 'Payout configuration',
          description: 'Admin controls default and per-artist royalty settings separately from platform fee policy.',
        ),
      ],
    );
  }
}

class ArtworksPanel extends StatelessWidget {
  const ArtworksPanel({required this.catalog, super.key});

  final DemoCatalog catalog;

  @override
  Widget build(BuildContext context) {
    final Artwork artwork = catalog.artworks().first;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text('Artwork management', style: Theme.of(context).textTheme.displaySmall),
        Card(
          child: ListTile(
            title: Text(artwork.title),
            subtitle: Text(artwork.story),
          ),
        ),
        ...artwork.humanMadeProof.map((String media) => ListTile(title: Text(media))),
      ],
    );
  }
}

class MintingPanel extends StatelessWidget {
  const MintingPanel({required this.catalog, super.key});

  final DemoCatalog catalog;

  @override
  Widget build(BuildContext context) {
    final UniqueItem item = catalog.items().first;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text('Product and unique item minting', style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            title: const Text('Minted unit'),
            subtitle: Text('${item.productName} • ${item.serialNumber}'),
            trailing: const Text('QR + hidden claim code generated'),
          ),
        ),
        const GenericPanel(
          title: 'V2-ready transfer hook',
          description: 'Transfer records preserve room for future NFC or Bluetooth verification without changing the ownership authority model.',
        ),
      ],
    );
  }
}

class InventoryPanel extends StatelessWidget {
  const InventoryPanel({required this.catalog, super.key});

  final DemoCatalog catalog;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text('Inventory and item states', style: Theme.of(context).textTheme.displaySmall),
        ...catalog.items().map(
          (UniqueItem item) => Card(
            child: ListTile(
              title: Text(item.productName),
              subtitle: Text('State: ${item.state.key}'),
              trailing: Text(item.serialNumber),
            ),
          ),
        ),
      ],
    );
  }
}

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return const GenericPanel(
      title: 'Marketplace settings',
      description: 'Configure platform fee rate, default royalty rate, marketplace rules, and editorial brand settings without exposing any client secrets.',
    );
  }
}

class GenericPanel extends StatelessWidget {
  const GenericPanel({required this.title, required this.description, super.key});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text(description),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title),
              const SizedBox(height: 8),
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
        ),
      ),
    );
  }
}
