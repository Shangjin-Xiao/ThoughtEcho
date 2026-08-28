part of '../database_service.dart';

/// Mixin providing default category initialization for DatabaseService.
mixin _DatabaseTagInitMixin on _DatabaseServiceBase {
  /// 初始化默认一言标签标签
  @override
  Future<void> initDefaultHitokotoTags() async {
    if (kIsWeb) {
      // Web 平台逻辑：检查内存中的 _tagStore
      final defaultCategories = _getDefaultHitokotoTags();
      final existingNamesLower =
          _tagStore.map((c) => c.name.toLowerCase()).toSet();
      for (final category in defaultCategories) {
        if (!existingNamesLower.contains(category.name.toLowerCase())) {
          _tagStore.add(category);
        }
      }
      // 修复被降级为普通标签的系统标签（同数据库分支的处理）
      for (var i = 0; i < _tagStore.length; i++) {
        final tag = _tagStore[i];
        if (tag.isDefault) continue;
        if (!_DatabaseServiceBase.systemTagIds.contains(tag.id)) continue;
        _tagStore[i] = NoteTag(
          id: tag.id,
          name: tag.name,
          isDefault: true,
          iconName: tag.iconName,
        );
      }
      // 确保流更新
      if (!_tagsController.isClosed) {
        _tagsController.add(List.unmodifiable(_tagStore));
      }
      return;
    }

    try {
      // 首先确保数据库已初始化
      if (_DatabaseServiceBase._database == null) {
        logDebug('数据库尚未初始化，尝试先进行初始化');
        try {
          await init();
        } catch (e) {
          logDebug('数据库初始化失败，但仍将尝试创建默认标签: $e');
        }
      }

      // 即使init()失败，也尝试获取数据库，如果還是null則提前返回
      if (_DatabaseServiceBase._database == null) {
        logDebug('数据库仍为null，无法创建默认标签');
        return;
      }

      final db = database;
      final defaultCategories = _getDefaultHitokotoTags();

      // 一次性读出现有标签，按 ID 和名称(小写)建索引。
      // 固定 ID 是系统标签的唯一判据：名称可以被导入数据占用，ID 不会。
      final existingCategories = await db.query(
        'categories',
        columns: ['id', 'name', 'is_default', 'icon_name'],
      );
      final idToRow = <String, Map<String, dynamic>>{
        for (final row in existingCategories) row['id'] as String: row,
      };
      final nameLowerToRow = <String, Map<String, dynamic>>{};
      for (final row in existingCategories) {
        final key = (row['name'] as String? ?? '').toLowerCase();
        nameLowerToRow.putIfAbsent(key, () => row);
      }

      var inserted = 0;
      var repaired = 0;
      var adopted = 0;

      await db.transaction((txn) async {
        for (final category in defaultCategories) {
          final nowUtc = DateTime.now().toUtc().toIso8601String();
          final nameKey = category.name.toLowerCase();

          // 1. 固定 ID 已存在：只修名称与系统属性，不动其它字段。
          final existingById = idToRow[category.id];
          if (existingById != null) {
            final currentName = existingById['name'] as String? ?? '';
            final isDefault = existingById['is_default'];
            final needNameFix = currentName.toLowerCase() != nameKey;
            final needDefaultFix = !(isDefault == 1 || isDefault == true);
            if (needNameFix || needDefaultFix) {
              await txn.update(
                'categories',
                {
                  'name': category.name,
                  'is_default': 1,
                  // last_modified 必须前进，否则这次修复会在下一轮 LWW 合并里被旧值盖回去
                  'last_modified': nowUtc,
                },
                where: 'id = ?',
                whereArgs: [category.id],
              );
              repaired++;
              logDebug('修复系统标签 ${category.id}: name=${category.name}');
            }
            continue;
          }

          // 2. 固定 ID 缺失但同名标签被别的 ID 占着（导入数据带进来的普通标签）。
          // 只按名称跳过的话，系统标签会永远建不出来，所以这里把占位的行收编：
          // 迁移它的笔记关联后再删掉，笔记不会掉标签。
          final impostor = nameLowerToRow[nameKey];
          if (impostor != null) {
            final impostorId = impostor['id'] as String;
            await _adoptTagAsSystemTag(
              txn,
              oldId: impostorId,
              category: category,
              timestamp: nowUtc,
            );
            idToRow.remove(impostorId);
            final adoptedRow = <String, dynamic>{
              'id': category.id,
              'name': category.name,
              'is_default': 1,
              'icon_name': category.iconName,
            };
            idToRow[category.id] = adoptedRow;
            nameLowerToRow[nameKey] = adoptedRow;
            adopted++;
            logDebug('同名普通标签 $impostorId 已收编为系统标签 ${category.id}');
            continue;
          }

          // 3. 全新的系统标签，直接插入。
          final newRow = <String, dynamic>{
            'id': category.id,
            'name': category.name,
            'is_default': 1,
            'icon_name': category.iconName,
            'last_modified': nowUtc,
          };
          await txn.insert(
            'categories',
            newRow,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          idToRow[category.id] = newRow;
          nameLowerToRow[nameKey] = newRow;
          inserted++;
          logDebug('添加默认一言标签: ${category.name}');
        }

        // 4. 兜底：默认列表之外的系统标签（隐藏标签等）若被写成普通标签，一并修回。
        for (final row in idToRow.values.toList()) {
          final rowId = row['id'] as String;
          if (!_DatabaseServiceBase.systemTagIds.contains(rowId)) continue;
          final isDefault = row['is_default'];
          if (isDefault == 1 || isDefault == true) continue;
          await txn.update(
            'categories',
            {
              'is_default': 1,
              'last_modified': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [rowId],
          );
          repaired++;
          logDebug('修复系统标签属性: $rowId');
        }
      });

      if (inserted > 0 || repaired > 0 || adopted > 0) {
        logDebug('系统标签处理完成：新增 $inserted，修复 $repaired，收编 $adopted');
      } else {
        logDebug('所有默认标签已存在，无需处理');
      }

      // 更新标签流
      await updateTagsStreamForParts();
    } catch (e) {
      logDebug('初始化默认一言标签出错: $e');
    }
  }

  /// 把占用了系统标签名称的普通标签收编为系统标签。
  ///
  /// categories.id 是主键且被 quote_tags / quotes 引用，不能直接改 ID，
  /// 所以先建出固定 ID 的行、把引用迁过去，最后删掉占位行。
  Future<void> _adoptTagAsSystemTag(
    Transaction txn, {
    required String oldId,
    required NoteTag category,
    required String timestamp,
  }) async {
    if (oldId == category.id) return;

    await txn.insert(
        'categories',
        {
          'id': category.id,
          'name': category.name,
          'is_default': 1,
          'icon_name': category.iconName,
          'last_modified': timestamp,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);

    // 笔记可能同时挂着新旧两个标签，用 OR IGNORE 避开主键冲突
    await txn.rawInsert(
      'INSERT OR IGNORE INTO quote_tags(quote_id, tag_id) '
      'SELECT quote_id, ? FROM quote_tags WHERE tag_id = ?',
      [category.id, oldId],
    );
    await txn.delete('quote_tags', where: 'tag_id = ?', whereArgs: [oldId]);
    await txn.update(
      'quotes',
      {'category_id': category.id},
      where: 'category_id = ?',
      whereArgs: [oldId],
    );
    await txn.delete('categories', where: 'id = ?', whereArgs: [oldId]);
  }

  /// 获取默认一言标签列表
  List<NoteTag> _getDefaultHitokotoTags() {
    return [
      NoteTag(
        id: _DatabaseServiceBase.defaultTagIdHitokoto, // 使用固定 ID
        name: '每日一言',
        isDefault: true,
        iconName: 'format_quote',
      ),
      NoteTag(
        id: _DatabaseServiceBase.defaultTagIdAnime, // 使用固定 ID
        name: '动画',
        isDefault: true,
        iconName: '🎬',
      ),
      NoteTag(
        id: _DatabaseServiceBase.defaultTagIdComic, // 使用固定 ID
        name: '漫画',
        isDefault: true,
        iconName: '📚',
      ),
      NoteTag(
        id: _DatabaseServiceBase.defaultTagIdGame, // 使用固定 ID
        name: '游戏',
        isDefault: true,
        iconName: '🎮',
      ),
      NoteTag(
        id: _DatabaseServiceBase.defaultTagIdNovel, // 使用固定 ID
        name: '文学',
        isDefault: true,
        iconName: '📖',
      ),
      NoteTag(
        id: _DatabaseServiceBase.defaultTagIdOriginal, // 使用固定 ID
        name: '原创',
        isDefault: true,
        iconName: '✨',
      ),
      NoteTag(
        id: _DatabaseServiceBase.defaultTagIdInternet, // 使用固定 ID
        name: '来自网络',
        isDefault: true,
        iconName: '🌐',
      ),
      NoteTag(
        id: _DatabaseServiceBase.defaultTagIdOther, // 使用固定 ID
        name: '其他',
        isDefault: true,
        iconName: '📦',
      ),
      NoteTag(
        id: _DatabaseServiceBase.defaultTagIdMovie, // 使用固定 ID
        name: '影视',
        isDefault: true,
        iconName: '🎞️',
      ),
      NoteTag(
        id: _DatabaseServiceBase.defaultTagIdPoem, // 使用固定 ID
        name: '诗词',
        isDefault: true,
        iconName: '🪶',
      ),
      NoteTag(
        id: _DatabaseServiceBase.defaultTagIdMusic, // 使用固定 ID
        name: '网易云',
        isDefault: true,
        iconName: '🎧',
      ),
      NoteTag(
        id: _DatabaseServiceBase.defaultTagIdPhilosophy, // 使用固定 ID
        name: '哲学',
        isDefault: true,
        iconName: '🤔',
      ),
      NoteTag(
        id: _DatabaseServiceBase.defaultTagIdJoke, // 使用固定 ID
        name: '抖机灵',
        isDefault: true,
        iconName: '😜',
      ),
    ];
  }
}
