import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:utils/utils.dart';

import '../../widgets/admin_shared.dart';

class OverviewPanel extends StatelessWidget {
  const OverviewPanel({required this.snapshot, super.key});

  final AdminOperationsSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final AdminDashboardSnapshot dashboard =
        snapshot?.dashboard ??
        const AdminDashboardSnapshot(
          openDisputes: 0,
          activeListings: 0,
          paymentPendingOrders: 0,
          deliveryPendingOrders: 0,
          payoutPendingOrders: 0,
          refundPendingOrders: 0,
          grossSalesCents: 0,
          royaltyCents: 0,
          platformFeeCents: 0,
          frozenItems: 0,
          stolenItems: 0,
        );

    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text(
          'Operational overview',
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            MetricCard(
              title: 'Open disputes',
              value: '${dashboard.openDisputes}',
            ),
            MetricCard(
              title: 'Active listings',
              value: '${dashboard.activeListings}',
            ),
            MetricCard(
              title: 'Payment pending',
              value: '${dashboard.paymentPendingOrders}',
            ),
            MetricCard(
              title: 'Delivery pending',
              value: '${dashboard.deliveryPendingOrders}',
            ),
            MetricCard(
              title: 'Payout pending',
              value: '${dashboard.payoutPendingOrders}',
            ),
            MetricCard(
              title: 'Refund pending',
              value: '${dashboard.refundPendingOrders}',
            ),
            MetricCard(
              title: 'Gross sales',
              value: formatCurrency(dashboard.grossSalesCents),
            ),
            MetricCard(
              title: 'Artist royalties',
              value: formatCurrency(dashboard.royaltyCents),
            ),
            MetricCard(
              title: 'Platform fees',
              value: formatCurrency(dashboard.platformFeeCents),
            ),
            MetricCard(
              title: 'Frozen items',
              value: '${dashboard.frozenItems}',
            ),
            MetricCard(
              title: 'Stolen flagged',
              value: '${dashboard.stolenItems}',
            ),
          ],
        ),
        const SizedBox(height: 20),
        const SectionCard(
          title: 'Marketplace guardrails',
          child: Text(
            'Ownership stays server-authoritative. Disputed, frozen, and stolen items cannot be claimed, listed, sold, or transferred. Listing moderation and dispute controls write audit-backed server actions rather than local overrides.',
          ),
        ),
      ],
    );
  }
}
