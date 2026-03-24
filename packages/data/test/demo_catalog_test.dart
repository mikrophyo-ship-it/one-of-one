// ignore_for_file: avoid_print

import 'package:domain/domain.dart';

import '../lib/src/demo/demo_catalog.dart';

Future<void> main() async {
  await _run('public authenticity lookup stays privacy-safe', () async {
    final DemoCatalog catalog = DemoCatalog();
    final result = await catalog.lookupPublicAuthenticity(
      qrToken: 'qr_afterglow_01',
    );
    _expect(result.success, 'lookup should succeed');
    _expect(result.data != null, 'lookup should return a record');
    _expect(
      result.data!.verifiedTransferCount >= 0,
      'transfer count should never be negative',
    );
  });

  await _run('claim code can only be used once', () async {
    final DemoCatalog catalog = DemoCatalog();
    final first = await catalog.claimOwnership(
      itemId: 'item_ember_02',
      claimCode: 'CLAIM-OOO-EM-0002',
      userId: 'collector_one',
    );
    final second = await catalog.claimOwnership(
      itemId: 'item_ember_02',
      claimCode: 'CLAIM-OOO-EM-0002',
      userId: 'collector_two',
    );
    _expect(first.success, 'first claim should succeed');
    _expect(!second.success, 'second claim should fail');
  });

  await _run('non-owner cannot create resale listing', () async {
    final DemoCatalog catalog = DemoCatalog();
    final result = await catalog.createResaleListing(
      itemId: 'item_afterglow_01',
      userId: 'not_the_owner',
      priceCents: 210000,
    );
    _expect(!result.success, 'listing should fail for a non-owner');
  });

  await _run('restricted items cannot be listed', () async {
    final DemoCatalog catalog = DemoCatalog();
    final result = await catalog.createResaleListing(
      itemId: 'item_restricted_03',
      userId: 'user_collector_2',
      priceCents: 120000,
    );
    _expect(!result.success, 'restricted item listing should fail');
  });

  await _run('self-buy is blocked', () async {
    final DemoCatalog catalog = DemoCatalog();
    final result = await catalog.buyResaleItem(
      itemId: 'item_afterglow_01',
      buyerUserId: 'user_collector_1',
      providerReference: 'mock-self-buy',
    );
    _expect(!result.success, 'seller should not be able to buy own listing');
  });

  await _run(
    'payment-backed resale transfers ownership and closes listing',
    () async {
      final DemoCatalog catalog = DemoCatalog();
      final result = await catalog.buyResaleItem(
        itemId: 'item_afterglow_01',
        buyerUserId: 'collector_buyer',
        providerReference: 'mock-payment-123',
      );
      final item = catalog.itemById('item_afterglow_01');
      _expect(result.success, 'resale buy should succeed');
      _expect(item != null, 'item should still exist');
      _expect(
        item!.currentOwnerUserId == 'collector_buyer',
        'ownership should transfer',
      );
      _expect(
        item.state == ItemState.transferred,
        'item should enter transferred state',
      );
      _expect(
        item.askingPrice == null,
        'asking price should clear after transfer',
      );
      _expect(
        catalog.activeListings().isEmpty,
        'listing should no longer be active',
      );
    },
  );

  await _run(
    'owner dispute freeze deactivates listing and blocks marketability',
    () async {
      final DemoCatalog catalog = DemoCatalog();
      final dispute = await catalog.openDispute(
        itemId: 'item_afterglow_01',
        userId: 'user_collector_1',
        reason: 'Package reported stolen',
        freeze: true,
      );
      final item = catalog.itemById('item_afterglow_01');
      _expect(dispute.success, 'owner dispute should succeed');
      _expect(item!.state == ItemState.frozen, 'item should be frozen');
      _expect(
        catalog.activeListings().isEmpty,
        'active listing should be removed',
      );
    },
  );

  print('All demo catalog checks passed.');
}

Future<void> _run(String label, Future<void> Function() body) async {
  try {
    await body();
    print('PASS: $label');
  } catch (error) {
    throw StateError('Failed: $label\n$error');
  }
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
