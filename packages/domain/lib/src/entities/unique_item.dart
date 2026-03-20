import 'item_state.dart';

class UniqueItem {
  const UniqueItem({
    required this.id,
    required this.serialNumber,
    required this.artworkId,
    required this.artistId,
    required this.productName,
    required this.state,
    required this.currentOwnerUserId,
    required this.claimCodeConsumed,
    required this.askingPrice,
  });

  final String id;
  final String serialNumber;
  final String artworkId;
  final String artistId;
  final String productName;
  final ItemState state;
  final String? currentOwnerUserId;
  final bool claimCodeConsumed;
  final int? askingPrice;

  UniqueItem copyWith({
    ItemState? state,
    String? currentOwnerUserId,
    bool? claimCodeConsumed,
    int? askingPrice,
  }) {
    return UniqueItem(
      id: id,
      serialNumber: serialNumber,
      artworkId: artworkId,
      artistId: artistId,
      productName: productName,
      state: state ?? this.state,
      currentOwnerUserId: currentOwnerUserId ?? this.currentOwnerUserId,
      claimCodeConsumed: claimCodeConsumed ?? this.claimCodeConsumed,
      askingPrice: askingPrice ?? this.askingPrice,
    );
  }
}
