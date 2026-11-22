import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_item.dart';
import '../services/bgg_service.dart';
import '../services/collection_refresh.dart';
import '../services/image_compression_service.dart';
import '../services/inventory_service.dart';
import '../utils/picked_image_bytes.dart';
import '../utils/web_image_paste.dart';
import 'collection_cover_image.dart';

/// Nouveau titre / image d'un objet. `original_title` et `original_image_url`
/// gardent la version catalogue (BGG) pour la recherche et la restauration.
class ItemCustomization {
  final String title;
  final String? imageUrl;
  final Map<String, dynamic> metadata;

  const ItemCustomization({
    required this.title,
    required this.imageUrl,
    required this.metadata,
  });
}

/// Calcule titre / image / metadata après personnalisation (pur, testable).
ItemCustomization applyItemCustomization(
  CollectionItem item, {
  required String title,
  required String? imageUrl,
}) {
  final meta = Map<String, dynamic>.from(item.metadata ?? {});
  final cleanTitle = title.trim().isEmpty ? item.title : title.trim();

  final originalTitle =
      (meta['original_title']?.toString().trim().isNotEmpty ?? false)
          ? meta['original_title'].toString().trim()
          : item.title.trim();
  if (cleanTitle.toLowerCase() == originalTitle.toLowerCase()) {
    meta.remove('original_title');
  } else {
    meta['original_title'] = originalTitle;
  }

  final originalImage =
      (meta['original_image_url']?.toString().trim().isNotEmpty ?? false)
          ? meta['original_image_url'].toString().trim()
          : item.imageUrl;
  if (imageUrl == null || imageUrl == originalImage) {
    meta.remove('original_image_url');
    meta.remove('custom_image');
  } else {
    if (originalImage != null && originalImage.isNotEmpty) {
      meta['original_image_url'] = originalImage;
    }
    meta['custom_image'] = true;
  }

  return ItemCustomization(
    title: cleanTitle,
    imageUrl: imageUrl ?? originalImage,
    metadata: meta,
  );
}

/// Extrait le path Storage `avatars` d'une URL publique de couverture.
String? avatarsStoragePathFromUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  const marker = '/storage/v1/object/public/avatars/';
  final i = url.indexOf(marker);
  if (i < 0) return null;
  final path = Uri.decodeComponent(url.substring(i + marker.length));
  if (!path.contains('/covers/')) return null;
  return path;
}

Future<bool?> showItemCustomizeSheet(
  BuildContext context, {
  required CollectionItem item,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ItemCustomizeSheet(item: item),
  );
}

class _ItemCustomizeSheet extends StatefulWidget {
  final CollectionItem item;

  const _ItemCustomizeSheet({required this.item});

  @override
  State<_ItemCustomizeSheet> createState() => _ItemCustomizeSheetState();
}

class _ItemCustomizeSheetState extends State<_ItemCustomizeSheet> {
  late final TextEditingController _title =
      TextEditingController(text: widget.item.title);
  late String? _imageUrl = widget.item.imageUrl;
  Uint8List? _pendingBytes;
  bool _saving = false;
  bool _dragging = false;
  List<BggGalleryPhoto>? _gallery;
  bool _galleryLoading = false;

  String? get _originalTitle {
    final raw = widget.item.metadata?['original_title']?.toString().trim();
    return raw == null || raw.isEmpty ? null : raw;
  }

  String? get _originalImage {
    final raw =
        widget.item.metadata?['original_image_url']?.toString().trim();
    if (raw != null && raw.isNotEmpty) return raw;
    return widget.item.metadata?['custom_image'] == true
        ? null
        : widget.item.imageUrl;
  }

