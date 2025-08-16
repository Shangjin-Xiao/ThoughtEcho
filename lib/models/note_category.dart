class NoteCategory {
  final String id;
  final String name;
  final bool isDefault;
  final String? iconName;
  final String? lastModified;

  NoteCategory({
    required this.id,
    required this.name,
    this.isDefault = false,
    this.iconName,
    this.lastModified,
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
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'is_default': isDefault ? 1 : 0,
      'icon_name': iconName,
      'last_modified': lastModified,
    };
  }

  /// 修复：从Map构建NoteCategory对象，增加数据验证
  factory NoteCategory.fromMap(Map<String, dynamic> map) {
    try {
      final id = map['id']?.toString() ?? '';
      final name = map['name']?.toString() ?? '';

      if (id.isEmpty) {
        throw ArgumentError('分类ID不能为空');
      }

      if (name.isEmpty) {
        throw ArgumentError('分类名称不能为空');
      }

      return NoteCategory(
        id: id,
        name: name,
        isDefault: map['is_default'] == 1 || map['is_default'] == true,
        iconName: map['icon_name']?.toString(),
        lastModified: map['last_modified']?.toString(),
      );
    } catch (e) {
      throw FormatException('解析NoteCategory Map失败: $e, Map: $map');
    }
  }

  /// 修复：添加copyWith方法
  NoteCategory copyWith({
    String? id,
    String? name,
    bool? isDefault,
    String? iconName,
    String? lastModified,
  }) {
    return NoteCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      isDefault: isDefault ?? this.isDefault,
      iconName: iconName ?? this.iconName,
      lastModified: lastModified ?? this.lastModified,
    );
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
