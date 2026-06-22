import 'collection_item.dart';

class UserList {
  final String id;
  final String ownerId;
  final String name;
  final String? description;
  final String? coverUrl;
  final String iconKey;
  final String colorHex;
  final Map<String, dynamic> metadata;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const UserList({
    required this.id,
    required this.ownerId,
    required this.name,
    this.description,
    this.coverUrl,
    this.iconKey = 'playlist_play',
    this.colorHex = '#00A896',
    this.metadata = const {},
    this.createdAt,
    this.updatedAt,
  });

  factory UserList.fromJson(Map<String, dynamic> json) {
    return UserList(
      id: json['id'] as String,
      ownerId: json['owner_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      coverUrl: json['cover_url'] as String?,
      iconKey: json['icon_key'] as String? ?? 'playlist_play',
      colorHex: json['color_hex'] as String? ?? '#00A896',
      metadata: Map<String, dynamic>.from(
        json['metadata'] as Map? ?? const {},
      ),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toInsertJson(String ownerId) => {
        'owner_id': ownerId,
        'name': name.trim(),
        'description': description?.trim(),
        'cover_url': coverUrl,
        'icon_key': iconKey,
        'color_hex': colorHex,
        'metadata': metadata,
      };

  Map<String, dynamic> toUpdateJson() => {
        'name': name.trim(),
        'description': description?.trim(),
        'cover_url': coverUrl,
        'icon_key': iconKey,
        'color_hex': colorHex,
        'metadata': metadata,
        'updated_at': DateTime.now().toIso8601String(),
      };

  UserList copyWith({
    String? name,
    String? description,
    String? coverUrl,
    String? iconKey,
    String? colorHex,
    Map<String, dynamic>? metadata,
  }) {
    return UserList(
      id: id,
      ownerId: ownerId,
      name: name ?? this.name,
      description: description ?? this.description,
      coverUrl: coverUrl ?? this.coverUrl,
      iconKey: iconKey ?? this.iconKey,
      colorHex: colorHex ?? this.colorHex,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

class UserListWithItems {
  final UserList list;
  final List<CollectionItem> items;

  const UserListWithItems({required this.list, required this.items});

  int get itemCount => items.length;

  List<String> get previewCoverUrls => items
      .map((i) => i.imageUrl)
      .whereType<String>()
      .where((u) => u.isNotEmpty)
      .take(4)
      .toList();
}