  String? get _bggId {
    final raw = widget.item.metadata?['bgg_id']?.toString().trim();
    return raw == null || raw.isEmpty ? null : raw;
  }

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      bindWebImagePaste((bytes) {
        if (!mounted) return;
        unawaited(_acceptBytes(bytes));
      });
    }
  }

  @override
  void dispose() {
    if (kIsWeb) unbindWebImagePaste();
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 90,
    );
    if (picked == null) return;
    final raw = await readPickedImageBytes(picked);
    final compressed = ImageCompressionService.compressCover(raw);
    if (!mounted) return;
    setState(() => _pendingBytes = compressed);
  }

  Future<void> _acceptBytes(Uint8List raw) async {
    final compressed = ImageCompressionService.compressCover(raw);
    if (!mounted) return;
    setState(() => _pendingBytes = compressed);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!kIsWeb) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isPaste = (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyV;
    if (!isPaste) return KeyEventResult.ignored;
    // Le collage image web passe souvent par le drop ; on signale juste.
    return KeyEventResult.ignored;
  }

  Future<void> _loadGallery() async {
    final id = _bggId;
    if (id == null || _galleryLoading) return;
    setState(() => _galleryLoading = true);
    try {
      final photos = await BggService.fetchCommunityGallery(id);
      if (mounted) setState(() => _gallery = photos);
    } catch (_) {
      if (mounted) setState(() => _gallery = const []);
    } finally {
      if (mounted) setState(() => _galleryLoading = false);
    }
  }

  Future<String> _upload(Uint8List bytes) async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser!.id;
    final path =
        '$uid/covers/${widget.item.id}-${DateTime.now().millisecondsSinceEpoch}.jpg';
    await client.storage.from('avatars').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
    return client.storage.from('avatars').getPublicUrl(path);
  }

  Future<void> _deleteStoredCover(String? url) async {
    final path = avatarsStoragePathFromUrl(url);
    if (path == null) return;
    try {
      await Supabase.instance.client.storage.from('avatars').remove([path]);
    } catch (_) {}
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final previousUrl = widget.item.imageUrl;
      var url = _imageUrl;
      if (_pendingBytes != null) url = await _upload(_pendingBytes!);
      final next = applyItemCustomization(
        widget.item,
        title: _title.text,
        imageUrl: url,
      );
      await Supabase.instance.client.from('collection_items').update({
        'title': next.title,
        'image_url': next.imageUrl,
        'metadata': next.metadata,
      }).eq('id', widget.item.id);

      // Nettoie l'ancienne couverture perso orpheline.
      final restoredBgg = next.metadata['custom_image'] != true;
      final replacedCustom = previousUrl != null &&
          previousUrl != next.imageUrl &&
          avatarsStoragePathFromUrl(previousUrl) != null;
      if (restoredBgg || replacedCustom) {
        await _deleteStoredCover(previousUrl);
      }

      InventoryService.patchRow(widget.item.id, (row) {
        row['title'] = next.title;
        row['image_url'] = next.imageUrl;
        row['metadata'] = next.metadata;
      });
      CollectionRefresh.instance.bump();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Enregistrement impossible : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _previewBox(ColorScheme scheme) {
    final child = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 120,
        height: 120,
        child: _pendingBytes != null
            ? Image.memory(_pendingBytes!, fit: BoxFit.cover)
            : (_imageUrl != null && _imageUrl!.isNotEmpty)
                ? CollectionCoverImage(
                    url: _imageUrl!,
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                  )
                : ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: const Icon(Icons.image_outlined),
                  ),
      ),
    );

    if (!kIsWeb) return child;

    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: DragTarget<Object>(
        onWillAcceptWithDetails: (_) {
          setState(() => _dragging = true);
          return true;
        },
        onLeave: (_) => setState(() => _dragging = false),
        onAcceptWithDetails: (details) async {
          setState(() => _dragging = false);
          final data = details.data;
          if (data is Uint8List) {
            await _acceptBytes(data);
          }
        },
        builder: (context, candidate, rejected) {
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _dragging || candidate.isNotEmpty
                    ? scheme.primary
                    : scheme.outlineVariant,
                width: _dragging ? 2.5 : 1,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                child,
                if (_dragging)
                  Positioned.fill(
                    child: ColoredBox(
                      color: scheme.primary.withValues(alpha: 0.18),
                      child: const Center(
                        child: Text(
                          'Déposer l\'image',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final origTitle = _originalTitle ?? widget.item.title;
    final origImage = _originalImage;
    final imageChanged = _pendingBytes != null || _imageUrl != origImage;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Personnaliser',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nom affiché',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_bggId != null || _originalTitle != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Titre BGG : $origTitle',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (_title.text.trim() != origTitle)
                      TextButton(
                        onPressed: () =>
                            setState(() => _title.text = origTitle),
                        child: const Text('Rétablir'),
                      ),
                  ],
                ),
                Text(
                  'La recherche trouve le jeu sous les deux noms.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              const Text(
                'Image',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              if (kIsWeb) ...[
                const SizedBox(height: 4),
                Text(
                  'Glisse une image ici ou colle avec Ctrl+V',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _previewBox(scheme),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _saving ? null : _pickPhoto,
                          icon: const Icon(
                            Icons.photo_camera_outlined,
                            size: 18,
                          ),
                          label: const Text('Ma photo'),
                        ),
                        if (_bggId != null)
                          OutlinedButton.icon(
                            onPressed: _saving ? null : _loadGallery,
                            icon: const Icon(
                              Icons.collections_outlined,
                              size: 18,
                            ),
                            label: const Text('Galerie BGG'),
                          ),
                        if (imageChanged && origImage != null)
                          TextButton(
                            onPressed: () => setState(() {
                              _pendingBytes = null;
                              _imageUrl = origImage;
                            }),
                            child: const Text('Rétablir l\'image BGG'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_galleryLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              else if (_gallery != null) ...[
                const SizedBox(height: 12),
                if (_gallery!.isEmpty)
                  const Text('Aucune image trouvée sur BGG.')
                else
                  SizedBox(
                    height: 86,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _gallery!.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (context, i) {
                        final p = _gallery![i];
                        final selected =
                            _pendingBytes == null && _imageUrl == p.url;
                        return GestureDetector(
                          onTap: () => setState(() {
                            _pendingBytes = null;
                            _imageUrl = p.url;
                          }),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected
                                    ? scheme.primary
                                    : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CollectionCoverImage(
                                url: p.url,
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Enregistrer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
