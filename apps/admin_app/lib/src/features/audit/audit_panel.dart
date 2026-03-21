import 'dart:convert';

import 'package:domain/domain.dart';
import 'package:flutter/material.dart';

import '../../widgets/admin_shared.dart';

class AuditPanel extends StatelessWidget {
  const AuditPanel({required this.audits, super.key});

  final List<AdminAuditRecord> audits;

  @override
  Widget build(BuildContext context) {
    return TableSection(
      title: 'Audit log viewer',
      subtitle:
          'Claims, ownership changes, moderation, payment transfer, and admin interventions.',
      child: audits.isEmpty
          ? const EmptyState(message: 'No audit events are available yet.')
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const <DataColumn>[
                  DataColumn(label: Text('Time')),
                  DataColumn(label: Text('Actor')),
                  DataColumn(label: Text('Entity')),
                  DataColumn(label: Text('Action')),
                  DataColumn(label: Text('Payload')),
                ],
                rows: audits.map((AdminAuditRecord audit) {
                  return DataRow(
                    cells: <DataCell>[
                      DataCell(Text(formatAdminDate(audit.createdAt))),
                      DataCell(
                        Text(
                          audit.actorDisplayName ??
                              audit.actorUsername ??
                              'system',
                        ),
                      ),
                      DataCell(
                        Text(
                          '${audit.entityType}${audit.entityId == null ? '' : ' • ${audit.entityId!.substring(0, 8)}'}',
                        ),
                      ),
                      DataCell(Text(audit.action)),
                      DataCell(
                        SizedBox(
                          width: 420,
                          child: SelectableText(
                            const JsonEncoder.withIndent(
                              '  ',
                            ).convert(audit.payload),
                            style: Theme.of(context).textTheme.bodySmall,
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
