class NoteTag {
  final String id;
  final String name;
  final bool isDefault;
  final String? iconName;

  NoteTag({
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

  factory NoteTag.fromMap(Map<String, dynamic> map) {
    return NoteTag(
      id: map['id'],
      name: map['name'],
      isDefault: map['is_default'] == 1,
      iconName: map['icon_name'],
    );
  }
}
