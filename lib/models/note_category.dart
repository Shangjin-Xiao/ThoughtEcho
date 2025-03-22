class NoteCategory {
  final String id;
  final String name;
  final bool isDefault;
  final String? iconName;

  NoteCategory({
    required this.id,
    required this.name,
    this.isDefault = false,
    this.iconName,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'is_default': isDefault ? 1 : 0,
      'icon_name': iconName,
    };
  }

  factory NoteCategory.fromMap(Map<String, dynamic> map) {
    return NoteCategory(
      id: map['id'],
      name: map['name'],
      isDefault: map['is_default'] == 1,
      iconName: map['icon_name'],
    );
  }
}
