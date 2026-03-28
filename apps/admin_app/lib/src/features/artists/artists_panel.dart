import 'package:domain/domain.dart';
import 'package:flutter/material.dart';

import '../../widgets/admin_shared.dart';

class AdminArtistEditorValue {
  const AdminArtistEditorValue({
    required this.artistId,
    required this.displayName,
    required this.slug,
    required this.royaltyBps,
    required this.authenticityStatement,
    required this.shortBio,
    required this.fullBio,
    required this.artistStatement,
    required this.instagramUrl,
    required this.websiteUrl,
    required this.isFeatured,
    required this.sortOrder,
    required this.profileStatus,
  });

  final String? artistId;
  final String displayName;
  final String slug;
  final int royaltyBps;
  final String authenticityStatement;
  final String shortBio;
  final String fullBio;
  final String artistStatement;
  final String instagramUrl;
  final String websiteUrl;
  final bool isFeatured;
  final int sortOrder;
  final String profileStatus;
}

class ArtistsPanel extends StatefulWidget {
  const ArtistsPanel({
    required this.artists,
    required this.busySlots,
    required this.onSaveArtist,
    required this.onUploadArtistImage,
    required this.onRemoveArtistImage,
    super.key,
  });

  final List<AdminArtistRecord> artists;
  final Set<String> busySlots;
  final Future<void> Function(AdminArtistEditorValue value) onSaveArtist;
  final Future<void> Function(AdminArtistRecord artist, String slot)
  onUploadArtistImage;
  final Future<void> Function(AdminArtistRecord artist, String slot)
  onRemoveArtistImage;

  @override
  State<ArtistsPanel> createState() => _ArtistsPanelState();
}

