class Artist {
  const Artist({
    required this.id,
    required this.displayName,
    required this.slug,
    required this.royaltyBps,
    required this.authenticityStatement,
    this.shortBio,
    this.fullBio,
    this.artistStatement,
    this.portraitImageUrl,
    this.heroImageUrl,
    this.instagramUrl,
    this.websiteUrl,
    this.isFeatured = false,
    this.sortOrder = 0,
    this.profileStatus = 'published',
  });

  final String id;
  final String displayName;
  final String slug;
  final int royaltyBps;
  final String authenticityStatement;
  final String? shortBio;
  final String? fullBio;
  final String? artistStatement;
  final String? portraitImageUrl;
  final String? heroImageUrl;
  final String? instagramUrl;
  final String? websiteUrl;
  final bool isFeatured;
  final int sortOrder;
  final String profileStatus;
}
