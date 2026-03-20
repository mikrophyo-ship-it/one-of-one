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

  final FeeBreakdown breakdown = rules.calculateResaleBreakdown(
    resalePrice: 100000,
    royaltyBps: 1500,
  );
  expectCondition(breakdown.platformFee == 10000, 'platform fee calculation');
  expectCondition(breakdown.artistRoyalty == 15000, 'artist royalty calculation');
  expectCondition(breakdown.sellerPayout == 75000, 'seller payout calculation');

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
  expectCondition(claimResult.success, 'ownership claim approval');

  const UniqueItem frozenItem = UniqueItem(
    id: 'item_3',
    serialNumber: 'OOO-0003',
    artworkId: 'artwork_3',
    artistId: 'artist_1',
    productName: 'Archive Crew',
    state: ItemState.frozen,
    currentOwnerUserId: null,
    claimCodeConsumed: false,
    askingPrice: null,
  );
  final ClaimResult frozenClaim = rules.validateClaim(
    item: frozenItem,
    providedClaimCode: 'CLAIM-123',
    expectedClaimCode: 'CLAIM-123',
  );
  expectCondition(!frozenClaim.success, 'frozen item claim blocking');

  expectCondition(
    rules.canListForResale(item: claimedItem, actingUserId: 'user_seller'),
    'resale eligibility for recorded owner',
  );
  expectCondition(
    !rules.canListForResale(item: claimedItem, actingUserId: 'user_other'),
    'resale rejection for non-owner',
  );
  expectCondition(rules.blocksMarketplaceAction(ItemState.disputed), 'dispute blocking');
  expectCondition(rules.blocksMarketplaceAction(ItemState.stolenFlagged), 'stolen blocking');
  expectCondition(rules.blocksMarketplaceAction(ItemState.frozen), 'frozen blocking');

  const Order order = Order(
    id: 'order_1',
    itemId: 'item_1',
    buyerUserId: 'user_buyer',
    amount: 100000,
    paymentCaptured: true,
  );
  final UniqueItem transferred = rules.completeResale(
    item: claimedItem.copyWith(state: ItemState.salePending, askingPrice: 100000),
    order: order,
  );
  expectCondition(transferred.currentOwnerUserId == 'user_buyer', 'ownership transfer after payment');
  expectCondition(transferred.state == ItemState.transferred, 'post-order state transition');
  expectCondition(
    rules.isTransitionAllowed(ItemState.listedForResale, ItemState.salePending),
    'allowed listed_for_resale -> sale_pending transition',
  );
  expectCondition(
    !rules.isTransitionAllowed(ItemState.claimed, ItemState.salePending),
    'blocked direct claimed -> sale_pending transition',
  );

  print('All domain rule checks passed.');
}

void expectCondition(bool condition, String label) {
  if (!condition) {
    throw StateError('Failed: $label');
  }
}
