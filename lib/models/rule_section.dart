import 'dart:convert';

/// Sections prédéfinies d'une variante de règles.
enum RuleSectionKind {
  setup('setup', 'Mise en place'),
  summary('summary', 'Résumé / Déroulement'),
  exampleTurn('example_turn', 'Exemple d\'un tour'),
  objective('objective', 'Objectif'),
  scoring('scoring', 'Comptage des points'),
  other('other', 'Autre');

  const RuleSectionKind(this.key, this.label);
  final String key;
  final String label;

  static RuleSectionKind? fromKey(String? key) {
    if (key == null) return null;
    for (final k in RuleSectionKind.values) {
      if (k.key == key) return k;
    }
    return null;
  }
}

class RuleTextSpan {
  final String text;
  final bool bold;

  const RuleTextSpan({required this.text, this.bold = false});

  Map<String, dynamic> toJson() => {
        't': text,
        if (bold) 'b': true,
      };

  factory RuleTextSpan.fromJson(Map<String, dynamic> json) {
    return RuleTextSpan(
      text: json['t'] as String? ?? '',
      bold: json['b'] == true,
    );
  }
}

class RuleSection {
  final String id;
  final RuleSectionKind kind;
  final String? customTitle;
  final List<RuleTextSpan> spans;
  final String? imageUrl;

  const RuleSection({
    required this.id,
    required this.kind,
    this.customTitle,
    this.spans = const [],
    this.imageUrl,
  });

  String get displayTitle =>
      kind == RuleSectionKind.other
          ? (customTitle?.trim().isNotEmpty == true
              ? customTitle!.trim()
              : 'Autre')
          : kind.label;

  String get plainText => spans.map((s) => s.text).join();

  RuleSection copyWith({
    String? id,
    RuleSectionKind? kind,
    String? customTitle,
    List<RuleTextSpan>? spans,
    String? imageUrl,
    bool clearImage = false,
  }) {
    return RuleSection(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      customTitle: customTitle ?? this.customTitle,
      spans: spans ?? this.spans,
      imageUrl: clearImage ? null : (imageUrl ?? this.imageUrl),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.key,
        if (customTitle != null && customTitle!.trim().isNotEmpty)
          'custom_title': customTitle,
        'spans': spans.map((s) => s.toJson()).toList(),
        if (imageUrl != null) 'image_url': imageUrl,
      };

  factory RuleSection.fromJson(Map<String, dynamic> json) {
    final spansRaw = json['spans'] as List? ?? const [];
    return RuleSection(
      id: json['id'] as String? ?? '',
      kind: RuleSectionKind.fromKey(json['kind'] as String?) ??
          RuleSectionKind.summary,
      customTitle: json['custom_title'] as String?,
      spans: spansRaw
          .map((e) => RuleTextSpan.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      imageUrl: json['image_url'] as String?,
    );
  }
}

/// Encode / décode le corps d'une variante (JSON modulaire ou markdown legacy).
class RuleBodyCodec {
  static const int version = 2;

  static List<RuleSection> decode(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return [];

    if (trimmed.startsWith('{')) {
      try {
        final map = jsonDecode(trimmed) as Map<String, dynamic>;
        if (map['v'] == version && map['sections'] is List) {
          return (map['sections'] as List)
              .map(
                (e) => RuleSection.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .toList();
        }
      } catch (_) {}
    }

    return [
      RuleSection(
        id: 'legacy',
        kind: RuleSectionKind.summary,
        spans: [RuleTextSpan(text: trimmed)],
      ),
    ];
  }

  static String encode(List<RuleSection> sections) {
    return jsonEncode({
      'v': version,
      'sections': sections.map((s) => s.toJson()).toList(),
    });
  }

  static bool isEmpty(List<RuleSection> sections) {
    if (sections.isEmpty) return true;
    return sections.every(
      (s) => s.plainText.trim().isEmpty && s.imageUrl == null,
    );
  }
}
