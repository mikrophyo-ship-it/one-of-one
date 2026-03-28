import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:utils/utils.dart';

import '../../widgets/admin_shared.dart';

class OrdersPanel extends StatefulWidget {
  const OrdersPanel({
    required this.orders,
    required this.onReviewManualPayment,
    super.key,
  });

  final List<AdminOrderRecord> orders;
  final Future<void> Function(AdminOrderRecord order, String action)
      onReviewManualPayment;

  @override
  State<OrdersPanel> createState() => _OrdersPanelState();
}

class _OrdersPanelState extends State<OrdersPanel> {
  String _filter = 'needs_review';

  @override
  Widget build(BuildContext context) {
    final int pendingReviewCount = widget.orders.where(_needsReview).length;
    final List<AdminOrderRecord> filteredOrders = widget.orders.where((
      AdminOrderRecord order,
    ) {
      return switch (_filter) {
        'needs_review' => _needsReview(order),
        'resubmission' =>
          order.manualPaymentReviewStatus == 'resubmission_requested',
        'approved' => order.orderStatus == 'paid',
        'rejected' =>
          order.manualPaymentReviewStatus == 'rejected' ||
              order.orderStatus == 'failed',
        'cancelled' => order.orderStatus == 'cancelled',
        'closed' =>
          order.orderStatus == 'cancelled' ||
              order.orderStatus == 'failed' ||
              order.orderStatus == 'fulfilled',
        _ => true,
      };
    }).toList();

    return TableSection(
      title: 'Orders',
      subtitle:
          'Primary resale order state, payment proof review, shipment progress, and downstream ledger readiness. Pending manual reviews: $pendingReviewCount.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final MapEntry<String, String> filter in const <MapEntry<String, String>>[
                MapEntry<String, String>('all', 'All orders'),
                MapEntry<String, String>('needs_review', 'Needs review'),
                MapEntry<String, String>('resubmission', 'Resubmission'),
                MapEntry<String, String>('approved', 'Approved / ready'),
                MapEntry<String, String>('rejected', 'Rejected'),
                MapEntry<String, String>('cancelled', 'Cancelled'),
                MapEntry<String, String>('closed', 'Closed'),
              ])
                ChoiceChip(
                  label: Text(filter.value),
                  selected: _filter == filter.key,
                  onSelected: (_) {
                    setState(() {
                      _filter = filter.key;
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (filteredOrders.isEmpty)
            const EmptyState(message: 'No orders match the current filter.')
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const <DataColumn>[
                  DataColumn(label: Text('Order')),
                  DataColumn(label: Text('Item')),
                  DataColumn(label: Text('Buyer / seller')),
                  DataColumn(label: Text('Order status')),
                  DataColumn(label: Text('Payment')),
                  DataColumn(label: Text('Manual review')),
                  DataColumn(label: Text('Shipment')),
                  DataColumn(label: Text('Total')),
                  DataColumn(label: Text('Created')),
                ],
                rows: filteredOrders.map((AdminOrderRecord order) {
                  final bool hasProof = order.paymentProofUrl != null;
                  final List<_OrderAction> actions = _actionsFor(order);
                  return DataRow(
                    cells: <DataCell>[
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                order.orderId.length <= 8
                                    ? order.orderId
                                    : order.orderId.substring(0, 8),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (actions.isEmpty)
                              Text(
                                _terminalLabel(order),
                                style: Theme.of(context).textTheme.bodySmall,
                              )
                            else
                              PopupMenuButton<_OrderAction>(
                                key: ValueKey<String>(
                                  'order-actions-${order.orderId}',
                                ),
                                tooltip: 'Order actions',
                                icon: const Icon(Icons.more_horiz, size: 18),
                                onSelected: (_OrderAction action) =>
                                    _handleAction(context, order, action),
                                itemBuilder: (BuildContext context) {
                                  return actions.map((_OrderAction action) {
                                    return PopupMenuItem<_OrderAction>(
                                      value: action,
                                      child: Text(action.label),
                                    );
                                  }).toList();
                                },
                              ),
                          ],
                        ),
                      ),
                      DataCell(
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Text(order.serialNumber),
                            Text(
                              '${order.artistName} / ${order.artworkTitle}',
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
                          '${order.paymentStatus ?? 'none'}${order.paymentProvider == null ? '' : ' / ${order.paymentProvider}'}',
                        ),
                      ),
                      DataCell(
                        Text(
                          [
                            order.manualPaymentReviewStatus ?? 'none',
                            if (order.submittedAmountCents != null)
                              'Submitted ${formatCurrency(order.submittedAmountCents!)}',
                            hasProof ? 'Proof attached' : 'Proof pending',
                          ].join(' | '),
                        ),
                      ),
                      DataCell(
                        Text(
                          '${order.shipmentStatus ?? 'none'}${order.shipmentCarrier == null ? '' : ' / ${order.shipmentCarrier}'}${order.trackingNumber == null ? '' : ' / ${order.trackingNumber}'}',
                        ),
                      ),
                      DataCell(Text(formatCurrency(order.totalCents))),
                      DataCell(Text(formatAdminDate(order.createdAt))),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  List<_OrderAction> _actionsFor(AdminOrderRecord order) {
    final List<_OrderAction> actions = <_OrderAction>[_OrderAction.viewDetails];
    if (order.paymentProofUrl != null) {
      actions.add(_OrderAction.viewProof);
    }
    if (_canReview(order)) {
      actions.addAll(const <_OrderAction>[
        _OrderAction.approvePayment,
        _OrderAction.rejectPayment,
        _OrderAction.requestResubmission,
      ]);
    }
    if (_canCancel(order)) {
      actions.add(_OrderAction.cancelOrder);
    }
    return actions;
  }

  Future<void> _handleAction(
    BuildContext context,
    AdminOrderRecord order,
    _OrderAction action,
  ) async {
    switch (action) {
      case _OrderAction.viewDetails:
        await _openOrderDetailsDialog(context, order);
      case _OrderAction.viewProof:
        await _openProofDialog(context, order);
      case _OrderAction.approvePayment:
        await widget.onReviewManualPayment(order, 'approve');
      case _OrderAction.rejectPayment:
        await widget.onReviewManualPayment(order, 'reject');
      case _OrderAction.requestResubmission:
        await widget.onReviewManualPayment(order, 'request_resubmission');
      case _OrderAction.cancelOrder:
        await widget.onReviewManualPayment(order, 'cancel');
    }
  }

  Future<void> _openOrderDetailsDialog(
    BuildContext context,
    AdminOrderRecord order,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1712),
          title: Text('Order ${order.serialNumber}'),
          content: SizedBox(
            width: 760,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _OrderDetailBlock(
                    title: 'Order',
                    rows: <_OrderDetailRow>[
                      _OrderDetailRow('Order id', order.orderId),
                      _OrderDetailRow('Order status', order.orderStatus),
                      _OrderDetailRow(
                        'Manual review',
                        order.manualPaymentReviewStatus ?? 'none',
                      ),
                      _OrderDetailRow(
                        'Payment',
                        '${order.paymentStatus ?? 'none'}${order.paymentProvider == null ? '' : ' / ${order.paymentProvider}'}',
                      ),
                      _OrderDetailRow('Created', formatAdminDate(order.createdAt)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _OrderDetailBlock(
                    title: 'Collectible',
                    rows: <_OrderDetailRow>[
                      _OrderDetailRow('Item id', order.itemId),
                      _OrderDetailRow('Serial', order.serialNumber),
                      _OrderDetailRow('Artist', order.artistName),
                      _OrderDetailRow('Artwork', order.artworkTitle),
                      _OrderDetailRow('Garment', order.garmentName),
                      _OrderDetailRow('Item state', order.itemState),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _OrderDetailBlock(
                    title: 'Participants',
                    rows: <_OrderDetailRow>[
                      _OrderDetailRow(
                        'Buyer',
                        order.buyerDisplayName ?? 'Buyer not available',
                      ),
                      _OrderDetailRow(
                        'Seller',
                        order.sellerDisplayName ?? 'Seller not available',
                      ),
                      _OrderDetailRow(
                        'Payer',
                        order.payerName ?? 'No payer submitted',
                      ),
                      _OrderDetailRow(
                        'Payer phone',
                        order.payerPhone ?? 'No phone submitted',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _OrderDetailBlock(
                    title: 'Payment proof',
                    rows: <_OrderDetailRow>[
                      _OrderDetailRow(
                        'Expected amount',
                        formatCurrency(order.totalCents),
                      ),
                      _OrderDetailRow(
                        'Submitted amount',
                        order.submittedAmountCents == null
                            ? 'n/a'
                            : formatCurrency(order.submittedAmountCents!),
                      ),
                      _OrderDetailRow(
                        'Method',
                        order.manualPaymentMethod ?? 'n/a',
                      ),
                      _OrderDetailRow(
                        'Transaction reference',
                        order.transactionReference ??
                            order.paymentProvider ??
                            'n/a',
                      ),
                      _OrderDetailRow(
                        'Paid at',
                        order.paidAt == null
                            ? 'n/a'
                            : formatAdminDate(order.paidAt!),
                      ),
                      _OrderDetailRow(
                        'Proof status',
                        order.paymentProofUrl == null
                            ? 'No proof uploaded'
                            : 'Proof available',
                      ),
                    ],
                    footer: order.paymentProofUrl == null
                        ? const Text('No payment screenshot has been uploaded.')
                        : Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: () => _openProofDialog(context, order),
                              icon: const Icon(Icons.image_outlined),
                              label: const Text('View proof'),
                            ),
                          ),
                  ),
                  if (order.paymentReviewNote != null ||
                      order.reviewedByDisplayName != null) ...<Widget>[
                    const SizedBox(height: 16),
                    _OrderDetailBlock(
                      title: 'Resolution',
                      rows: <_OrderDetailRow>[
                        _OrderDetailRow(
                          'Latest note',
                          order.paymentReviewNote ?? 'No note recorded',
                        ),
                        _OrderDetailRow(
                          'Reviewed by',
                          order.reviewedByDisplayName ?? 'n/a',
                        ),
                        _OrderDetailRow(
                          'Reviewed at',
                          order.reviewedAt == null
                              ? 'n/a'
                              : formatAdminDate(order.reviewedAt!),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            if (order.paymentProofUrl != null)
              OutlinedButton(
                onPressed: () => _openProofDialog(context, order),
                child: const Text('View proof'),
              ),
            if (_canReview(order))
              OutlinedButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await widget.onReviewManualPayment(
                    order,
                    'request_resubmission',
                  );
                },
                child: const Text('Request resubmission'),
              ),
            if (_canReview(order))
              OutlinedButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await widget.onReviewManualPayment(order, 'reject');
                },
                child: const Text('Reject'),
              ),
            if (_canCancel(order))
              OutlinedButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await widget.onReviewManualPayment(order, 'cancel');
                },
                child: const Text('Cancel order'),
              ),
            if (_canReview(order))
              FilledButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await widget.onReviewManualPayment(order, 'approve');
                },
                child: const Text('Approve payment'),
              ),
          ],
        );
      },
    );
  }

  Future<void> _openProofDialog(
    BuildContext context,
    AdminOrderRecord order,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1712),
          title: Text('Payment proof ${order.serialNumber}'),
          content: SizedBox(
            width: 760,
            child: order.paymentProofUrl == null
                ? const SizedBox(
                    height: 220,
                    child: Center(child: Text('No payment proof available yet.')),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(
                          order.paymentProofUrl!,
                          height: 360,
                          width: double.infinity,
                          fit: BoxFit.contain,
                          errorBuilder: (
                            BuildContext context,
                            Object error,
                            StackTrace? stackTrace,
                          ) {
                            return Container(
                              height: 240,
                              width: double.infinity,
                              alignment: Alignment.center,
                              color: const Color(0xFF241E17),
                              child: const Text(
                                'Payment proof preview unavailable',
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Submitted amount: ${order.submittedAmountCents == null ? 'n/a' : formatCurrency(order.submittedAmountCents!)}',
                      ),
                      Text('Method: ${order.manualPaymentMethod ?? 'n/a'}'),
                      Text('Payer: ${order.payerName ?? 'n/a'}'),
                      Text('Phone: ${order.payerPhone ?? 'n/a'}'),
                      Text(
                        'Reference: ${order.transactionReference ?? order.paymentProvider ?? 'n/a'}',
                      ),
                    ],
                  ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  bool _needsReview(AdminOrderRecord order) {
    return order.orderStatus == 'payment_pending' &&
        (order.manualPaymentReviewStatus == 'submitted' ||
            order.paymentStatus == 'under_review');
  }

  bool _canReview(AdminOrderRecord order) {
    return order.paymentProofUrl != null &&
        order.orderStatus == 'payment_pending' &&
        (order.manualPaymentReviewStatus == 'submitted' ||
            order.manualPaymentReviewStatus == 'resubmission_requested' ||
            order.paymentStatus == 'under_review' ||
            order.paymentStatus == 'rejected');
  }

  bool _canCancel(AdminOrderRecord order) {
    return order.orderStatus == 'payment_pending';
  }

  String _terminalLabel(AdminOrderRecord order) {
    return switch (order.orderStatus) {
      'cancelled' => 'Cancelled',
      'failed' => 'Rejected',
      'fulfilled' => 'Completed',
      _ => 'Closed',
    };
  }
}

enum _OrderAction {
  viewDetails('View details'),
  viewProof('View proof'),
  approvePayment('Approve payment'),
  rejectPayment('Reject payment'),
  requestResubmission('Request resubmission'),
  cancelOrder('Cancel order');

  const _OrderAction(this.label);

  final String label;
}

class _OrderDetailBlock extends StatelessWidget {
  const _OrderDetailBlock({
    required this.title,
    required this.rows,
    this.footer,
  });

  final String title;
  final List<_OrderDetailRow> rows;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF15120E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFD4AF37).withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...rows.map((_OrderDetailRow row) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 160,
                    child: Text(
                      row.label,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Expanded(child: Text(row.value)),
                ],
              ),
            );
          }),
          if (footer != null) ...<Widget>[
            const SizedBox(height: 8),
            footer!,
          ],
        ],
      ),
    );
  }
}

class _OrderDetailRow {
  const _OrderDetailRow(this.label, this.value);

  final String label;
  final String value;
}
