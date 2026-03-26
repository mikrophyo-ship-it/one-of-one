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
    super.key,
  });

  final List<AdminArtistRecord> artists;
  final List<AdminArtworkRecord> artworks;
  final List<AdminInventoryRecord> inventory;
  final List<AdminGarmentProductRecord> garmentProducts;
  final VoidCallback onCreateArtist;
  final VoidCallback onCreateArtwork;
  final VoidCallback onCreateInventory;

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
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const <DataColumn>[
                      DataColumn(label: Text('Serial')),
                      DataColumn(label: Text('Artist / work')),
                      DataColumn(label: Text('Garment')),
                      DataColumn(label: Text('State')),
                      DataColumn(label: Text('Owner')),
                    ],
                    rows: inventory.map((AdminInventoryRecord item) {
                      return DataRow(
                        cells: <DataCell>[
                          DataCell(Text(item.serialNumber)),
                          DataCell(Text('${item.artistName} / ${item.artworkTitle}')),
                          DataCell(Text(item.garmentName)),
                          DataCell(StatusPill(label: item.itemState)),
                          DataCell(Text(item.ownerDisplayLabel)),
                        ],
                      );
                    }).toList(),
                  ),
                ),
        ),
      ],
    );
  }
}
