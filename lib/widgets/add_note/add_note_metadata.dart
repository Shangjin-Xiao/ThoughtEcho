part of '../add_note_dialog.dart';

extension _AddNoteDialogMetadata on _AddNoteDialogState {
  // 优化：数据库变化监听回调 - 自动更新标签列表（带防抖）
  void _onDatabaseChanged() {
    if (!mounted || _databaseService == null) return;

    // 防抖：300ms 内的多次变化只触发一次更新
    _dbChangeDebounceTimer?.cancel();
    _dbChangeDebounceTimer = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted || _databaseService == null) return;

      try {
        // 重新获取最新的标签列表
        final updatedTags = await _databaseService!.getCategories();

        if (!mounted) return;

        // 脏检查：比较完整列表，避免新增标签但首尾不变时漏更新
        bool needsUpdate = _availableTags.length != updatedTags.length;
        if (!needsUpdate) {
          for (int i = 0; i < _availableTags.length; i++) {
            final current = _availableTags[i];
            final updated = updatedTags[i];
            if (current.id != updated.id ||
                current.name != updated.name ||
                current.iconName != updated.iconName ||
                current.isDefault != updated.isDefault) {
              needsUpdate = true;
              break;
            }
          }
        }

        if (needsUpdate) {
          setState(() {
            _availableTags = updatedTags;
            // 重新应用当前的搜索过滤
            _updateFilteredTags(_lastSearchQuery);
          });
          logDebug('标签列表已更新，当前共 ${updatedTags.length} 个标签');
        }
      } catch (e) {
        logDebug('更新标签列表失败: $e');
      }
    });
  }

  /// 显示功能引导序列
  void _showGuides() {
    FeatureGuideHelper.showSequence(
      context: context,
      guides: [
        ('add_note_fullscreen_button', _fullscreenButtonKey),
        ('add_note_tag_hidden', _tagGuideKey),
      ],
    );
  }

  // 搜索变化处理 - 使用防抖优化
  void _onSearchChanged() {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      final query = _tagSearchController.text.toLowerCase();
      if (query != _lastSearchQuery) {
        _lastSearchQuery = query;
        _updateFilteredTags(query);
      }
    });
  }

  // 更新过滤标签 - 使用缓存优化
  void _updateFilteredTags(String query) {
    if (!mounted) return;

    setState(() {
      if (query.isEmpty) {
        _filteredTags = _availableTags;
      } else {
        // 优化：使用缓存避免重复计算
        if (_filterCache.containsKey(query)) {
          _filteredTags = _filterCache[query]!;
        } else {
          _filteredTags = _availableTags.where((tag) {
            return tag.name.toLowerCase().contains(query);
          }).toList();

          // 缓存结果，限制缓存大小防止内存泄漏
          if (_filterCache.length < 50) {
            _filterCache[query] = _filteredTags;
          }
        }
      }
    });
  }

  // 添加默认的一言相关标签（完全异步执行，不阻塞UI）
  Future<void> _addDefaultHitokotoTagsAsync() async {
    if (!mounted) return;

    setState(() {
      _isLoadingHitokotoTags = true;
    });

    try {
      final db =
          _databaseService ?? _readServiceOrNull<DatabaseService>(context);

      if (db == null) {
        logDebug('未找到DatabaseService，跳过默认标签添加');
        return;
      }

      // 批量准备标签信息，减少异步等待次数
      final List<Map<String, String>> tagsToEnsure = [];

      // 添加"每日一言"标签
      tagsToEnsure.add({
        'name': '每日一言',
        'icon': '💭',
        'fixedId': DatabaseService.defaultCategoryIdHitokoto,
      });

      // 添加一言类型对应的标签
      String? hitokotoType;
      if (widget.hitokotoData != null) {
        hitokotoType = _getHitokotoTypeFromApiResponse();
        if (hitokotoType != null && hitokotoType.isNotEmpty) {
          String tagName = _convertHitokotoTypeToTagName(hitokotoType);
          String iconName = _getIconForHitokotoType(hitokotoType);
          String? fixedId;

          if (_hitokotoTypeToCategoryIdMap.containsKey(hitokotoType)) {
            fixedId = _hitokotoTypeToCategoryIdMap[hitokotoType];
          }

          tagsToEnsure.add({
            'name': tagName,
            'icon': iconName,
            if (fixedId != null) 'fixedId': fixedId,
          });
        }
      }

      // 批量确保标签存在
      final List<String> tagIds = [];
      for (final tagInfo in tagsToEnsure) {
        final tagId = await _ensureTagExists(
          db,
          tagInfo['name']!,
          tagInfo['icon']!,
          fixedId: tagInfo['fixedId'],
        );
        if (tagId != null) {
          tagIds.add(tagId);
        }
      }

      if (!mounted) return;

      // 一次性更新所有选中的标签
      setState(() {
        for (final tagId in tagIds) {
          if (!_selectedTagIds.contains(tagId)) {
            _selectedTagIds.add(tagId);
          }
        }
      });

      // 设置分类（如果需要）
      if (hitokotoType != null &&
          _hitokotoTypeToCategoryIdMap.containsKey(hitokotoType)) {
        final categoryId = _hitokotoTypeToCategoryIdMap[hitokotoType];
        final category = await db.getCategoryById(categoryId!);
        if (mounted) {
          setState(() {
            _selectedCategory = category;
          });
        }
      }
    } catch (e) {
      logDebug('添加默认标签失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingHitokotoTags = false;
        });
      }
    }
  }

  // 从hitokotoData中获取一言类型
  String? _getHitokotoTypeFromApiResponse() {
    // 一言API的类型字段是'type'
    if (widget.hitokotoData != null &&
        widget.hitokotoData!.containsKey('type')) {
      return widget.hitokotoData!['type'].toString();
    }
    return null;
  }

  // 将一言API的类型代码转换为可读标签名称
  String _convertHitokotoTypeToTagName(String typeCode) {
    // 一言API的类型映射
    const Map<String, String> typeMap = {
      'a': '动画',
      'b': '漫画',
      'c': '游戏',
      'd': '文学',
      'e': '原创',
      'f': '来自网络',
      'g': '其他',
      'h': '影视',
      'i': '诗词',
      'j': '网易云',
      'k': '哲学',
      'l': '抖机灵',
    };

    return typeMap[typeCode] ?? '其他一言';
  }

  // 为不同类型的一言选择对应的图标
  String _getIconForHitokotoType(String typeCode) {
    const Map<String, String> iconMap = {
      'a': '🎬', // 动画
      'b': '📚', // 漫画
      'c': '🎮', // 游戏
      'd': '📖', // 文学
      'e': '✨', // 原创
      'f': '🌐', // 来自网络
      'g': '📦', // 其他 -> 新 emoji
      'h': '🎞️', // 影视 -> 随机 emoji
      'i': '🪶', // 诗词 -> 随机 emoji
      'j': '🎧', // 网易云 -> 🎧
      'k': '🤔', // 哲学
      'l': '😄', // 抖机灵
    };

    // 默认使用 Material 的 format_quote 图标名
    return iconMap[typeCode] ?? 'format_quote';
  }

  // 确保标签存在，如果不存在则创建（优化版：减少数据库查询）
  Future<String?> _ensureTagExists(
    DatabaseService db,
    String name,
    String iconName, {
    String? fixedId,
  }) async {
    try {
      // 使用传入的 fixedId 或检查是否有固定ID映射
      if (fixedId == null) {
        for (var entry in _hitokotoTypeToCategoryIdMap.entries) {
          if (_convertHitokotoTypeToTagName(entry.key) == name) {
            fixedId = entry.value;
            break;
          }
        }

        // 如果是"每日一言"标签的特殊情况
        if (name == '每日一言') {
          fixedId = DatabaseService.defaultCategoryIdHitokoto;
        }
      }

      // 无论标签是否被重命名，优先通过固定ID查找
      if (fixedId != null) {
        final category = await db.getCategoryById(fixedId);
        if (category != null) {
          logDebug('通过固定ID找到标签: ${category.name}(ID=${category.id})');
          return category.id;
        }
      }

      // 优化：使用缓存的标签列表，避免每次都查询数据库
      _allCategoriesCache ??= await db.getCategories();
      final categories = _allCategoriesCache!;

      final existingTag = categories.firstWhere(
        (tag) => tag.name.toLowerCase() == name.toLowerCase(),
        orElse: () => NoteCategory(id: '', name: ''),
      );

      // 如果标签已存在，返回其ID
      if (existingTag.id.isNotEmpty) {
        return existingTag.id;
      }

      // 创建新标签
      if (fixedId != null) {
        try {
          await db.addCategoryWithId(fixedId, name, iconName: iconName);
          // 清除缓存，下次会重新加载
          _allCategoriesCache = null;
          return fixedId;
        } catch (e) {
          logDebug('使用固定ID创建标签失败: $e');
          await db.addCategory(name, iconName: iconName);
        }
      } else {
        await db.addCategory(name, iconName: iconName);
      }

      // 清除缓存并重新获取
      _allCategoriesCache = null;
      final updatedCategories = await db.getCategories();
      final newTag = updatedCategories.firstWhere(
        (tag) => tag.name.toLowerCase() == name.toLowerCase(),
        orElse: () => NoteCategory(id: '', name: ''),
      );

      return newTag.id.isNotEmpty ? newTag.id : null;
    } catch (e) {
      logDebug('确保标签"$name"存在时出错: $e');
      return null;
    }
  }
}
