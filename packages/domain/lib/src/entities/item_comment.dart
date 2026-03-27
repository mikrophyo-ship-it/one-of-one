class ItemComment {
  const ItemComment({
    required this.id,
    required this.itemId,
    required this.userDisplayName,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String itemId;
  final String userDisplayName;
  final String body;
  final DateTime createdAt;
}
