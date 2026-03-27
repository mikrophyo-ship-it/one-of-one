import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:utils/utils.dart';

import '../../widgets/admin_shared.dart';

class ListingsPanel extends StatelessWidget {
  const ListingsPanel({
    required this.listings,
    required this.onModerateListing,
    required this.onFlagItem,
    super.key,
  });

  final List<AdminListingRecord> listings;
  final Future<void> Function(AdminListingRecord listing, String action)
  onModerateListing;
  final Future<void> Function(String itemId, String targetState, String title)
  onFlagItem;

  @override
  Widget build(BuildContext context) {
    return TableSection(
      title: 'Listing moderation',
      subtitle:
          'Suppress, restore, cancel, freeze, or stolen-flag listings without bypassing server ownership rules.',
      child: listings.isEmpty
          ? const EmptyState(message: 'No listings are available yet.')
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                horizontalMargin: 12,
                columnSpacing: 16,
                dataRowMinHeight: 88,
                dataRowMaxHeight: 120,
                columns: const <DataColumn>[
                  DataColumn(label: Text('Serial')),
                  DataColumn(label: Text('Artist / work')),
                  DataColumn(label: Text('Seller')),
                  DataColumn(label: Text('Price')),
                  DataColumn(label: Text('Listing')),
                  DataColumn(label: Text('Item state')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: listings.map((AdminListingRecord listing) {
                  return DataRow(
                    cells: <DataCell>[
                      DataCell(Text(listing.serialNumber)),
                      DataCell(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Text(listing.artistName),
                            Text(
                              listing.artworkTitle,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      DataCell(
                        Text(
                          listing.sellerDisplayName ??
                              listing.sellerUserId.substring(0, 8),
                        ),
                      ),
                      DataCell(Text(formatCurrency(listing.askingPriceCents))),
                      DataCell(StatusPill(label: listing.listingStatus)),
                      DataCell(StatusPill(label: listing.itemState)),
                      DataCell(
                        SizedBox(
                          width: 360,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: <Widget>[
                              OutlinedButton(
                                onPressed: () =>
                                    onModerateListing(listing, 'block'),
                                child: const Text('Block'),
                              ),
                              OutlinedButton(
                                onPressed:
                                    listing.listingStatus == 'blocked_by_admin'
                                    ? () =>
                                          onModerateListing(listing, 'restore')
                                    : null,
                                child: const Text('Restore'),
                              ),
                              OutlinedButton(
                                onPressed: () =>
                                    onModerateListing(listing, 'cancel'),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => onFlagItem(
                                  listing.itemId,
                                  'frozen',
                                  'Freeze item',
                                ),
                                child: const Text('Freeze'),
                              ),
                              TextButton(
                                onPressed: () => onFlagItem(
                                  listing.itemId,
                                  'stolen_flagged',
                                  'Flag stolen item',
                                ),
                                child: const Text('Flag stolen'),
                              ),
                              TextButton(
                                onPressed: () => onFlagItem(
                                  listing.itemId,
                                  'claimed',
                                  'Release to claimed state',
                                ),
                                child: const Text('Release'),
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
    );
  }
}
