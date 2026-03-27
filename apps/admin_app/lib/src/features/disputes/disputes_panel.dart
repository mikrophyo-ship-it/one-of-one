import 'package:domain/domain.dart';
import 'package:flutter/material.dart';

import '../../widgets/admin_shared.dart';

class DisputesPanel extends StatelessWidget {
  const DisputesPanel({
    required this.disputes,
    required this.onUpdateDispute,
    required this.onFlagItem,
    super.key,
  });

  final List<AdminDisputeRecord> disputes;
  final Future<void> Function(AdminDisputeRecord dispute) onUpdateDispute;
  final Future<void> Function(String itemId, String targetState, String title)
  onFlagItem;

  @override
  Widget build(BuildContext context) {
    return TableSection(
      title: 'Disputes',
      subtitle:
          'Review disputes, move them through resolution, and enforce freeze or stolen controls at the backend.',
      child: disputes.isEmpty
          ? const EmptyState(message: 'No disputes are available yet.')
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                dataRowMinHeight: 88,
                dataRowMaxHeight: 120,
                columns: const <DataColumn>[
                  DataColumn(label: Text('Item')),
                  DataColumn(label: Text('Reason')),
                  DataColumn(label: Text('Reporter')),
                  DataColumn(label: Text('Dispute')),
                  DataColumn(label: Text('Listing')),
                  DataColumn(label: Text('Created')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: disputes.map((AdminDisputeRecord dispute) {
                  return DataRow(
                    cells: <DataCell>[
                      DataCell(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Text(dispute.serialNumber),
                            Text(
                              '${dispute.artistName} • ${dispute.artworkTitle}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 220,
                          child: Text(
                            dispute.details == null || dispute.details!.isEmpty
                                ? dispute.reason
                                : '${dispute.reason}: ${dispute.details}',
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          dispute.reporterDisplayName ??
                              dispute.reportedByUserId.substring(0, 8),
                        ),
                      ),
                      DataCell(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            StatusPill(label: dispute.disputeStatus),
                            const SizedBox(height: 6),
                            StatusPill(label: dispute.itemState),
                          ],
                        ),
                      ),
                      DataCell(Text(dispute.latestListingStatus ?? 'none')),
                      DataCell(Text(formatAdminDate(dispute.createdAt))),
                      DataCell(
                        SizedBox(
                          width: 320,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: <Widget>[
                              FilledButton.tonal(
                                onPressed: () => onUpdateDispute(dispute),
                                child: const Text('Update'),
                              ),
                              TextButton(
                                onPressed: () => onFlagItem(
                                  dispute.itemId,
                                  'frozen',
                                  'Freeze item',
                                ),
                                child: const Text('Freeze'),
                              ),
                              TextButton(
                                onPressed: () => onFlagItem(
                                  dispute.itemId,
                                  'stolen_flagged',
                                  'Flag stolen item',
                                ),
                                child: const Text('Flag stolen'),
                              ),
                              TextButton(
                                onPressed: () => onFlagItem(
                                  dispute.itemId,
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
