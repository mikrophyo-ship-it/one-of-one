import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:utils/utils.dart';

import '../../widgets/admin_shared.dart';

class OrdersPanel extends StatelessWidget {
  const OrdersPanel({required this.orders, super.key});

  final List<AdminOrderRecord> orders;

  @override
  Widget build(BuildContext context) {
    return TableSection(
      title: 'Orders',
      subtitle:
          'Primary resale order state, payment capture, and downstream ledger readiness.',
      child: orders.isEmpty
          ? const EmptyState(message: 'No orders are available yet.')
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const <DataColumn>[
                  DataColumn(label: Text('Order')),
                  DataColumn(label: Text('Item')),
                  DataColumn(label: Text('Buyer / seller')),
                  DataColumn(label: Text('Order status')),
                  DataColumn(label: Text('Payment')),
                  DataColumn(label: Text('Ledgers')),
                  DataColumn(label: Text('Total')),
                  DataColumn(label: Text('Created')),
                ],
                rows: orders.map((AdminOrderRecord order) {
                  return DataRow(
                    cells: <DataCell>[
                      DataCell(Text(order.orderId.substring(0, 8))),
                      DataCell(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Text(order.serialNumber),
                            Text(
                              '${order.artistName} • ${order.artworkTitle}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      DataCell(
                        Text(
                          '${order.buyerDisplayName ?? 'Buyer'} / ${order.sellerDisplayName ?? 'Seller'}',
                        ),
                      ),
                      DataCell(StatusPill(label: order.orderStatus)),
                      DataCell(
                        Text(
                          '${order.paymentStatus ?? 'none'}${order.paymentProvider == null ? '' : ' • ${order.paymentProvider}'}',
                        ),
                      ),
                      DataCell(
                        Text(
                          'Seller ${order.sellerPayoutStatus ?? 'n/a'} • Royalty ${order.royaltyStatus ?? 'n/a'} • Fee ${order.platformFeeStatus ?? 'n/a'}',
                        ),
                      ),
                      DataCell(Text(formatCurrency(order.totalCents))),
                      DataCell(Text(formatAdminDate(order.createdAt))),
                    ],
                  );
                }).toList(),
              ),
            ),
    );
  }
}
