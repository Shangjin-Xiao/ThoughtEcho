part of '../database_service.dart';

/// Mixin providing category CRUD operations for DatabaseService.
mixin _DatabaseTagMixin on _DatabaseServiceBase {
  /// 获取所有标签列表
  @override
  Future<List<Map<String, dynamic>>> getAllTagMaps() async {
    try {
      if (kIsWeb) {
        return _tagStore.map((c) => c.toJson()).toList();
      }
      final db = database;
      return await db.query('categories');
    } catch (e) {
      logDebug('获取所有标签失败: $e');
      return [];
    }
  }

  @override
  Future<List<NoteTag>> getTags() async {
    if (kIsWeb) {
      return _moveHiddenTagToBottom(
        List<NoteTag>.from(_tagStore),
      );
    }
    try {
      final db = await safeDatabase;
      final maps = await db.query('categories');
      final categories = maps.map((map) => NoteTag.fromMap(map)).toList();
      return _moveHiddenTagToBottom(categories);
    } catch (e) {
      logDebug('获取标签错误: $e');
      return [];
    }
  }

  List<NoteTag> _moveHiddenTagToBottom(
    List<NoteTag> categories,
  ) {
    final hiddenCategories = categories
        .where((category) => category.id == _DatabaseServiceBase.hiddenTagId)
        .toList();
    final normalCategories = categories
        .where((category) => category.id != _DatabaseServiceBase.hiddenTagId)
        .toList();
    return [...normalCategories, ...hiddenCategories];
  }

  /// 修复：添加一条标签，统一名称唯一性检查
  @override
  Future<void> addTag(String name, {String? iconName}) async {
    // 统一的参数验证
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw Exception('标签名称不能为空');
    }
    if (trimmedName.length > 50) {
      throw Exception('标签名称不能超过50个字符');
    }

    if (kIsWeb) {
      // 检查是否已存在同名标签（不区分大小写）
      final exists = _tagStore.any(
        (c) => c.name.toLowerCase() == trimmedName.toLowerCase(),
      );
      if (exists) {
        throw Exception('已存在相同名称的标签');
      }

      final newCategory = NoteTag(
        id: _uuid.v4(),
        name: trimmedName,
        isDefault: false,
        iconName: iconName?.trim() ?? "",
      );
      _tagStore.add(newCategory);
      _tagsController.add(_tagStore);
      notifyListeners();
      notifyLocalDataChangedForParts();
      return;
    }

    final db = database;

    // 统一的唯一性检查逻辑
    await _validateTagNameUnique(db, trimmedName);

    final id = _uuid.v4();
    final categoryMap = {
      'id': id,
      'name': trimmedName,
      'is_default': 0,
      'icon_name': iconName?.trim() ?? "",
      'last_modified': DateTime.now().toUtc().toIso8601String(),
    };
    await db.insert(
      'categories',
      categoryMap,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await updateTagsStreamForParts();
    notifyListeners();
    notifyLocalDataChangedForParts();
  }

  /// 修复：统一的标签名称唯一性验证
  Future<void> _validateTagNameUnique(
    Database db,
    String name, {
    String? excludeId,
  }) async {
    final whereClause =
        excludeId != null ? 'LOWER(name) = ? AND id != ?' : 'LOWER(name) = ?';
    final whereArgs = excludeId != null
        ? [name.toLowerCase(), excludeId]
        : [name.toLowerCase()];

    final existing = await db.query(
      'categories',
      where: whereClause,
      whereArgs: whereArgs,
      limit: 1,
    );

    if (existing.isNotEmpty) {
      throw Exception('已存在相同名称的标签');
    }
  }

  /// 添加一条标签（使用指定ID）
  @override
  Future<void> addTagWithId(
    String id,
    String name, {
    String? iconName,
  }) async {
    // 检查参数
    if (name.trim().isEmpty) {
      throw Exception('标签名称不能为空');
    }
    if (id.trim().isEmpty) {
      throw Exception('标签ID不能为空');
    }

    if (kIsWeb) {
      // 检查是否已存在同名标签
      final exists = _tagStore.any(
        (c) => c.name.toLowerCase() == name.toLowerCase(),
      );
      if (exists) {
        logDebug('Web平台: 已存在相同名称的标签 "$name"，但将继续使用');
      }

      // 检查ID是否已被占用
      final idExists = _tagStore.any((c) => c.id == id);
      if (idExists) {
        // 如果ID已存在，不报错，静默更新此标签
        final index = _tagStore.indexWhere((c) => c.id == id);
        if (index != -1) {
          _tagStore[index] = NoteTag(
            id: id,
            name: name,
            isDefault: _tagStore[index].isDefault,
            iconName: iconName ?? _tagStore[index].iconName,
          );
        }
      } else {
        // 创建新标签
        final newCategory = NoteTag(
          id: id,
          name: name,
          isDefault: false,
          iconName: iconName ?? "",
        );
        _tagStore.add(newCategory);
      }

      _tagsController.add(_tagStore);
      notifyListeners();
      notifyLocalDataChangedForParts();
      return;
    }

    // 确保数据库已初始化
    if (_DatabaseServiceBase._database == null) {
      try {
        await init();
      } catch (e) {
        logDebug('添加标签前初始化数据库失败: $e');
        throw Exception('数据库未初始化，无法添加标签');
      }
    }

    final db = database;

    try {
      // 使用事务确保操作的原子性
      await db.transaction((txn) async {
        // 检查是否已存在同名标签
        final existing = await txn.query(
          'categories',
          where: 'LOWER(name) = ?',
          whereArgs: [name.toLowerCase()],
        );

        if (existing.isNotEmpty) {
          // 如果存在同名标签但ID不同，记录警告但继续
          final existingId = existing.first['id'] as String;
          if (existingId != id) {
            logDebug('警告: 已存在相同名称的标签 "$name"，但将继续使用指定ID创建');
          }
        }

        // 检查ID是否已被占用
        final existingById = await txn.query(
          'categories',
          where: 'id = ?',
          whereArgs: [id],
        );

        if (existingById.isNotEmpty) {
          // 如果ID已存在，更新此标签
          final categoryMap = {
            'name': name,
            'icon_name': iconName ?? "",
            'last_modified': DateTime.now().toUtc().toIso8601String(),
          };
          await txn.update(
            'categories',
            categoryMap,
            where: 'id = ?',
            whereArgs: [id],
          );
          logDebug('更新ID为 $id 的现有标签为 "$name"');
        } else {
          // 创建新标签，使用指定的ID
          final categoryMap = {
            'id': id,
            'name': name,
            'is_default': 0,
            'icon_name': iconName ?? "",
            'last_modified': DateTime.now().toUtc().toIso8601String(),
          };
          await txn.insert(
            'categories',
            categoryMap,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          logDebug('使用ID $id 创建新标签 "$name"');
        }
      });

      // 操作成功后更新流和通知侦听器
      await updateTagsStreamForParts();
      notifyListeners();
      notifyLocalDataChangedForParts();
    } catch (e) {
      logDebug('添加指定ID标签失败: $e');
      // 重试一次作为回退方案
      try {
        final categoryMap = {
          'id': id,
          'name': name,
          'is_default': 0,
          'icon_name': iconName ?? "",
          'last_modified': DateTime.now().toUtc().toIso8601String(),
        };
        await db.insert(
          'categories',
          categoryMap,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await updateTagsStreamForParts();

        // 修复：导入/恢复完成后必须重建媒体引用，确保引用表准确
        logInfo('导入完成，开始重建媒体引用记录...');
        await MediaReferenceService.migrateExistingQuotes();

        notifyListeners();
        notifyLocalDataChangedForParts();
        logDebug('通过回退方式成功添加标签');
      } catch (retryError) {
        logDebug('重试添加标签也失败: $retryError');
        throw Exception('无法添加标签: $e');
      }
    }
  }

  /// 监听标签流
  @override
  Stream<List<NoteTag>> watchTags() {
    updateTagsStreamForParts();
    return _tagsController.stream;
  }

  /// 修复：删除指定标签，增加级联删除和孤立数据清理
  @override
  Future<void> deleteTag(String id) async {
    // 系统标签（如隐藏标签）不允许删除
    if (id == _DatabaseServiceBase.hiddenTagId) {
      throw Exception('系统标签不允许删除');
    }

    if (kIsWeb) {
      _tagStore.removeWhere((category) => category.id == id);
      _tagsController.add(_tagStore);
      notifyListeners();
      notifyLocalDataChangedForParts();
      return;
    }

    final db = database;

    await db.transaction((txn) async {
      // 1. 检查是否有笔记使用此标签
      final quotesUsingCategory = await txn.query(
        'quotes',
        where: 'category_id = ?',
        whereArgs: [id],
        columns: ['id'],
      );

      // 2. 清理使用此标签的笔记的category_id字段
      if (quotesUsingCategory.isNotEmpty) {
        await txn.update(
          'quotes',
          {'category_id': null},
          where: 'category_id = ?',
          whereArgs: [id],
        );
        logDebug('已清理 ${quotesUsingCategory.length} 条笔记的标签关联');
      }

      // 3. 删除quote_tags表中的相关记录（CASCADE会自动处理，但为了确保一致性）
      final deletedTagRelations = await txn.delete(
        'quote_tags',
        where: 'tag_id = ?',
        whereArgs: [id],
      );

      if (deletedTagRelations > 0) {
        logDebug('已删除 $deletedTagRelations 条标签关联记录');
      }

      // 4. 最后删除标签本身
      await txn.delete('categories', where: 'id = ?', whereArgs: [id]);
    });

    // 清理缓存
    clearAllCacheForParts();

    await updateTagsStreamForParts();
    notifyListeners();
    notifyLocalDataChangedForParts();

    logDebug('标签删除完成，ID: $id');
  }

  @override
  Future<void> _updateTagsStream() async {
    final categories = await getTags();
    if (_tagsController.isClosed) return;
    _tagsController.add(categories);
  }

  /// 更新标签信息
  @override
  Future<void> updateTag(
    String id,
    String name, {
    String? iconName,
  }) async {
    // 系统标签（如隐藏标签）不允许修改
    if (id == _DatabaseServiceBase.hiddenTagId) {
      throw Exception('系统标签不允许修改');
    }

    // 检查参数
    if (name.trim().isEmpty) {
      throw Exception('标签名称不能为空');
    }
    if (kIsWeb) {
      // Web 平台逻辑
      final index = _tagStore.indexWhere((c) => c.id == id);
      if (index == -1) {
        throw Exception('找不到指定的标签');
      }
      // 检查新名称是否与 *其他* 标签冲突
      final newNameLower = name.toLowerCase();
      final conflict = _tagStore.any(
        (c) => c.id != id && c.name.toLowerCase() == newNameLower,
      );
      if (conflict) {
        throw Exception('已存在相同名称的标签');
      }
      final updatedCategory = NoteTag(
        id: id, // ID 保持不变
        name: name,
        isDefault: _tagStore[index].isDefault, // isDefault 状态保持不变
        iconName: iconName ?? _tagStore[index].iconName,
      );
      _tagStore[index] = updatedCategory;
      _tagsController.add(_tagStore);
      notifyListeners();
      notifyLocalDataChangedForParts();
      return;
    }

    final db = database;

    // 检查要更新的标签是否存在
    final currentCategories = await db.query(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (currentCategories.isEmpty) {
      throw Exception('找不到指定的标签');
    }

    final currentCategory = NoteTag.fromMap(currentCategories.first);

    /// 修复：使用统一的名称唯一性验证
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw Exception('标签名称不能为空');
    }
    if (trimmedName.length > 50) {
      throw Exception('标签名称不能超过50个字符');
    }

    // 只有当新名称与当前名称不同时，才检查重复
    if (trimmedName.toLowerCase() != currentCategory.name.toLowerCase()) {
      await _validateTagNameUnique(db, trimmedName, excludeId: id);
    }

    final categoryMap = {
      'name': trimmedName,
      'icon_name':
          iconName?.trim() ?? currentCategory.iconName, // 如果未提供新图标，则保留旧图标
      'last_modified': DateTime.now().toUtc().toIso8601String(),
      // 'is_default' 字段不应在此处更新，它在创建时确定
    };

    await db.update(
      'categories',
      categoryMap,
      where: 'id = ?',
      whereArgs: [id],
    );

    await updateTagsStreamForParts();
    notifyListeners();
    notifyLocalDataChangedForParts();
  }

  /// 根据 ID 获取标签
  @override
  Future<NoteTag?> getTagById(String id) async {
    if (kIsWeb) {
      try {
        return _tagStore.firstWhere((cat) => cat.id == id);
      } catch (e) {
        logDebug('在内存中找不到 ID 为 $id 的标签: $e');
        return null;
      }
    }

    try {
      final db = database;
      final maps = await db.query(
        'categories',
        where: 'id = ?',
        whereArgs: [id],
      );

      if (maps.isEmpty) {
        return null;
      }

      return NoteTag.fromMap(maps.first);
    } catch (e) {
      logDebug('根据 ID 获取标签失败: $e');
      return null;
    }
  }

  /// 根据一组 ID 批量获取标签
  @override
  Future<Map<String, NoteTag>> getTagsByIds(Iterable<String> ids) async {
    final idList = ids.where((id) => id.isNotEmpty).toSet().toList();
    if (idList.isEmpty) {
      return {};
    }

    if (kIsWeb) {
      final result = <String, NoteTag>{};
      final idSet = idList.toSet();
      for (final tag in _tagStore) {
        if (idSet.contains(tag.id)) {
          result[tag.id] = tag;
        }
      }
      return result;
    }

    try {
      final db = database;
      final placeholders = List.filled(idList.length, '?').join(',');
      final maps = await db.query(
        'categories',
        where: 'id IN ($placeholders)',
        whereArgs: idList,
      );

      final result = <String, NoteTag>{};
      for (final map in maps) {
        final tag = NoteTag.fromMap(map);
        result[tag.id] = tag;
      }
      return result;
    } catch (e) {
      logDebug('批量根据 ID 获取标签失败: $e');
      return {};
    }
  }
}
