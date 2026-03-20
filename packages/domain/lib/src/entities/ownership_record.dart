class OwnershipRecord {
  const OwnershipRecord({
    required this.id,
    required this.itemId,
    required this.ownerUserId,
    required this.acquiredAt,
    this.relinquishedAt,
  });

  final String id;
  final String itemId;
  final String ownerUserId;
  final DateTime acquiredAt;
  final DateTime? relinquishedAt;
}
