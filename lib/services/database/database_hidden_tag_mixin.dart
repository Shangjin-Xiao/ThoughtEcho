part of '../database_service.dart';

/// Mixin providing hidden tag operations for DatabaseService.
mixin _DatabaseHiddenTagMixin on ChangeNotifier {
  Future<NoteCategory?> getOrCreateHiddenTag() async {
    try {
      // 先尝试获取现有的隐藏标签
      final categories = await getCategories();
      final existingHiddenTag = categories.where((c) => c.id == hiddenTagId);
      if (existingHiddenTag.isNotEmpty) {
        // 检查并更新旧版隐藏标签（如果需要）
        final existing = existingHiddenTag.first;
        if (!existing.isDefault || existing.iconName != hiddenTagIconName) {
          // 更新为新的系统标签格式
          await _updateHiddenTagFormat();
          // 返回更新后的标签
          return NoteCategory(
            id: hiddenTagId,
            name: '隐藏',
            isDefault: true,
            iconName: hiddenTagIconName,
          );
        }
        return existing;
      }

      // 如果不存在，创建隐藏标签（系统标签，使用锁图标）
      if (kIsWeb) {
        final hiddenTag = NoteCategory(
          id: hiddenTagId,
          name: '隐藏', // UI层会根据语言显示本地化名称
          isDefault: true, // 系统标签，不可删除/编辑
          iconName: hiddenTagIconName, // 使用 emoji 小锁
        );
        _categoryStore.add(hiddenTag);
        _categoriesController.add(_categoryStore);
        notifyListeners();
        return hiddenTag;
      }

      final db = await safeDatabase;
      final categoryMap = {
        'id': hiddenTagId,
        'name': '隐藏',
        'is_default': 1, // 系统标签
        'icon_name': hiddenTagIconName, // emoji 小锁
        'last_modified': DateTime.now().toUtc().toIso8601String(),
      };

      await db.insert(
        'categories',
        categoryMap,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await _updateCategoriesStream();
      notifyListeners();

      return NoteCategory(
        id: hiddenTagId,
        name: '隐藏',
        isDefault: true,
        iconName: hiddenTagIconName,
      );
    } catch (e) {
      logDebug('获取或创建隐藏标签错误: $e');
      return null;
    }
  }

  Future<void> _updateHiddenTagFormat() async {
    try {
      if (kIsWeb) {
        final index = _categoryStore.indexWhere((c) => c.id == hiddenTagId);
        if (index >= 0) {
          _categoryStore[index] = NoteCategory(
            id: hiddenTagId,
            name: '隐藏',
            isDefault: true,
            iconName: hiddenTagIconName,
          );
          _categoriesController.add(_categoryStore);
          notifyListeners();
        }
        return;
      }

      final db = await safeDatabase;
      await db.update(
        'categories',
        {
          'is_default': 1,
          'icon_name': hiddenTagIconName,
          'last_modified': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [hiddenTagId],
      );
      await _updateCategoriesStream();
      notifyListeners();
    } catch (e) {
      logDebug('更新隐藏标签格式错误: $e');
    }
  }

  bool isHiddenTag(String tagId) {
    return tagId == hiddenTagId;
  }

  Future<void> removeHiddenTag() async {
    try {
      if (kIsWeb) {
        _categoryStore.removeWhere((c) => c.id == hiddenTagId);
        _categoriesController.add(_categoryStore);
        notifyListeners();
        return;
      }

      final db = await safeDatabase;
      // 先删除所有笔记与隐藏标签的关联
      await db.delete(
        'quote_tags',
        where: 'tag_id = ?',
        whereArgs: [hiddenTagId],
      );
      // 再删除隐藏标签本身
      await db.delete('categories', where: 'id = ?', whereArgs: [hiddenTagId]);
      await _updateCategoriesStream();
      notifyListeners();
    } catch (e) {
      logDebug('删除隐藏标签错误: $e');
    }
  }

  Future<bool> isQuoteHidden(String quoteId) async {
    try {
      if (kIsWeb) {
        final quote = _memoryStore.where((q) => q.id == quoteId);
        if (quote.isNotEmpty) {
          return quote.first.tagIds.contains(hiddenTagId);
        }
        return false;
      }

      final db = database;
      final result = await db.query(
        'quote_tags',
        where: 'quote_id = ? AND tag_id = ?',
        whereArgs: [quoteId, hiddenTagId],
        limit: 1,
      );
      return result.isNotEmpty;
    } catch (e) {
      logDebug('检查笔记是否隐藏错误: $e');
      return false;
    }
  }

  Future<List<String>> getHiddenQuoteIds() async {
    try {
      if (kIsWeb) {
        return _memoryStore
            .where((q) => q.tagIds.contains(hiddenTagId))
            .map((q) => q.id ?? '')
            .where((id) => id.isNotEmpty)
            .toList();
      }

      final db = database;
      final result = await db.query(
        'quote_tags',
        columns: ['quote_id'],
        where: 'tag_id = ?',
        whereArgs: [hiddenTagId],
      );
      return result.map((row) => row['quote_id'] as String).toList();
    } catch (e) {
      logDebug('获取隐藏笔记ID列表错误: $e');
      return [];
    }
  }

}
