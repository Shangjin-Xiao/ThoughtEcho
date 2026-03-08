part of '../database_service.dart';

/// Mixin providing default category initialization for DatabaseService.
mixin _DatabaseCategoryInitMixin on ChangeNotifier {
  /// 初始化默认一言分类标签
  Future<void> initDefaultHitokotoCategories() async {
    if (kIsWeb) {
      // Web 平台逻辑：检查内存中的 _categoryStore
      final defaultCategories = _getDefaultHitokotoCategories();
      final existingNamesLower =
          _categoryStore.map((c) => c.name.toLowerCase()).toSet();
      for (final category in defaultCategories) {
        if (!existingNamesLower.contains(category.name.toLowerCase())) {
          _categoryStore.add(category);
        }
      }
      // 确保流更新
      if (!_categoriesController.isClosed) {
        _categoriesController.add(List.unmodifiable(_categoryStore));
      }
      return;
    }

    try {
      // 首先确保数据库已初始化
      if (_database == null) {
        logDebug('数据库尚未初始化，尝试先进行初始化');
        try {
          await init();
        } catch (e) {
          logDebug('数据库初始化失败，但仍将尝试创建默认标签: $e');
        }
      }

      // 即使init()失败，也尝试获取数据库，如果還是null則提前返回
      if (_database == null) {
        logDebug('数据库仍为null，无法创建默认标签');
        return;
      }

      final db = database;
      final defaultCategories = _getDefaultHitokotoCategories();

      // 1. 一次性查询所有现有分类名称（小写）
      final existingCategories = await db.query(
        'categories',
        columns: ['name', 'id'],
      );
      final existingNamesLower = existingCategories
          .map((row) => (row['name'] as String?)?.toLowerCase())
          .where((name) => name != null)
          .toSet();

      // 同时创建ID到名称的映射，用于检查默认ID是否已被其它名称使用
      final existingIdToName = {
        for (var row in existingCategories)
          row['id'] as String: row['name'] as String,
      };

      // 2. 筛选出数据库中尚不存在的默认分类
      final categoriesToAdd = defaultCategories
          .where(
            (category) =>
                !existingNamesLower.contains(category.name.toLowerCase()),
          )
          .toList();

      // 3. 检查默认ID是否已被其他名称使用，如果是，需要更新名称
      final idsToUpdate = <String, String>{};
      for (final category in defaultCategories) {
        if (existingIdToName.containsKey(category.id) &&
            existingIdToName[category.id]!.toLowerCase() !=
                category.name.toLowerCase()) {
          // 已存在此ID但名称不同，需要更新
          idsToUpdate[category.id] = category.name;
        }
      }

      // 4. 如果有需要添加的分类，则使用批处理插入
      final batch = db.batch();

      // 先处理更新
      for (final entry in idsToUpdate.entries) {
        batch.update(
          'categories',
          {'name': entry.value, 'is_default': 1},
          where: 'id = ?',
          whereArgs: [entry.key],
        );
        logDebug('更新ID为${entry.key}的分类名称为: ${entry.value}');
      }

      // 再处理新增
      for (final category in categoriesToAdd) {
        // 跳过ID已经存在但名称不同的情况（已在上面处理）
        if (idsToUpdate.containsKey(category.id)) {
          continue;
        }
        batch.insert(
            'categories',
            {
              'id': category.id,
              'name': category.name,
              'is_default': category.isDefault ? 1 : 0,
              'icon_name': category.iconName,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
        logDebug('添加默认一言分类: ${category.name}');
      }

      // 提交批处理
      if (categoriesToAdd.isNotEmpty || idsToUpdate.isNotEmpty) {
        await batch.commit(noResult: true);
        logDebug(
          '批量处理了 ${categoriesToAdd.length} 个新分类和 ${idsToUpdate.length} 个更新',
        );
      } else {
        logDebug('所有默认分类已存在，无需添加');
      }

      // 更新分类流
      await _updateCategoriesStream();
    } catch (e) {
      logDebug('初始化默认一言分类出错: $e');
    }
  }

  /// 获取默认一言分类列表
  List<NoteCategory> _getDefaultHitokotoCategories() {
    return [
      NoteCategory(
        id: defaultCategoryIdHitokoto, // 使用固定 ID
        name: '每日一言',
        isDefault: true,
        iconName: 'format_quote',
      ),
      NoteCategory(
        id: defaultCategoryIdAnime, // 使用固定 ID
        name: '动画',
        isDefault: true,
        iconName: '🎬',
      ),
      NoteCategory(
        id: defaultCategoryIdComic, // 使用固定 ID
        name: '漫画',
        isDefault: true,
        iconName: '📚',
      ),
      NoteCategory(
        id: defaultCategoryIdGame, // 使用固定 ID
        name: '游戏',
        isDefault: true,
        iconName: '🎮',
      ),
      NoteCategory(
        id: defaultCategoryIdNovel, // 使用固定 ID
        name: '文学',
        isDefault: true,
        iconName: '📖',
      ),
      NoteCategory(
        id: defaultCategoryIdOriginal, // 使用固定 ID
        name: '原创',
        isDefault: true,
        iconName: '✨',
      ),
      NoteCategory(
        id: defaultCategoryIdInternet, // 使用固定 ID
        name: '来自网络',
        isDefault: true,
        iconName: '🌐',
      ),
      NoteCategory(
        id: defaultCategoryIdOther, // 使用固定 ID
        name: '其他',
        isDefault: true,
        iconName: '📦',
      ),
      NoteCategory(
        id: defaultCategoryIdMovie, // 使用固定 ID
        name: '影视',
        isDefault: true,
        iconName: '🎞️',
      ),
      NoteCategory(
        id: defaultCategoryIdPoem, // 使用固定 ID
        name: '诗词',
        isDefault: true,
        iconName: '🪶',
      ),
      NoteCategory(
        id: defaultCategoryIdMusic, // 使用固定 ID
        name: '网易云',
        isDefault: true,
        iconName: '🎧',
      ),
      NoteCategory(
        id: defaultCategoryIdPhilosophy, // 使用固定 ID
        name: '哲学',
        isDefault: true,
        iconName: '🤔',
      ),
    ];
  }

}
