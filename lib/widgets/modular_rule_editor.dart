import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/rule_section.dart';
import '../services/image_compression_service.dart';
import '../utils/picked_image_bytes.dart';
import 'rich_section_text_field.dart';

/// Éditeur modulaire : bulles réordonnables, rich text, pièces jointes.
class ModularRuleEditor extends StatefulWidget {
  final List<RuleSection> initialSections;
  final ValueChanged<List<RuleSection>> onChanged;

  const ModularRuleEditor({
    super.key,
    required this.initialSections,
    required this.onChanged,
  });

  @override
  State<ModularRuleEditor> createState() => _ModularRuleEditorState();
}

class _ModularRuleEditorState extends State<ModularRuleEditor> {
  late List<RuleSection> _sections;
  final _expanded = <String>{};
  final _picker = ImagePicker();
  int _idSeq = 0;

  @override
  void initState() {
    super.initState();
    _sections = List.of(widget.initialSections);
    if (_sections.isEmpty) {
      _sections.add(_newSection(RuleSectionKind.objective));
      _expanded.add(_sections.first.id);
    }
  }

  String _newId() => 'sec_${DateTime.now().microsecondsSinceEpoch}_${_idSeq++}';

  RuleSection _newSection(RuleSectionKind kind, {String? customTitle}) {
    return RuleSection(
      id: _newId(),
      kind: kind,
      customTitle: customTitle,
    );
  }

  void _emit() => widget.onChanged(List.of(_sections));

  Set<RuleSectionKind> get _usedKinds =>
      _sections.map((s) => s.kind).where((k) => k != RuleSectionKind.other).toSet();

  List<RuleSectionKind> get _availableKinds => RuleSectionKind.values
      .where((k) => k == RuleSectionKind.other || !_usedKinds.contains(k))
      .toList();

  void _addSection(RuleSectionKind kind) async {
    String? customTitle;
    if (kind == RuleSectionKind.other) {
      final controller = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Titre de la section'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'Ex. Variante maison'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ajouter'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      customTitle = controller.text.trim();
      controller.dispose();
    }
    setState(() {
      final sec = _newSection(kind, customTitle: customTitle);
      _sections.add(sec);
      _expanded.add(sec.id);
      _emit();
    });
  }

  void _removeSection(String id) {
    setState(() {
      _sections.removeWhere((s) => s.id == id);
      _expanded.remove(id);
      _emit();
    });
  }

  void _updateSection(RuleSection updated) {
    final i = _sections.indexWhere((s) => s.id == updated.id);
    if (i < 0) return;
    setState(() {
      _sections[i] = updated;
      _emit();
    });
  }

