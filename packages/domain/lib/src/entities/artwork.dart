class Artwork {
  const Artwork({
    required this.id,
    required this.artistId,
    required this.title,
    required this.story,
    required this.humanMadeProof,
    required this.createdOn,
  });

  final String id;
  final String artistId;
  final String title;
  final String story;
  final List<String> humanMadeProof;
  final DateTime createdOn;
}
