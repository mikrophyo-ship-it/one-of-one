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
    super.key,
  });

  final List<AdminArtistRecord> artists;
  final List<AdminArtworkRecord> artworks;
  final List<AdminInventoryRecord> inventory;
  final List<AdminGarmentProductRecord> garmentProducts;
  final VoidCallback onCreateArtist;
  final VoidCallback onCreateArtwork;
  final VoidCallback onCreateInventory;
  final Future<void> Function(AdminInventoryRecord item) onCreateAuthenticityRecord;
  final Future<void> Function(AdminInventoryRecord item) onUpsertListing;
  final Future<void> Function(AdminInventoryRecord item) onRevealClaimCode;
  final Future<void> Function(AdminInventoryRecord item) onGenerateClaimPacket;
  final Future<void> Function(AdminInventoryRecord item) onUploadInventoryImage;

  static final ButtonStyle _compactActionStyle = FilledButton.styleFrom(
    minimumSize: const Size(0, 34),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
  );

  @override
  Widget build(BuildContext context) {
    final ScrollController inventoryScrollController = ScrollController();
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
                            StatusPill(
                              label: artist.isActive ? 'active' : 'inactive',
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
              : Scrollbar(
                  controller: inventoryScrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: inventoryScrollController,
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      horizontalMargin: 12,
                      columnSpacing: 16,
                      dataRowMinHeight: 64,
                      dataRowMaxHeight: 96,
                      columns: const <DataColumn>[
                        DataColumn(label: Text('Serial')),
                        DataColumn(label: Text('Artist / work')),
                        DataColumn(label: Text('Garment')),
                        DataColumn(label: Text('State')),
                        DataColumn(label: Text('Owner')),
                        DataColumn(label: Text('Auth')),
                        DataColumn(label: Text('Listing')),
                        DataColumn(label: Text('Price')),
                        DataColumn(label: Text('Visible')),
                        DataColumn(label: Text('Buy')),
                        DataColumn(label: Text('QR')),
                        DataColumn(label: Text('Claim')),
                        DataColumn(label: Text('Packet')),
                        DataColumn(label: Text('Actions')),
                      ],
                      rows: inventory.map((AdminInventoryRecord item) {
                        return DataRow(
                          cells: <DataCell>[
                            DataCell(Text(item.serialNumber)),
                            DataCell(
                              SizedBox(
                                width: 180,
                                child: Text(
                                  '${item.artistName} / ${item.artworkTitle}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            DataCell(
                              SizedBox(
                                width: 120,
                                child: Text(
                                  item.garmentName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            DataCell(StatusPill(label: item.itemState)),
                            DataCell(
                              SizedBox(
                                width: 120,
                                child: Text(
                                  item.ownerDisplayLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            DataCell(
                              StatusPill(
                                label: item.hasAuthenticityRecord
                                    ? (item.authenticityStatus ?? 'linked')
                                    : 'missing',
                              ),
                            ),
                            DataCell(
                              item.listingStatus == null
                                  ? const Text('None')
                                  : StatusPill(label: item.listingStatus!),
                            ),
                            DataCell(
                              Text(
                                item.askingPriceCents == null
                                    ? 'n/a'
                                    : formatCurrency(item.askingPriceCents!),
                              ),
                            ),
                            DataCell(
                              StatusPill(
                                label: item.customerVisible ? 'yes' : 'no',
                              ),
                            ),
                            DataCell(
                              StatusPill(label: item.buyable ? 'yes' : 'no'),
                            ),
                            DataCell(
                              StatusPill(label: item.qrReady ? 'ready' : 'no'),
                            ),
                            DataCell(
                              StatusPill(label: item.claimCodeRevealState),
                            ),
                            DataCell(
                              StatusPill(
                                label: item.claimPacketReady ? 'ready' : 'hold',
                              ),
                            ),
                            DataCell(
                              SizedBox(
                                width: 320,
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: <Widget>[
                                    if (!item.hasAuthenticityRecord)
                                      FilledButton.tonal(
                                        style: _compactActionStyle,
                                        onPressed: () =>
                                            onCreateAuthenticityRecord(item),
                                        child: const Text('Link'),
                                      ),
                                    IconButton(
                                      tooltip: 'Upload editorial photo',
                                      onPressed: () => onUploadInventoryImage(item),
                                      icon: const Icon(Icons.add_a_photo_outlined),
                                    ),
                                    if (item.hasAuthenticityRecord &&
                                        item.listingStatus == null)
                                      FilledButton.tonal(
                                        style: _compactActionStyle,
                                        onPressed: () => onUpsertListing(item),
                                        child: const Text('List'),
                                      ),
                                    if (item.hasAuthenticityRecord &&
                                        item.listingStatus != null &&
                                        item.listingStatus != 'active')
                                      FilledButton.tonal(
                                        style: _compactActionStyle,
                                        onPressed: () => onUpsertListing(item),
                                        child: const Text('Publish'),
                                      ),
                                    if (item.claimCodeRevealState == 'ready')
                                      FilledButton.tonal(
                                        style: _compactActionStyle,
                                        onPressed: () => onRevealClaimCode(item),
                                        child: const Text('Reveal'),
                                      ),
                                    if (item.claimPacketReady)
                                      FilledButton.tonal(
                                        style: _compactActionStyle,
                                        onPressed: () => onGenerateClaimPacket(item),
                                        child: const Text('Packet'),
                                      ),
                                    if (item.listingStatus == 'active')
                                      const StatusPill(label: 'live'),
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
        ),
      ],
    );
  }
}