  Future<void> _pickImage(RuleSection section) async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (file == null || !mounted) return;
    final bytes = await readPickedImageBytes(file);
    final compressed = await ImageCompressionService.compressForUpload(bytes);
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final path = '$userId/rule_sections/${section.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await Supabase.instance.client.storage.from('avatars').uploadBinary(
          path,
          compressed,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
        );
    final url =
        Supabase.instance.client.storage.from('avatars').getPublicUrl(path);
    if (!mounted) return;
    _updateSection(section.copyWith(imageUrl: url));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: _sections.length,
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) newIndex--;
              final item = _sections.removeAt(oldIndex);
              _sections.insert(newIndex, item);
              _emit();
            });
          },
          itemBuilder: (context, index) {
            final section = _sections[index];
            final expanded = _expanded.contains(section.id);
            return _SectionBubble(
              key: ValueKey(section.id),
              section: section,
              expanded: expanded,
              index: index,
              onToggle: () => setState(() {
                if (expanded) {
                  _expanded.remove(section.id);
                } else {
                  _expanded.add(section.id);
                }
              }),
              onSpansChanged: (spans) =>
                  _updateSection(section.copyWith(spans: spans)),
              onRemove: _sections.length > 1
                  ? () => _removeSection(section.id)
                  : null,
              onPickImage: () => _pickImage(section),
              onRemoveImage: () =>
                  _updateSection(section.copyWith(clearImage: true)),
            );
          },
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: PopupMenuButton<RuleSectionKind>(
            tooltip: 'Ajouter une section',
            onSelected: _addSection,
            itemBuilder: (_) => _availableKinds
                .map(
                  (k) => PopupMenuItem(
                    value: k,
                    child: Text(k.label),
                  ),
                )
                .toList(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_circle_outline, color: scheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Ajouter une section',
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionBubble extends StatelessWidget {
  final RuleSection section;
  final bool expanded;
  final int index;
  final VoidCallback onToggle;
  final ValueChanged<List<RuleTextSpan>> onSpansChanged;
  final VoidCallback? onRemove;
  final VoidCallback onPickImage;
  final VoidCallback onRemoveImage;

  const _SectionBubble({
    super.key,
    required this.section,
    required this.expanded,
    required this.index,
    required this.onToggle,
    required this.onSpansChanged,
    this.onRemove,
    required this.onPickImage,
    required this.onRemoveImage,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                child: Row(
                  children: [
                    ReorderableDragStartListener(
                      index: index,
                      child: Icon(
                        Icons.drag_handle,
                        color: scheme.onSurfaceVariant,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        section.displayTitle,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (section.imageUrl != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(
                          Icons.image_outlined,
                          size: 18,
                          color: scheme.primary,
                        ),
                      ),
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      color: scheme.onSurfaceVariant,
                    ),
                    if (onRemove != null)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Supprimer la section',
                        onPressed: onRemove,
                        icon: Icon(
                          Icons.close,
                          size: 18,
                          color: Colors.red.shade400,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (expanded) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RichSectionTextField(
                      key: ValueKey('${section.id}_${section.spans.length}'),
                      initialSpans: section.spans,
                      onChanged: onSpansChanged,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: onPickImage,
                          icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                          label: const Text('Image'),
                        ),
                        if (section.imageUrl != null)
                          TextButton.icon(
                            onPressed: onRemoveImage,
                            icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                            label: const Text('Retirer l\'image'),
                          ),
                      ],
                    ),
                    if (section.imageUrl != null) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          section.imageUrl!,
                          height: 160,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => const SizedBox(
                            height: 48,
                            child: Center(child: Icon(Icons.broken_image_outlined)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Affichage accordéon en lecture seule.
class ModularRuleBodyView extends StatefulWidget {
  final List<RuleSection> sections;
  final Color? accent;

  const ModularRuleBodyView({
    super.key,
    required this.sections,
    this.accent,
  });

  @override
  State<ModularRuleBodyView> createState() => _ModularRuleBodyViewState();
}

class _ModularRuleBodyViewState extends State<ModularRuleBodyView> {
  final _expanded = <String>{};
  final _showImages = <String>{};

  @override
  Widget build(BuildContext context) {
    if (widget.sections.isEmpty) {
      return Text(
        'Aucun contenu.',
        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final accent = widget.accent ?? scheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final section in widget.sections) ...[
          Material(
            color: accent.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => setState(() {
                if (_expanded.contains(section.id)) {
                  _expanded.remove(section.id);
                } else {
                  _expanded.add(section.id);
                }
              }),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            section.displayTitle,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (section.imageUrl != null)
                          Icon(Icons.image_outlined, size: 16, color: accent),
                        Icon(
                          _expanded.contains(section.id)
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 20,
                        ),
                      ],
                    ),
                    if (_expanded.contains(section.id) &&
                        section.plainText.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      RichSectionText(spans: section.spans),
                    ],
                    if (_expanded.contains(section.id) &&
                        section.imageUrl != null) ...[
                      const SizedBox(height: 8),
                      if (_showImages.contains(section.id))
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            section.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.broken_image_outlined),
                          ),
                        )
                      else
                        TextButton.icon(
                          onPressed: () =>
                              setState(() => _showImages.add(section.id)),
                          icon: const Icon(Icons.photo_outlined, size: 18),
                          label: const Text('Voir la pièce jointe'),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
