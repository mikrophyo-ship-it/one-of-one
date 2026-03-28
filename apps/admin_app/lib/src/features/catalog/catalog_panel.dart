import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:utils/utils.dart';

import '../../widgets/admin_shared.dart';

class CatalogPanel extends StatelessWidget {
  const CatalogPanel({
    required this.artists,
    required this.artworks,
    required this.inventory,
    required this.garmentProducts,
    required this.onCreateArtist,
    required this.onCreateArtwork,
    required this.onCreateInventory,
    required this.onCreateAuthenticityRecord,
    required this.onUpsertListing,
    required this.onRevealClaimCode,
    required this.onGenerateClaimPacket,
    required this.onUploadInventoryImage,
    required this.onRemoveInventoryImage,
    required this.busyInventoryItemIds,
    super.key,
  });

  final List<AdminArtistRecord> artists;
  final List<AdminArtworkRecord> artworks;
  final List<AdminInventoryRecord> inventory;
  final List<AdminGarmentProductRecord> garmentProducts;
  final VoidCallback onCreateArtist;
  final VoidCallback onCreateArtwork;
  final VoidCallback onCreateInventory;
  final Future<void> Function(AdminInventoryRecord item)
  onCreateAuthenticityRecord;
  final Future<void> Function(AdminInventoryRecord item) onUpsertListing;
  final Future<void> Function(AdminInventoryRecord item) onRevealClaimCode;
  final Future<void> Function(AdminInventoryRecord item) onGenerateClaimPacket;
  final Future<void> Function(AdminInventoryRecord item) onUploadInventoryImage;
  final Future<void> Function(AdminInventoryRecord item) onRemoveInventoryImage;
  final Set<String> busyInventoryItemIds;

