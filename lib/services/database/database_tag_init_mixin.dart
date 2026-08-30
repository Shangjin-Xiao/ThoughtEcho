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
      // sqflite 返回的是只读 map，这里复制一份，后续可就地更新以反映修复结果
      final idToRow = <String, Map<String, dynamic>>{
        for (final row in existingCategories)
          row['id'] as String: Map<String, dynamic>.from(row),
      };
      var inserted = 0;
      var repaired = 0;
      var adopted = 0;

      await db.transaction((txn) async {
        // 第一轮：按固定 ID 修复已存在的系统标签（名称 + is_default）。
        // 必须先于按名称的收编，否则一个系统标签顶着另一个系统标签的名字时
        // （例如 default_anime 的名称被写成"每日一言"），会被当成占位行收编掉，
        // 它原有的笔记归类就跟着迁走了。
        for (final category in defaultCategories) {
          final existingById = idToRow[category.id];
          if (existingById == null) continue;

          final currentName = existingById['name'] as String? ?? '';
          final isDefault = existingById['is_default'];
          final needNameFix =
              currentName.toLowerCase() != category.name.toLowerCase();
          final needDefaultFix = !(isDefault == 1 || isDefault == true);
          if (!needNameFix && !needDefaultFix) continue;

          await txn.update(
            'categories',
            {
              'name': category.name,
              'is_default': 1,
              // last_modified 必须前进，否则这次修复会在下一轮 LWW 合并里被旧值盖回去
              'last_modified': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [category.id],
          );
          existingById['name'] = category.name;
          existingById['is_default'] = 1;
          repaired++;
          logDebug('修复系统标签 ${category.id}: name=${category.name}');
        }

        // 名称索引按第一轮之后的状态重建：改过名的系统标签不该再占着别人的名字。
        final nameLowerToRow = <String, Map<String, dynamic>>{};
        for (final row in idToRow.values) {
          final key = (row['name'] as String? ?? '').toLowerCase();
          nameLowerToRow.putIfAbsent(key, () => row);
        }

        // 第二轮：补建仍然缺失的系统标签。
        for (final category in defaultCategories) {
          if (idToRow.containsKey(category.id)) continue;
          final nowUtc = DateTime.now().toUtc().toIso8601String();
          final nameKey = category.name.toLowerCase();

          // 同名标签被别的 ID 占着（导入数据带进来的普通标签）。只按名称跳过的话，
          // 系统标签会永远建不出来，所以把占位行收编：迁移笔记关联后再删掉。
          // 占位行本身是系统标签时不能收编——那是另一个系统标签的数据，
          // 它的名称已在第一轮修回，这里直接新建即可。
          final impostor = nameLowerToRow[nameKey];
          final impostorId = impostor?['id'] as String?;
          if (impostorId != null &&
              !_DatabaseServiceBase.systemTagIds.contains(impostorId)) {
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
          nameLowerToRow.putIfAbsent(nameKey, () => newRow);
          inserted++;
          logDebug('添加默认一言标签: ${category.name}');
        }

        // 兜底：默认列表之外的系统标签（隐藏标签等）若被写成普通标签，一并修回。
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

    // 这里绝不能用 ConflictAlgorithm.replace：SQLite 的 REPLACE 是 DELETE+INSERT，
    // 若规范行已被另一条恢复/启动路径抢先建出，删除会经 quote_tags 的
    // ON DELETE CASCADE 连带清掉它已有的笔记关联。改为 ignore + 显式 update。
    await txn.insert(
        'categories',
        {
          'id': category.id,
          'name': category.name,
          'is_default': 1,
          'icon_name': category.iconName,
          'last_modified': timestamp,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
    await txn.update(
      'categories',
      {
        'name': category.name,
        'is_default': 1,
        'icon_name': category.iconName,
        'last_modified': timestamp,
      },
      where: 'id = ?',
      whereArgs: [category.id],
    );

    // 笔记可能同时挂着新旧两个标签，用 OR IGNORE 避开主键冲突
    await txn.rawInsert(
      'INSERT OR IGNORE INTO quote_tags(quote_id, tag_id) '
      'SELECT quote_id, ? FROM quote_tags WHERE tag_id = ?',
      [category.id, oldId],
    );
    await txn.delete('quote_tags', where: 'tag_id = ?', whereArgs: [oldId]);
    await txn.update(
      'quotes',
      {
        'category_id': category.id,
        // last_modified 参与笔记的 LWW 比较：不推进的话，下一次合并会用带旧
        // category_id 的远端行把这次迁移盖回去
        'last_modified': timestamp,
      },
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
    ];
  }
}
