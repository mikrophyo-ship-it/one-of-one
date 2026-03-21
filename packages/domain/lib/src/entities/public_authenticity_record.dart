import 'item_state.dart';

class PublicAuthenticityRecord {
  const PublicAuthenticityRecord({
    required this.qrToken,
    required this.serialNumber,
    required this.state,
    required this.garmentName,
    required this.artworkTitle,
    required this.story,
    required this.artistName,
    required this.authenticityStatus,
    required this.publicStory,
    required this.ownershipVisibility,
    required this.verifiedTransferCount,
  });

  final String qrToken;
  final String serialNumber;
  final ItemState state;
  final String garmentName;
  final String artworkTitle;
  final String story;
  final String artistName;
  final String authenticityStatus;
  final String publicStory;
  final String ownershipVisibility;
  final int verifiedTransferCount;
}
