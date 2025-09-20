class NoteCategory {
  final String id;
  final String name;
  final bool isDefault;
  final String? iconName;
  final String? lastModified;
  final String? icon;

  NoteCategory({
    required this.id,
    required this.name,
    this.isDefault = false,
    this.iconName,
    this.lastModified,
    this.icon,
  })  : assert(id.isNotEmpty, '分类ID不能为空'),
        assert(name.isNotEmpty, '分类名称不能为空'),
        assert(name.length <= 50, '分类名称不能超过50字符');

  /// 修复：添加数据验证方法
  static bool isValidName(String name) {
    return name.trim().isNotEmpty && name.trim().length <= 50;
  }

  static bool isValidId(String id) {
    return id.trim().isNotEmpty;
  }

  /// 修复：创建验证过的NoteCategory实例
  factory NoteCategory.validated({
    required String id,
    required String name,
    bool isDefault = false,
    String? iconName,
    String? icon,
  }) {
    final trimmedId = id.trim();
    final trimmedName = name.trim();

    if (!isValidId(trimmedId)) {
      throw ArgumentError('分类ID无效：ID不能为空');
    }

    if (!isValidName(trimmedName)) {
      throw ArgumentError('分类名称无效：名称不能为空且不能超过50字符');
    }

    return NoteCategory(
      id: trimmedId,
      name: trimmedName,
      isDefault: isDefault,
      iconName: iconName?.trim(),
      icon: icon?.trim(),
    );
  }

  NoteCategory copyWith({
    String? id,
    String? name,
    bool? isDefault,
    String? iconName,
    String? lastModified,
    String? icon,
  }) {
    return NoteCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      isDefault: isDefault ?? this.isDefault,
      iconName: iconName ?? this.iconName,
      lastModified: lastModified ?? this.lastModified,
      icon: icon ?? this.icon,
    );
  }

  factory NoteCategory.fromMap(Map<String, dynamic> map) {
    final id = map['id'] as String?;
    final name = map['name'] as String?;

    if (id == null || id.isEmpty) {
      throw ArgumentError('Category ID is missing or empty in the map.');
    }
    if (name == null || name.isEmpty) {
      throw ArgumentError('Category name is missing or empty in the map.');
    }

    return NoteCategory(
      id: id,
      name: name,
      isDefault: (map['is_default'] == 1 || map['is_default'] == true),
      iconName: map['icon_name'],
      lastModified: map['last_modified'],
      icon: map['icon'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'is_default': isDefault ? 1 : 0,
      'icon_name': iconName,
      'last_modified': lastModified,
      'icon': icon,
    };
  }

  factory NoteCategory.fromJson(Map<String, dynamic> json) {
    return NoteCategory(
      id: json['id'],
      name: json['name'],
      isDefault: json['isDefault'] ?? false,
      iconName: json['iconName'],
      lastModified: json['lastModified'],
      icon: json['icon'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'isDefault': isDefault,
      'iconName': iconName,
      'lastModified': lastModified,
      'icon': icon,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NoteCategory && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'NoteCategory(id: $id, name: $name, isDefault: $isDefault, iconName: $iconName)';
  }
}
