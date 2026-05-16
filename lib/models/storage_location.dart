class StorageLocation {
  final String id;
  final String label;
  final String? groupId;

  const StorageLocation({
    required this.id,
    required this.label,
    this.groupId,
  });

  factory StorageLocation.fromJson(Map<String, dynamic> json) {
    return StorageLocation(
      id: json['id'] as String,
      label: json['label'] as String,
      groupId: json['group_id'] as String?,
    );
  }
}
