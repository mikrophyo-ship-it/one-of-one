import '../entities/claim_result.dart';
import '../entities/fee_breakdown.dart';
import '../entities/item_state.dart';
import '../entities/order.dart';
import '../entities/unique_item.dart';

class MarketplaceRules {
  const MarketplaceRules({
    required this.platformFeeBps,
    required this.defaultRoyaltyBps,
  });

  final int platformFeeBps;
  final int defaultRoyaltyBps;

  FeeBreakdown calculateResaleBreakdown({
    required int resalePrice,
    required int royaltyBps,
  }) {
    final int platformFee = _basisPoints(resalePrice, platformFeeBps);
    final int artistRoyalty = _basisPoints(resalePrice, royaltyBps);
    final int sellerPayout = resalePrice - platformFee - artistRoyalty;
    return FeeBreakdown(
      grossAmount: resalePrice,
      platformFee: platformFee,
      artistRoyalty: artistRoyalty,
      sellerPayout: sellerPayout,
    );
  }

  bool canClaim({required UniqueItem item}) {
    if (item.claimCodeConsumed) {
      return false;
    }
    return item.state == ItemState.soldUnclaimed;
  }

  bool canListForResale({
    required UniqueItem item,
    required String actingUserId,
  }) {
    if (item.currentOwnerUserId != actingUserId) {
      return false;
    }
    if (item.state == ItemState.claimed || item.state == ItemState.transferred) {
      return true;
    }
    return false;
  }

  bool blocksMarketplaceAction(ItemState state) => state.isRestricted;

  ClaimResult validateClaim({
    required UniqueItem item,
    required String providedClaimCode,
    required String expectedClaimCode,
  }) {
    if (item.state == ItemState.stolenFlagged || item.state == ItemState.frozen) {
      return const ClaimResult(
        success: false,
        message: 'Frozen or stolen items cannot be claimed.',
      );
    }
    if (!canClaim(item: item)) {
      return const ClaimResult(
        success: false,
        message: 'Item is not eligible for ownership claim.',
      );
    }
    if (providedClaimCode != expectedClaimCode) {
      return const ClaimResult(
        success: false,
        message: 'Claim code is invalid.',
      );
    }
    return const ClaimResult(
      success: true,
      message: 'Ownership claim approved.',
      newState: 'claimed',
    );
  }

  UniqueItem completeResale({
    required UniqueItem item,
    required Order order,
  }) {
    if (!order.paymentCaptured) {
      throw StateError('Ownership cannot transfer before payment capture.');
    }
    if (blocksMarketplaceAction(item.state)) {
      throw StateError('Restricted items cannot be transferred.');
    }
    return item.copyWith(
      state: ItemState.transferred,
      currentOwnerUserId: order.buyerUserId,
      askingPrice: null,
    );
  }

  bool isTransitionAllowed(ItemState from, ItemState to) {
    const Map<ItemState, Set<ItemState>> allowed = <ItemState, Set<ItemState>>{
      ItemState.drafted: <ItemState>{ItemState.minted, ItemState.archived},
      ItemState.minted: <ItemState>{ItemState.inInventory, ItemState.archived},
      ItemState.inInventory: <ItemState>{ItemState.soldUnclaimed, ItemState.frozen},
      ItemState.soldUnclaimed: <ItemState>{
        ItemState.claimed,
        ItemState.frozen,
        ItemState.disputed,
      },
      ItemState.claimed: <ItemState>{
        ItemState.listedForResale,
        ItemState.disputed,
        ItemState.stolenFlagged,
        ItemState.frozen,
      },
      ItemState.listedForResale: <ItemState>{
        ItemState.salePending,
        ItemState.claimed,
        ItemState.disputed,
        ItemState.stolenFlagged,
        ItemState.frozen,
      },
      ItemState.salePending: <ItemState>{
        ItemState.transferred,
        ItemState.claimed,
        ItemState.disputed,
        ItemState.frozen,
      },
      ItemState.transferred: <ItemState>{
        ItemState.claimed,
        ItemState.listedForResale,
        ItemState.disputed,
        ItemState.stolenFlagged,
        ItemState.frozen,
      },
      ItemState.disputed: <ItemState>{
        ItemState.claimed,
        ItemState.frozen,
        ItemState.archived,
      },
      ItemState.stolenFlagged: <ItemState>{ItemState.frozen, ItemState.disputed},
      ItemState.frozen: <ItemState>{ItemState.claimed, ItemState.archived},
      ItemState.archived: <ItemState>{},
    };
    return allowed[from]?.contains(to) ?? false;
  }

  int _basisPoints(int amount, int bps) => ((amount * bps) / 10000).round();
}
