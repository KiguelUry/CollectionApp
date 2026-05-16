class CollectionGroup {
  final String id;
  final String name;
  final String createdBy;

  const CollectionGroup({
    required this.id,
    required this.name,
    required this.createdBy,
  });

  factory CollectionGroup.fromJson(Map<String, dynamic> json) {
    return CollectionGroup(
      id: json['id'] as String,
      name: json['name'] as String,
      createdBy: json['created_by'] as String,
    );
  }
}
