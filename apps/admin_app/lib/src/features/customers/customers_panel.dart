import 'package:domain/domain.dart';
import 'package:flutter/material.dart';

import '../../widgets/admin_shared.dart';

class CustomersPanel extends StatelessWidget {
  const CustomersPanel({
    required this.customers,
    required this.onSetRole,
    super.key,
  });

  final List<AdminCustomerRecord> customers;
  final Future<void> Function(AdminCustomerRecord customer, String role)
  onSetRole;

  @override
  Widget build(BuildContext context) {
    return TableSection(
      title: 'Customers',
      subtitle: 'Profile, role, dispute exposure, and owned-item overview.',
      child: customers.isEmpty
          ? const EmptyState(message: 'No customer profiles are available yet.')
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const <DataColumn>[
                  DataColumn(label: Text('Collector')),
                  DataColumn(label: Text('Role')),
                  DataColumn(label: Text('Owned')),
                  DataColumn(label: Text('Open disputes')),
                  DataColumn(label: Text('Buy orders')),
                  DataColumn(label: Text('Sell orders')),
                  DataColumn(label: Text('Last activity')),
                ],
                rows: customers.map((AdminCustomerRecord customer) {
                  return DataRow(
                    cells: <DataCell>[
                      DataCell(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Text(customer.displayName),
                            Text(
                              customer.username == null
                                  ? customer.userId.substring(0, 8)
                                  : '@${customer.username}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      DataCell(
                        PopupMenuButton<String>(
                          onSelected: (String value) =>
                              onSetRole(customer, value),
                          itemBuilder: (BuildContext context) {
                            return const <String>[
                              'customer',
                              'support',
                              'artist_manager',
                              'admin',
                              'owner',
                            ].map((String value) {
                              return PopupMenuItem<String>(
                                value: value,
                                child: Text(value),
                              );
                            }).toList();
                          },
                          child: StatusPill(label: customer.role),
                        ),
                      ),
                      DataCell(Text('${customer.ownedItemCount}')),
                      DataCell(Text('${customer.openDisputeCount}')),
                      DataCell(Text('${customer.buyOrderCount}')),
                      DataCell(Text('${customer.sellOrderCount}')),
                      DataCell(
                        Text(
                          formatAdminDate(
                            customer.lastActivityAt ?? customer.createdAt,
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