  static final ButtonStyle _compactActionStyle = FilledButton.styleFrom(
    minimumSize: const Size(0, 34),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
  );

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Catalog operations',
                style: Theme.of(context).textTheme.displaySmall,
              ),
            ),
            FilledButton(
              onPressed: onCreateArtist,
              child: const Text('New artist'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: onCreateArtwork,
              child: const Text('New artwork'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: onCreateInventory,
              child: const Text('New inventory'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Operational CRUD for artists, artworks, and serialized inventory while keeping ownership and restriction controls on the server.',
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Artists',
          child: artists.isEmpty
              ? const EmptyState(message: 'No artist records available.')
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    dataRowMinHeight: 72,
                    dataRowMaxHeight: 108,
                    columns: const <DataColumn>[
                      DataColumn(label: Text('Artist')),
                      DataColumn(label: Text('Slug')),
                      DataColumn(label: Text('Royalty')),
                      DataColumn(label: Text('Artworks')),
                      DataColumn(label: Text('Inventory')),
                      DataColumn(label: Text('Status')),
                    ],
                    rows: artists.map((AdminArtistRecord artist) {
                      return DataRow(
                        cells: <DataCell>[
                          DataCell(Text(artist.displayName)),
                          DataCell(Text(artist.slug)),
                          DataCell(Text('${artist.royaltyBps} bps')),
                          DataCell(Text('${artist.artworkCount}')),
                          DataCell(Text('${artist.inventoryCount}')),
                          DataCell(
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: <Widget>[
                                StatusPill(label: artist.profileStatus),
                                if (artist.isFeatured)
                                  const StatusPill(label: 'featured'),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Artworks',
          child: artworks.isEmpty
              ? const EmptyState(message: 'No artwork records available.')
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const <DataColumn>[
                      DataColumn(label: Text('Title')),
                      DataColumn(label: Text('Artist')),
                      DataColumn(label: Text('Created')),
                      DataColumn(label: Text('Inventory')),
                    ],
                    rows: artworks.map((AdminArtworkRecord artwork) {
                      return DataRow(
                        cells: <DataCell>[
                          DataCell(Text(artwork.title)),
                          DataCell(Text(artwork.artistName)),
                          DataCell(
                            Text(
                              artwork.creationDate == null
                                  ? 'n/a'
                                  : formatAdminDate(artwork.creationDate!),
                            ),
                          ),
                          DataCell(Text('${artwork.inventoryCount}')),
                        ],
                      );
                    }).toList(),
                  ),
                ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Garment products',
          child: garmentProducts.isEmpty
              ? const EmptyState(message: 'No garment products available.')
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const <DataColumn>[
                      DataColumn(label: Text('Name')),
                      DataColumn(label: Text('SKU')),
                      DataColumn(label: Text('Silhouette')),
                      DataColumn(label: Text('Size')),
                      DataColumn(label: Text('Colorway')),
                      DataColumn(label: Text('Base price')),
                    ],
                    rows: garmentProducts.map((AdminGarmentProductRecord item) {
                      return DataRow(
                        cells: <DataCell>[
                          DataCell(Text(item.name)),
                          DataCell(Text(item.sku)),
                          DataCell(Text(item.silhouette ?? 'n/a')),
                          DataCell(Text(item.sizeLabel ?? 'n/a')),
                          DataCell(Text(item.colorway ?? 'n/a')),
                          DataCell(Text(formatCurrency(item.basePriceCents))),
                        ],
                      );
                    }).toList(),
                  ),
                ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Inventory',
          child: inventory.isEmpty
              ? const EmptyState(message: 'No inventory available.')
              : _InventorySection(
                  inventory: inventory,
                  busyInventoryItemIds: busyInventoryItemIds,
                  onCreateAuthenticityRecord: onCreateAuthenticityRecord,
                  onUpsertListing: onUpsertListing,
                  onRevealClaimCode: onRevealClaimCode,
                  onGenerateClaimPacket: onGenerateClaimPacket,
                  onUploadInventoryImage: onUploadInventoryImage,
                  onRemoveInventoryImage: onRemoveInventoryImage,
                ),
        ),
      ],
    );
  }
}

class _InventorySection extends StatefulWidget {
  const _InventorySection({
    required this.inventory,
    required this.busyInventoryItemIds,
    required this.onCreateAuthenticityRecord,
    required this.onUpsertListing,
    required this.onRevealClaimCode,
    required this.onGenerateClaimPacket,
    required this.onUploadInventoryImage,
    required this.onRemoveInventoryImage,
  });

  final List<AdminInventoryRecord> inventory;
  final Set<String> busyInventoryItemIds;
  final Future<void> Function(AdminInventoryRecord item)
  onCreateAuthenticityRecord;
  final Future<void> Function(AdminInventoryRecord item) onUpsertListing;
  final Future<void> Function(AdminInventoryRecord item) onRevealClaimCode;
  final Future<void> Function(AdminInventoryRecord item) onGenerateClaimPacket;
  final Future<void> Function(AdminInventoryRecord item) onUploadInventoryImage;
  final Future<void> Function(AdminInventoryRecord item) onRemoveInventoryImage;

  @override
  State<_InventorySection> createState() => _InventorySectionState();
}

class _InventorySectionState extends State<_InventorySection> {
  static const String _allArtists = '__all_artists__';
  static const String _allOwners = '__all_owners__';
  static const String _allStates = '__all_states__';

  String _searchQuery = '';
  String _artistFilter = _allArtists;
  String _ownerFilter = _allOwners;
  String _stateFilter = _allStates;
  _InventorySortOption _sortOption = _InventorySortOption.newestFirst;

  @override
  Widget build(BuildContext context) {
    final ScrollController inventoryScrollController = ScrollController();
    final List<String> artistOptions =
        widget.inventory
            .map((AdminInventoryRecord item) => item.artistName)
            .toSet()
            .toList()
          ..sort();
    final List<String> ownerOptions =
        widget.inventory
            .map((AdminInventoryRecord item) => item.ownerDisplayLabel)
            .toSet()
            .toList()
          ..sort();
    final List<String> stateOptions =
        widget.inventory
            .map((AdminInventoryRecord item) => item.itemState)
            .toSet()
            .toList()
          ..sort();
    final List<AdminInventoryRecord> filteredInventory = _filteredInventory();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            SizedBox(
              width: 260,
              child: TextField(
                onChanged: (String value) {
                  setState(() {
                    _searchQuery = value.trim().toLowerCase();
                  });
                },
                decoration: const InputDecoration(
                  labelText: 'Search inventory',
                  hintText: 'Serial, artwork, garment, owner',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            _FilterDropdown(
              label: 'Artist',
              value: _artistFilter,
              options: <String>[_allArtists, ...artistOptions],
              optionLabel: (String value) =>
                  value == _allArtists ? 'All artists' : value,
              onChanged: (String value) {
                setState(() {
                  _artistFilter = value;
                });
              },
            ),
            _FilterDropdown(
              label: 'Owner',
              value: _ownerFilter,
              options: <String>[_allOwners, ...ownerOptions],
              optionLabel: (String value) =>
                  value == _allOwners ? 'All owners' : value,
              onChanged: (String value) {
                setState(() {
                  _ownerFilter = value;
                });
              },
            ),
            _FilterDropdown(
              label: 'State',
              value: _stateFilter,
              options: <String>[_allStates, ...stateOptions],
              optionLabel: (String value) =>
                  value == _allStates ? 'All states' : value,
              onChanged: (String value) {
                setState(() {
                  _stateFilter = value;
                });
              },
            ),
            _FilterDropdown(
              label: 'Sort',
              value: _sortOption.name,
              options: _InventorySortOption.values
                  .map((_InventorySortOption option) => option.name)
                  .toList(),
              optionLabel: (String value) => _sortLabel(
                _InventorySortOption.values.firstWhere(
                  (_InventorySortOption option) => option.name == value,
                ),
              ),
              onChanged: (String value) {
                setState(() {
                  _sortOption = _InventorySortOption.values.firstWhere(
                    (_InventorySortOption option) => option.name == value,
                  );
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _SummaryChip(
              label:
                  'Showing ${filteredInventory.length} of ${widget.inventory.length}',
            ),
            _SummaryChip(
              label:
                  '${filteredInventory.where((AdminInventoryRecord item) => item.hasAuthenticityRecord).length} authenticated',
            ),
            _SummaryChip(
              label:
                  '${filteredInventory.where((AdminInventoryRecord item) => item.hasEditorialImage).length} with photo',
            ),
            _SummaryChip(
              label:
                  '${filteredInventory.where((AdminInventoryRecord item) => item.listingStatus == 'active').length} live listings',
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (filteredInventory.isEmpty)
          const EmptyState(
            message:
                'No inventory items match the current search and filter settings.',
          )
        else
          Scrollbar(
            controller: inventoryScrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: inventoryScrollController,
              scrollDirection: Axis.horizontal,
              child: DataTable(
                horizontalMargin: 10,
                columnSpacing: 18,
                headingRowHeight: 46,
                dataRowMinHeight: 96,
                dataRowMaxHeight: 136,
                columns: const <DataColumn>[
                  DataColumn(label: Text('Item')),
                  DataColumn(label: Text('Owner')),
                  DataColumn(label: Text('State')),
                  DataColumn(label: Text('Readiness')),
                  DataColumn(label: Text('Price')),
                  DataColumn(label: Text('Created')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: filteredInventory.map((AdminInventoryRecord item) {
                  final bool photoBusy = widget.busyInventoryItemIds.contains(
                    item.itemId,
                  );
                  return DataRow(
                    cells: <DataCell>[
                      DataCell(
                        SizedBox(
                          width: 290,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                item.serialNumber,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${item.artistName} / ${item.artworkTitle}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.garmentName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 150,
                          child: Text(
                            item.ownerDisplayLabel,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(StatusPill(label: item.itemState)),
                      DataCell(
                        SizedBox(
                          width: 280,
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: <Widget>[
                              StatusPill(
                                label: item.hasAuthenticityRecord
                                    ? (item.authenticityStatus ?? 'linked')
                                    : 'missing auth',
                              ),
                              StatusPill(
                                label: item.listingStatus ?? 'unlisted',
                              ),
                              StatusPill(
                                label: item.hasEditorialImage
                                    ? 'Photo attached'
                                    : 'No photo',
                              ),
                              StatusPill(
                                label: item.customerVisible
                                    ? 'Visible'
                                    : 'Hidden',
                              ),
                              StatusPill(
                                label: item.qrReady ? 'QR ready' : 'QR pending',
                              ),
                              if (item.claimPacketReady)
                                const StatusPill(label: 'Packet ready'),
                              if (item.buyable)
                                const StatusPill(label: 'Buyable'),
                              if (photoBusy)
                                const StatusPill(label: 'Updating'),
                            ],
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          item.askingPriceCents == null
                              ? 'n/a'
                              : formatCurrency(item.askingPriceCents!),
                        ),
                      ),
                      DataCell(Text(formatAdminDate(item.createdAt))),
                      DataCell(
                        SizedBox(
                          width: 300,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: <Widget>[
                              if (!item.hasAuthenticityRecord)
                                FilledButton.tonal(
                                  style: CatalogPanel._compactActionStyle,
                                  onPressed: () =>
                                      widget.onCreateAuthenticityRecord(item),
                                  child: const Text('Link'),
                                ),
                              if (!item.hasEditorialImage)
                                FilledButton.tonalIcon(
                                  style: CatalogPanel._compactActionStyle,
                                  onPressed: photoBusy
                                      ? null
                                      : () =>
                                            widget.onUploadInventoryImage(item),
                                  icon: const Icon(
                                    Icons.add_a_photo_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Upload'),
                                ),
                              if (item.hasEditorialImage)
                                FilledButton.tonalIcon(
                                  style: CatalogPanel._compactActionStyle,
                                  onPressed: photoBusy
                                      ? null
                                      : () =>
                                            widget.onRemoveInventoryImage(item),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                  ),
                                  label: const Text('Remove'),
                                ),
                              if (item.hasAuthenticityRecord &&
                                  item.listingStatus == null)
                                FilledButton.tonal(
                                  style: CatalogPanel._compactActionStyle,
                                  onPressed: () => widget.onUpsertListing(item),
                                  child: const Text('List'),
                                ),
                              if (item.hasAuthenticityRecord &&
                                  item.listingStatus != null &&
                                  item.listingStatus != 'active')
                                FilledButton.tonal(
                                  style: CatalogPanel._compactActionStyle,
                                  onPressed: () => widget.onUpsertListing(item),
                                  child: const Text('Publish'),
                                ),
                              if (item.claimCodeRevealState == 'ready')
                                FilledButton.tonal(
                                  style: CatalogPanel._compactActionStyle,
                                  onPressed: () =>
                                      widget.onRevealClaimCode(item),
                                  child: const Text('Reveal'),
                                ),
                              if (item.claimPacketReady)
                                FilledButton.tonal(
                                  style: CatalogPanel._compactActionStyle,
                                  onPressed: () =>
                                      widget.onGenerateClaimPacket(item),
                                  child: const Text('Packet'),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
      ],
    );
  }

  List<AdminInventoryRecord> _filteredInventory() {
    final List<AdminInventoryRecord> filtered = widget.inventory.where((
      AdminInventoryRecord item,
    ) {
      final bool matchesQuery =
          _searchQuery.isEmpty ||
          <String>[
            item.serialNumber,
            item.artistName,
            item.artworkTitle,
            item.garmentName,
            item.ownerDisplayLabel,
            item.itemState,
          ].join(' ').toLowerCase().contains(_searchQuery);
      final bool matchesArtist =
          _artistFilter == _allArtists || item.artistName == _artistFilter;
      final bool matchesOwner =
          _ownerFilter == _allOwners || item.ownerDisplayLabel == _ownerFilter;
      final bool matchesState =
          _stateFilter == _allStates || item.itemState == _stateFilter;
      return matchesQuery && matchesArtist && matchesOwner && matchesState;
    }).toList();

    filtered.sort((AdminInventoryRecord a, AdminInventoryRecord b) {
      return switch (_sortOption) {
        _InventorySortOption.newestFirst => b.createdAt.compareTo(a.createdAt),
        _InventorySortOption.oldestFirst => a.createdAt.compareTo(b.createdAt),
        _InventorySortOption.serialAz => a.serialNumber.compareTo(
          b.serialNumber,
        ),
        _InventorySortOption.artistAz => a.artistName.compareTo(b.artistName),
        _InventorySortOption.ownerAz => a.ownerDisplayLabel.compareTo(
          b.ownerDisplayLabel,
        ),
      };
    });
    return filtered;
  }

  String _sortLabel(_InventorySortOption option) {
    return switch (option) {
      _InventorySortOption.newestFirst => 'Newest first',
      _InventorySortOption.oldestFirst => 'Oldest first',
      _InventorySortOption.serialAz => 'Serial A-Z',
      _InventorySortOption.artistAz => 'Artist A-Z',
      _InventorySortOption.ownerAz => 'Owner A-Z',
    };
  }
}

enum _InventorySortOption {
  newestFirst,
  oldestFirst,
  serialAz,
  artistAz,
  ownerAz,
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.optionLabel,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final String Function(String value) optionLabel;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: options
            .map(
              (String option) => DropdownMenuItem<String>(
                value: option,
                child: Text(
                  optionLabel(option),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: (String? nextValue) {
          if (nextValue != null) {
            onChanged(nextValue);
          }
        },
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: const Color(0xFF23201A),
        border: Border.all(color: Colors.white10),
      ),
      child: Text(label, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
