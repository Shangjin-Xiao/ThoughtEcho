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

  NoteTag copyWith({
    String? id,
    String? name,
    bool? isDefault,
    String? iconName,
  }) {
    return NoteTag(
      id: id ?? this.id,
      name: name ?? this.name,
      isDefault: isDefault ?? this.isDefault,
      iconName: iconName ?? this.iconName,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'is_default': isDefault ? 1 : 0,
      'icon_name': iconName,
    };
  }

  factory NoteTag.fromMap(Map<String, dynamic> map) {
    final id = (map['id'] as String?)?.trim() ?? '';
    final name = (map['name'] as String?)?.trim() ?? '';

    return NoteTag(
      id: id,
      name: name,
      isDefault: map['is_default'] == 1 || map['is_default'] == true,
      iconName: map['icon_name'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NoteTag && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'NoteTag(id: $id, name: $name, isDefault: $isDefault, iconName: $iconName)';
  }
}
