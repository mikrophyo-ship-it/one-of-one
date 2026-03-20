class Artist {
  const Artist({
    required this.id,
    required this.displayName,
    required this.slug,
    required this.royaltyBps,
    required this.authenticityStatement,
  });

  final String id;
  final String displayName;
  final String slug;
  final int royaltyBps;
  final String authenticityStatement;
}
