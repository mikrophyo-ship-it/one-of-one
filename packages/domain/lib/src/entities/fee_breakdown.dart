class FeeBreakdown {
  const FeeBreakdown({
    required this.grossAmount,
    required this.platformFee,
    required this.artistRoyalty,
    required this.sellerPayout,
  });

  final int grossAmount;
  final int platformFee;
  final int artistRoyalty;
  final int sellerPayout;
}