class _ArtistsPanelState extends State<ArtistsPanel> {
  final TextEditingController _searchController = TextEditingController();
  String _statusFilter = 'all';
  bool? _featuredFilter;
  String _sortBy = 'display_order';
  String? _selectedArtistId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String query = _searchController.text.trim().toLowerCase();
    final List<AdminArtistRecord> filtered = widget.artists.where((
      AdminArtistRecord artist,
    ) {
      final bool matchesQuery =
          query.isEmpty ||
          artist.displayName.toLowerCase().contains(query) ||
          artist.slug.toLowerCase().contains(query);
      final bool matchesStatus =
          _statusFilter == 'all' || artist.profileStatus == _statusFilter;
      final bool matchesFeatured =
          _featuredFilter == null || artist.isFeatured == _featuredFilter;
      return matchesQuery && matchesStatus && matchesFeatured;
    }).toList()
      ..sort((AdminArtistRecord a, AdminArtistRecord b) {
        switch (_sortBy) {
          case 'updated_desc':
            final DateTime aUpdated =
                a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final DateTime bUpdated =
                b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final int updatedCompare = bUpdated.compareTo(aUpdated);
            if (updatedCompare != 0) {
              return updatedCompare;
            }
            return a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            );
          case 'name_asc':
            return a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            );
          case 'display_order':
          default:
            final int orderCompare = a.sortOrder.compareTo(b.sortOrder);
            if (orderCompare != 0) {
              return orderCompare;
            }
            return a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            );
        }
      });

    AdminArtistRecord? selected;
    if (_selectedArtistId != null) {
      for (final AdminArtistRecord artist in widget.artists) {
        if (artist.artistId == _selectedArtistId) {
          selected = artist;
          break;
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Artist management',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Admin-managed profile publishing, editorial media, featured placement, and public-facing artist content.',
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _selectedArtistId = null;
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('New artist'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            SizedBox(
              width: 280,
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Search artist',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String>(
                initialValue: _statusFilter,
                decoration: const InputDecoration(labelText: 'Profile status'),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'all', child: Text('All statuses')),
                  DropdownMenuItem(value: 'draft', child: Text('Draft')),
                  DropdownMenuItem(value: 'published', child: Text('Published')),
                  DropdownMenuItem(value: 'archived', child: Text('Archived')),
                ],
                onChanged: (String? value) {
                  setState(() {
                    _statusFilter = value ?? 'all';
                  });
                },
              ),
            ),
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String>(
                initialValue: _featuredFilter == null
                    ? 'all'
                    : _featuredFilter!
                    ? 'featured'
                    : 'not_featured',
                decoration: const InputDecoration(labelText: 'Featured'),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'all', child: Text('All artists')),
                  DropdownMenuItem(value: 'featured', child: Text('Featured')),
                  DropdownMenuItem(value: 'not_featured', child: Text('Not featured')),
                ],
                onChanged: (String? value) {
                  setState(() {
                    _featuredFilter = value == 'all'
                        ? null
                        : value == 'featured';
                  });
                },
              ),
            ),
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<String>(
                initialValue: _sortBy,
                decoration: const InputDecoration(labelText: 'Sort'),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(
                    value: 'display_order',
                    child: Text('Display order'),
                  ),
                  DropdownMenuItem(
                    value: 'updated_desc',
                    child: Text('Recently updated'),
                  ),
                  DropdownMenuItem(
                    value: 'name_asc',
                    child: Text('Artist name'),
                  ),
                ],
                onChanged: (String? value) {
                  setState(() {
                    _sortBy = value ?? 'display_order';
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool stacked = constraints.maxWidth < 1100;
            final Widget listPane = SectionCard(
              title: 'Artists',
              child: filtered.isEmpty
                  ? const EmptyState(message: 'No artists match the current filters.')
                  : Column(
                      children: filtered
                          .map(
                            (AdminArtistRecord artist) => _ArtistListRow(
                              artist: artist,
                              selected: artist.artistId == _selectedArtistId,
                              onTap: () {
                                setState(() {
                                  _selectedArtistId = artist.artistId;
                                });
                              },
                            ),
                          )
                          .toList(growable: false),
                    ),
            );

            final Widget editorPane = ArtistEditorCard(
              artist: selected,
              busySlots: widget.busySlots,
              onSave: widget.onSaveArtist,
              onUploadImage: widget.onUploadArtistImage,
              onRemoveImage: widget.onRemoveArtistImage,
            );

            if (stacked) {
              return Column(
                children: <Widget>[
                  listPane,
                  const SizedBox(height: 16),
                  editorPane,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(flex: 4, child: listPane),
                const SizedBox(width: 16),
                Expanded(flex: 6, child: editorPane),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ArtistListRow extends StatelessWidget {
  const _ArtistListRow({
    required this.artist,
    required this.selected,
    required this.onTap,
  });

  final AdminArtistRecord artist;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2A2414) : const Color(0xFF191919),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? const Color(0xFFD4AF37).withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.04),
          ),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    artist.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(artist.slug, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      StatusPill(label: artist.profileStatus),
                      if (artist.isFeatured) const StatusPill(label: 'featured'),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text('${artist.artworkCount} artworks'),
                const SizedBox(height: 4),
                Text('${artist.inventoryCount} inventory'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ArtistEditorCard extends StatefulWidget {
  const ArtistEditorCard({
    required this.artist,
    required this.busySlots,
    required this.onSave,
    required this.onUploadImage,
    required this.onRemoveImage,
    super.key,
  });

  final AdminArtistRecord? artist;
  final Set<String> busySlots;
  final Future<void> Function(AdminArtistEditorValue value) onSave;
  final Future<void> Function(AdminArtistRecord artist, String slot) onUploadImage;
  final Future<void> Function(AdminArtistRecord artist, String slot) onRemoveImage;

  @override
  State<ArtistEditorCard> createState() => _ArtistEditorCardState();
}

class _ArtistEditorCardState extends State<ArtistEditorCard> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _displayNameController;
  late final TextEditingController _slugController;
  late final TextEditingController _royaltyController;
  late final TextEditingController _statementController;
  late final TextEditingController _shortBioController;
  late final TextEditingController _fullBioController;
  late final TextEditingController _artistStatementController;
  late final TextEditingController _instagramController;
  late final TextEditingController _websiteController;
  bool _isFeatured = false;
  String _profileStatus = 'draft';
  int _sortOrder = 0;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController();
    _slugController = TextEditingController();
    _royaltyController = TextEditingController(text: '1200');
    _statementController = TextEditingController();
    _shortBioController = TextEditingController();
    _fullBioController = TextEditingController();
    _artistStatementController = TextEditingController();
    _instagramController = TextEditingController();
    _websiteController = TextEditingController();
    _syncFromArtist();
  }

  @override
  void didUpdateWidget(covariant ArtistEditorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artist?.artistId != widget.artist?.artistId) {
      _syncFromArtist();
    }
  }

  void _syncFromArtist() {
    final AdminArtistRecord? artist = widget.artist;
    _displayNameController.text = artist?.displayName ?? '';
    _slugController.text = artist?.slug ?? '';
    _royaltyController.text = '${artist?.royaltyBps ?? 1200}';
    _statementController.text = artist?.authenticityStatement ?? '';
    _shortBioController.text = artist?.shortBio ?? '';
    _fullBioController.text = artist?.fullBio ?? '';
    _artistStatementController.text = artist?.artistStatement ?? '';
    _instagramController.text = artist?.instagramUrl ?? '';
    _websiteController.text = artist?.websiteUrl ?? '';
    _isFeatured = artist?.isFeatured ?? false;
    _profileStatus = artist?.profileStatus ?? 'draft';
    _sortOrder = artist?.sortOrder ?? 0;
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _slugController.dispose();
    _royaltyController.dispose();
    _statementController.dispose();
    _shortBioController.dispose();
    _fullBioController.dispose();
    _artistStatementController.dispose();
    _instagramController.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AdminArtistRecord? artist = widget.artist;
    return SectionCard(
      title: artist == null ? 'Create artist profile' : 'Artist profile',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Identity'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _displayNameController,
              decoration: const InputDecoration(labelText: 'Display name'),
              validator: (String? value) =>
                  (value == null || value.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _slugController,
              decoration: const InputDecoration(labelText: 'Slug'),
              validator: (String? value) =>
                  (value == null || value.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _royaltyController,
              decoration: const InputDecoration(labelText: 'Royalty bps'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            const Text('Media'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                _ArtistMediaCard(
                  title: 'Portrait',
                  imageUrl: artist?.portraitImageUrl,
                  busy: artist != null &&
                      widget.busySlots.contains('${artist.artistId}:portrait'),
                  onUpload: artist == null
                      ? null
                      : () => widget.onUploadImage(artist, 'portrait'),
                  onRemove: artist?.portraitImageUrl == null
                      ? null
                      : () => widget.onRemoveImage(artist!, 'portrait'),
                ),
                _ArtistMediaCard(
                  title: 'Hero image',
                  imageUrl: artist?.heroImageUrl,
                  busy: artist != null &&
                      widget.busySlots.contains('${artist.artistId}:hero'),
                  onUpload: artist == null
                      ? null
                      : () => widget.onUploadImage(artist, 'hero'),
                  onRemove: artist?.heroImageUrl == null
                      ? null
                      : () => widget.onRemoveImage(artist!, 'hero'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Profile text'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _shortBioController,
              decoration: const InputDecoration(labelText: 'Short bio'),
              minLines: 2,
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _fullBioController,
              decoration: const InputDecoration(labelText: 'Full bio / about'),
              minLines: 4,
              maxLines: 6,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _artistStatementController,
              decoration: const InputDecoration(labelText: 'Artist statement'),
              minLines: 3,
              maxLines: 5,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _statementController,
              decoration: const InputDecoration(
                labelText: 'Authenticity statement',
              ),
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: 16),
            const Text('Links'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _instagramController,
              decoration: const InputDecoration(labelText: 'Instagram URL'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _websiteController,
              decoration: const InputDecoration(labelText: 'Website URL'),
            ),
            const SizedBox(height: 16),
            const Text('Publishing & display'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _profileStatus,
              decoration: const InputDecoration(labelText: 'Profile status'),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem(value: 'draft', child: Text('Draft')),
                DropdownMenuItem(value: 'published', child: Text('Published')),
                DropdownMenuItem(value: 'archived', child: Text('Archived')),
              ],
              onChanged: (String? value) {
                setState(() {
                  _profileStatus = value ?? 'draft';
                });
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: '$_sortOrder',
              decoration: const InputDecoration(labelText: 'Display order'),
              keyboardType: TextInputType.number,
              onChanged: (String value) {
                _sortOrder = int.tryParse(value.trim()) ?? 0;
              },
            ),
            SwitchListTile(
              value: _isFeatured,
              contentPadding: EdgeInsets.zero,
              title: const Text('Featured artist'),
              subtitle: const Text('Highlight in featured/public artist surfaces.'),
              onChanged: (bool value) {
                setState(() {
                  _isFeatured = value;
                });
              },
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () async {
                  if (!_formKey.currentState!.validate()) {
                    return;
                  }
                  await widget.onSave(
                    AdminArtistEditorValue(
                      artistId: artist?.artistId,
                      displayName: _displayNameController.text.trim(),
                      slug: _slugController.text.trim(),
                      royaltyBps:
                          int.tryParse(_royaltyController.text.trim()) ?? 1200,
                      authenticityStatement: _statementController.text.trim(),
                      shortBio: _shortBioController.text.trim(),
                      fullBio: _fullBioController.text.trim(),
                      artistStatement: _artistStatementController.text.trim(),
                      instagramUrl: _instagramController.text.trim(),
                      websiteUrl: _websiteController.text.trim(),
                      isFeatured: _isFeatured,
                      sortOrder: _sortOrder,
                      profileStatus: _profileStatus,
                    ),
                  );
                },
                child: Text(artist == null ? 'Create profile' : 'Save profile'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtistMediaCard extends StatelessWidget {
  const _ArtistMediaCard({
    required this.title,
    required this.imageUrl,
    required this.busy,
    required this.onUpload,
    required this.onRemove,
  });

  final String title;
  final String? imageUrl;
  final bool busy;
  final VoidCallback? onUpload;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 140,
              width: double.infinity,
              color: const Color(0xFF111111),
              alignment: Alignment.center,
              child: imageUrl == null
                  ? const Icon(Icons.image_outlined, size: 28)
                  : Image.network(imageUrl!, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.tonal(
                  onPressed: busy ? null : onUpload,
                  child: Text(imageUrl == null ? 'Upload' : 'Replace'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onRemove,
                  child: const Text('Remove'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
