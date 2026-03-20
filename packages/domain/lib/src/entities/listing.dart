class Listing {
  const Listing({
    required this.id,
    required this.itemId,
    required this.sellerUserId,
    required this.askingPrice,
    required this.isActive,
  });

  final String id;
  final String itemId;
  final String sellerUserId;
  final int askingPrice;
  final bool isActive;

  Listing copyWith({
    String? id,
    String? itemId,
    String? sellerUserId,
    int? askingPrice,
    bool? isActive,
  }) {
    return Listing(
      id: id ?? this.id,
      itemId: itemId ?? this.itemId,
      sellerUserId: sellerUserId ?? this.sellerUserId,
      askingPrice: askingPrice ?? this.askingPrice,
      isActive: isActive ?? this.isActive,
    );
  }
}
