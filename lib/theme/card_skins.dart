import 'package:flutter/material.dart';

enum CardSkinFamily { solid, gradient, special }

class CardSkin {
  final String id;
  final String label;
  final CardSkinFamily family;
  final Color accent;
  final Color edge;
  final List<Color> fill;

  const CardSkin({
    required this.id,
    required this.label,
    required this.family,
    required this.accent,
    required this.edge,
    required this.fill,
  });

  bool get isDynamic => id == 'dynamic';

  BoxDecoration decoration({Color? dynamicTint}) {
    final colors = isDynamic && dynamicTint != null
        ? [dynamicTint.withValues(alpha: 0.55), const Color(0xFF12141A)]
        : fill;
    if (colors.length == 1) {
      return BoxDecoration(
        color: colors.first,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: edge, width: 1.4),
      );
    }
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: edge, width: 1.2),
    );
  }

  static const all = <CardSkin>[
    CardSkin(id: 'ocean', label: 'Bleu Océan', family: CardSkinFamily.solid, accent: Color(0xFF1565C0), edge: Color(0xFF64B5F6), fill: [Color(0xFF0D47A1)]),
    CardSkin(id: 'sapphire', label: 'Bleu Saphir', family: CardSkinFamily.solid, accent: Color(0xFF1E3A8A), edge: Color(0xFF93C5FD), fill: [Color(0xFF1E3A8A)]),
    CardSkin(id: 'emerald', label: 'Vert Émeraude', family: CardSkinFamily.solid, accent: Color(0xFF0F766E), edge: Color(0xFF5EEAD4), fill: [Color(0xFF115E59)]),
    CardSkin(id: 'forest', label: 'Vert Forêt', family: CardSkinFamily.solid, accent: Color(0xFF166534), edge: Color(0xFF86EFAC), fill: [Color(0xFF14532D)]),
    CardSkin(id: 'ruby', label: 'Bordeaux Rubis', family: CardSkinFamily.solid, accent: Color(0xFF9F1239), edge: Color(0xFFFB7185), fill: [Color(0xFF881337)]),
    CardSkin(id: 'amber', label: 'Ambre Or', family: CardSkinFamily.solid, accent: Color(0xFFB45309), edge: Color(0xFFFBBF24), fill: [Color(0xFF92400E)]),
    CardSkin(id: 'ice', label: 'Cyan Glacé', family: CardSkinFamily.solid, accent: Color(0xFF0E7490), edge: Color(0xFF67E8F9), fill: [Color(0xFF155E75)]),
    CardSkin(id: 'terracotta', label: 'Terracotta', family: CardSkinFamily.solid, accent: Color(0xFFC2410C), edge: Color(0xFFFDBA74), fill: [Color(0xFF9A3412)]),
    CardSkin(id: 'plum', label: 'Prune', family: CardSkinFamily.solid, accent: Color(0xFF6B21A8), edge: Color(0xFFE9D5FF), fill: [Color(0xFF581C87)]),
    CardSkin(id: 'graphite', label: 'Graphite', family: CardSkinFamily.solid, accent: Color(0xFF334155), edge: Color(0xFFCBD5E1), fill: [Color(0xFF1E293B)]),
    CardSkin(id: 'silver', label: 'Argent', family: CardSkinFamily.solid, accent: Color(0xFF64748B), edge: Color(0xFFF8FAFC), fill: [Color(0xFF475569)]),
    CardSkin(id: 'slate', label: 'Ardoise / Noir initial', family: CardSkinFamily.solid, accent: Color(0xFFE8EAED), edge: Color(0xFF3A3A42), fill: [Color(0xFF16181D)]),
    CardSkin(id: 'abyss', label: 'Océan Abyssal', family: CardSkinFamily.gradient, accent: Color(0xFF38BDF8), edge: Color(0xFF7DD3FC), fill: [Color(0xFF082F49), Color(0xFF020617)]),
    CardSkin(id: 'aurora', label: 'Aurore Boréale', family: CardSkinFamily.gradient, accent: Color(0xFF34D399), edge: Color(0xFFA7F3D0), fill: [Color(0xFF064E3B), Color(0xFF1E1B4B)]),
    CardSkin(id: 'sunset', label: 'Soleil Couchant', family: CardSkinFamily.gradient, accent: Color(0xFFFB7185), edge: Color(0xFFFDA4AF), fill: [Color(0xFF9F1239), Color(0xFF7C2D12)]),
    CardSkin(id: 'galaxy', label: 'Galaxie', family: CardSkinFamily.gradient, accent: Color(0xFFC4B5FD), edge: Color(0xFFE9D5FF), fill: [Color(0xFF312E81), Color(0xFF111827)]),
    CardSkin(id: 'onyx', label: 'Or & Onyx', family: CardSkinFamily.gradient, accent: Color(0xFFFBBF24), edge: Color(0xFFFDE68A), fill: [Color(0xFF78350F), Color(0xFF0B0C0E)]),
    CardSkin(id: 'mystic', label: 'Forêt Mystique', family: CardSkinFamily.gradient, accent: Color(0xFF4ADE80), edge: Color(0xFFBBF7D0), fill: [Color(0xFF14532D), Color(0xFF052E16)]),
    CardSkin(id: 'volcano', label: 'Volcan', family: CardSkinFamily.gradient, accent: Color(0xFFF97316), edge: Color(0xFFFDBA74), fill: [Color(0xFF7F1D1D), Color(0xFF1C1917)]),
    CardSkin(id: 'glacier', label: 'Glacier', family: CardSkinFamily.gradient, accent: Color(0xFFBAE6FD), edge: Color(0xFFE0F2FE), fill: [Color(0xFF0C4A6E), Color(0xFF082F49)]),
    CardSkin(id: 'cyber', label: 'Cyber Nuit', family: CardSkinFamily.gradient, accent: Color(0xFF22D3EE), edge: Color(0xFF67E8F9), fill: [Color(0xFF083344), Color(0xFF020617)]),
    CardSkin(id: 'dune', label: 'Dune Dorée', family: CardSkinFamily.gradient, accent: Color(0xFFF59E0B), edge: Color(0xFFFDE68A), fill: [Color(0xFF92400E), Color(0xFF451A03)]),
    CardSkin(id: 'blackruby', label: 'Rubis Noir', family: CardSkinFamily.gradient, accent: Color(0xFFFB7185), edge: Color(0xFFFECDD3), fill: [Color(0xFF4C0519), Color(0xFF0B0C0E)]),
    CardSkin(id: 'midnight', label: 'Minuit', family: CardSkinFamily.gradient, accent: Color(0xFF818CF8), edge: Color(0xFFC7D2FE), fill: [Color(0xFF1E1B4B), Color(0xFF020617)]),
    CardSkin(id: 'dynamic', label: 'Couleur dynamique du jeu', family: CardSkinFamily.special, accent: Color(0xFFE8B86D), edge: Color(0xFFFDE68A), fill: [Color(0xFF1A140C), Color(0xFF0B0C0E)]),
    CardSkin(id: 'pulse', label: 'Lueur douce', family: CardSkinFamily.special, accent: Color(0xFFF472B6), edge: Color(0xFFFBCFE8), fill: [Color(0xFF3B0764), Color(0xFF0B0C0E)]),
    CardSkin(id: 'ink', label: 'Encre vive', family: CardSkinFamily.special, accent: Color(0xFF38BDF8), edge: Color(0xFF7DD3FC), fill: [Color(0xFF0B1220)]),
    CardSkin(id: 'ember', label: 'Braise', family: CardSkinFamily.special, accent: Color(0xFFEF4444), edge: Color(0xFFFCA5A5), fill: [Color(0xFF450A0A), Color(0xFF1C1917)]),
    CardSkin(id: 'lagoon', label: 'Lagon', family: CardSkinFamily.special, accent: Color(0xFF2DD4BF), edge: Color(0xFF99F6E4), fill: [Color(0xFF042F2E), Color(0xFF022C22)]),
    CardSkin(id: 'slate-night', label: 'Nuit ardoise', family: CardSkinFamily.special, accent: Color(0xFFE2E8F0), edge: Color(0xFF94A3B8), fill: [Color(0xFF111827), Color(0xFF020617)]),
  ];

  static CardSkin byId(String? id) {
    for (final skin in all) {
      if (skin.id == id) return skin;
    }
    return all.firstWhere((skin) => skin.id == 'slate');
  }

  static Color tintForGame(String title) {
    var hash = 0;
    for (final unit in title.codeUnits) {
      hash = (hash * 33 + unit) & 0x7fffffff;
    }
    return HSLColor.fromAHSL(1, (hash % 360).toDouble(), 0.55, 0.42).toColor();
  }
}

class PlayCardStyle extends ThemeExtension<PlayCardStyle> {
  final CardSkin skin;

  const PlayCardStyle(this.skin);

  @override
  PlayCardStyle copyWith({CardSkin? skin}) => PlayCardStyle(skin ?? this.skin);

  @override
  PlayCardStyle lerp(ThemeExtension<PlayCardStyle>? other, double t) {
    if (other is! PlayCardStyle) return this;
    return t < 0.5 ? this : other;
  }
}

const scaffoldBlack = Color(0xFF0B0C0E);

const backgroundChoices = <(String, Color)>[
  ('Noir profond', Color(0xFF0B0C0E)),
  ('Encre', Color(0xFF12141A)),
  ('Ardoise nuit', Color(0xFF1C1F26)),
  ('Bleu nuit', Color(0xFF0B1220)),
  ('Vert nuit', Color(0xFF0C1614)),
  ('Bordeaux nuit', Color(0xFF16080C)),
];
