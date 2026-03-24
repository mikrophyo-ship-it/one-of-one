import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:utils/utils.dart';

import '../../widgets/admin_shared.dart';

class FinancePanel extends StatelessWidget {
  const FinancePanel({required this.finance, super.key});

  final List<AdminFinanceRecord> finance;

  @override
  Widget build(BuildContext context) {
    return TableSection(
      title: 'Finance visibility',
      subtitle:
          'Audit payment, shipment, payout, royalty, and platform fee progression at the order level.',
      child: finance.isEmpty
          ? const EmptyState(message: 'No finance records are available yet.')
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const <DataColumn>[
                  DataColumn(label: Text('Order')),
                  DataColumn(label: Text('Payment')),
                  DataColumn(label: Text('Shipment')),
                  DataColumn(label: Text('Seller payout')),
                  DataColumn(label: Text('Royalty')),
                  DataColumn(label: Text('Platform fee')),
                  DataColumn(label: Text('Total')),
                ],
                rows: finance.map((AdminFinanceRecord row) {
                  return DataRow(
                    cells: <DataCell>[
                      DataCell(Text(row.orderId.substring(0, 8))),
                      DataCell(StatusPill(label: row.paymentStatus)),
                      DataCell(StatusPill(label: row.shipmentStatus)),
                      DataCell(StatusPill(label: row.sellerPayoutStatus)),
                      DataCell(StatusPill(label: row.royaltyStatus)),
                      DataCell(StatusPill(label: row.platformFeeStatus)),
                      DataCell(Text(formatCurrency(row.totalCents))),
                    ],
                  );
                }).toList(),
              ),
            ),
    );
  }
}
