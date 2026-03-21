import '../lib/src/entities/claim_result.dart';
import '../lib/src/entities/fee_breakdown.dart';
import '../lib/src/entities/item_state.dart';
import '../lib/src/entities/order.dart';
import '../lib/src/entities/unique_item.dart';
import '../lib/src/services/marketplace_rules.dart';

void main() {
  const MarketplaceRules rules = MarketplaceRules(
    platformFeeBps: 1000,
    defaultRoyaltyBps: 1200,
  );

  const UniqueItem claimedItem = UniqueItem(
    id: 'item_1',
    serialNumber: 'OOO-0001',
    artworkId: 'artwork_1',
    artistId: 'artist_1',
    productName: 'Gallery Tee',
    state: ItemState.claimed,
    currentOwnerUserId: 'user_seller',
    claimCodeConsumed: true,
    askingPrice: null,
  );

  _run('platform fee calculation', () {
    final FeeBreakdown breakdown = rules.calculateResaleBreakdown(
      resalePrice: 100000,
      royaltyBps: 1500,
    );
    _expect(breakdown.platformFee == 10000, 'platform fee should be 10%');
    _expect(breakdown.artistRoyalty == 15000, 'royalty should be 15%');
    _expect(
      breakdown.sellerPayout == 75000,
      'seller payout should net correctly',
    );
  });

  _run('claim succeeds only for sold_unclaimed items with matching code', () {
    const UniqueItem claimableItem = UniqueItem(
      id: 'item_2',
      serialNumber: 'OOO-0002',
      artworkId: 'artwork_2',
      artistId: 'artist_1',
      productName: 'Studio Hoodie',
      state: ItemState.soldUnclaimed,
      currentOwnerUserId: null,
      claimCodeConsumed: false,
      askingPrice: null,
    );
    final ClaimResult claimResult = rules.validateClaim(
      item: claimableItem,
      providedClaimCode: 'CLAIM-123',
      expectedClaimCode: 'CLAIM-123',
    );
    _expect(claimResult.success, 'claim should be approved');
  });

  _run('claim fails when code is already consumed', () {
    final ClaimResult result = rules.validateClaim(
      item: claimedItem,
      providedClaimCode: 'CLAIM-123',
      expectedClaimCode: 'CLAIM-123',
    );
    _expect(!result.success, 'already-consumed claim should fail');
  });

  _run('claim fails for mismatched claim code', () {
    const UniqueItem claimableItem = UniqueItem(
      id: 'item_2',
      serialNumber: 'OOO-0002',
      artworkId: 'artwork_2',
      artistId: 'artist_1',
      productName: 'Studio Hoodie',
      state: ItemState.soldUnclaimed,
      currentOwnerUserId: null,
      claimCodeConsumed: false,
      askingPrice: null,
    );
    final ClaimResult result = rules.validateClaim(
      item: claimableItem,
      providedClaimCode: 'WRONG-CODE',
      expectedClaimCode: 'CLAIM-123',
    );
    _expect(!result.success, 'mismatched claim code should fail');
  });

  _run('frozen and stolen items cannot be claimed', () {
    for (final ItemState state in <ItemState>[
      ItemState.frozen,
      ItemState.stolenFlagged,
    ]) {
      final ClaimResult result = rules.validateClaim(
        item: UniqueItem(
          id: 'blocked_${state.key}',
          serialNumber: 'OOO-BLOCKED',
          artworkId: 'artwork',
          artistId: 'artist',
          productName: 'Blocked Piece',
          state: state,
          currentOwnerUserId: null,
          claimCodeConsumed: false,
          askingPrice: null,
        ),
        providedClaimCode: 'CLAIM-123',
        expectedClaimCode: 'CLAIM-123',
      );
      _expect(!result.success, '${state.key} should not be claimable');
    }
  });

  _run('only recorded owner can list eligible items', () {
    _expect(
      rules.canListForResale(item: claimedItem, actingUserId: 'user_seller'),
      'recorded owner should be able to list',
    );
    _expect(
      !rules.canListForResale(item: claimedItem, actingUserId: 'user_other'),
      'non-owner should not be able to list',
    );
  });

  _run('disputed stolen and frozen states block marketplace actions', () {
    _expect(
      rules.blocksMarketplaceAction(ItemState.disputed),
      'disputed should block',
    );
    _expect(
      rules.blocksMarketplaceAction(ItemState.stolenFlagged),
      'stolen should block',
    );
    _expect(
      rules.blocksMarketplaceAction(ItemState.frozen),
      'frozen should block',
    );
  });

  _run('ownership transfer requires successful payment capture', () {
    bool threw = false;
    try {
      rules.completeResale(
        item: claimedItem.copyWith(
          state: ItemState.salePending,
          askingPrice: 100000,
        ),
        order: const Order(
          id: 'order_unpaid',
          itemId: 'item_1',
          buyerUserId: 'user_buyer',
          amount: 100000,
          paymentCaptured: false,
        ),
      );
    } catch (_) {
      threw = true;
    }
    _expect(threw, 'unpaid order should not transfer ownership');
  });

  _run('restricted item cannot transfer even after payment object exists', () {
    bool threw = false;
    try {
      rules.completeResale(
        item: claimedItem.copyWith(
          state: ItemState.frozen,
          askingPrice: 100000,
        ),
        order: const Order(
          id: 'order_blocked',
          itemId: 'item_1',
          buyerUserId: 'user_buyer',
          amount: 100000,
          paymentCaptured: true,
        ),
      );
    } catch (_) {
      threw = true;
    }
    _expect(threw, 'restricted item should not transfer');
  });

  _run('paid resale transfers ownership and resets listing price', () {
    final UniqueItem transferred = rules.completeResale(
      item: claimedItem.copyWith(
        state: ItemState.salePending,
        askingPrice: 100000,
      ),
      order: const Order(
        id: 'order_paid',
        itemId: 'item_1',
        buyerUserId: 'user_buyer',
        amount: 100000,
        paymentCaptured: true,
      ),
    );
    _expect(
      transferred.currentOwnerUserId == 'user_buyer',
      'owner should update',
    );
    _expect(
      transferred.state == ItemState.transferred,
      'state should be transferred',
    );
    _expect(transferred.askingPrice == null, 'asking price should clear');
  });

  _run('state transitions reflect dispute and resale lifecycle', () {
    _expect(
      rules.isTransitionAllowed(
        ItemState.listedForResale,
        ItemState.salePending,
      ),
      'listed_for_resale -> sale_pending should be allowed',
    );
    _expect(
      !rules.isTransitionAllowed(ItemState.claimed, ItemState.salePending),
      'claimed -> sale_pending should not be allowed directly',
    );
    _expect(
      rules.isTransitionAllowed(ItemState.salePending, ItemState.transferred),
      'sale_pending -> transferred should be allowed',
    );
    _expect(
      rules.isTransitionAllowed(ItemState.disputed, ItemState.archived),
      'disputed -> archived should be allowed',
    );
  });

  print('All domain rule checks passed.');
}

void _run(String label, void Function() body) {
  try {
    body();
    print('PASS: $label');
  } catch (error) {
    throw StateError('Failed: $label\n$error');
  }
}

void _expect(bool condition, String label) {
  if (!condition) {
    throw StateError(label);
  }
}
