import 'item_state.dart';

const Object _uniqueItemUnset = Object();

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
    this.imageUrls = const <String>[],
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
  final List<String> imageUrls;

  UniqueItem copyWith({
    ItemState? state,
    Object? currentOwnerUserId = _uniqueItemUnset,
    bool? claimCodeConsumed,
    Object? askingPrice = _uniqueItemUnset,
    List<String>? imageUrls,
  }) {
    return UniqueItem(
      id: id,
      serialNumber: serialNumber,
      artworkId: artworkId,
      artistId: artistId,
      productName: productName,
      state: state ?? this.state,
      currentOwnerUserId: currentOwnerUserId == _uniqueItemUnset
          ? this.currentOwnerUserId
          : currentOwnerUserId as String?,
      claimCodeConsumed: claimCodeConsumed ?? this.claimCodeConsumed,
      askingPrice: askingPrice == _uniqueItemUnset
          ? this.askingPrice
          : askingPrice as int?,
      imageUrls: imageUrls ?? this.imageUrls,
    );
  }
}
