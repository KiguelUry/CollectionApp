class CollectionGroup {
  final String id;
  final String name;
  final String createdBy;
  final String accentColor;
  final String iconKey;
  final String? avatarUrl;

  const CollectionGroup({
    required this.id,
    required this.name,
    required this.createdBy,
    this.accentColor = '#455A64',
    this.iconKey = 'groups',
    this.avatarUrl,
  });

  factory CollectionGroup.fromJson(Map<String, dynamic> json) {
    return CollectionGroup(
      id: json['id'] as String,
      name: json['name'] as String,
      createdBy: json['created_by'] as String,
      accentColor: (json['accent_color'] as String?) ?? '#455A64',
      iconKey: (json['icon_key'] as String?) ?? 'groups',
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  String get initial => name.isNotEmpty ? name[0].toUpperCase() : 'G';

  Map<String, dynamic> toUpdateJson() {
    return {
      'name': name.trim(),
      'accent_color': accentColor,
      'icon_key': iconKey,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
    };
  }

  CollectionGroup copyWith({
    String? name,
    String? accentColor,
    String? iconKey,
    String? avatarUrl,
    bool clearAvatar = false,
  }) {
    return CollectionGroup(
      id: id,
      createdBy: createdBy,
      name: name ?? this.name,
      accentColor: accentColor ?? this.accentColor,
      iconKey: iconKey ?? this.iconKey,
      avatarUrl: clearAvatar ? null : (avatarUrl ?? this.avatarUrl),
    );
  }
}

/// Couleurs proposées pour les groupes (réutilise la palette profils).
const List<String> groupAccentPresets = [
  '#455A64',
  '#37474F',
  '#E91E63',
  '#F44336',
  '#FF9800',
  '#4CAF50',
  '#009688',
  '#2196F3',
  '#546E7A',
  '#795548',
];
