part of '../home_page.dart';

/// Extension for dialog-related methods
extension _HomeDialogs on _HomePageState {
  /// 显示添加笔记对话框（优化性能）
  void _showAddQuoteDialog({
    String? prefilledContent,
    String? prefilledAuthor,
    String? prefilledWork,
    dynamic hitokotoData,
  }) async {
    await _loadTags();
    if (!mounted) return;

    // 确保标签数据已经加载
    if (_isLoadingTags || _tags.isEmpty) {
      logDebug('标签数据未准备好，重新加载标签数据...');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).loadingDataPleaseWait),
          duration: const Duration(seconds: 1),
        ),
      );

      // 强制重新加载标签数据
      await _loadTags();

      // 如果仍然没有标签数据，提示用户
      if (_tags.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).noTagsAvailable),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return;
      }
    }

    if (!mounted) return;

    // 检查是否启用跳过非全屏编辑器
    final settingsService = context.read<SettingsService>();
    if (settingsService.skipNonFullscreenEditor) {
      logDebug('跳过非全屏编辑器，直接打开全屏编辑器');
      await _openFullscreenEditorDirectly(
        prefilledContent: prefilledContent,
        prefilledAuthor: prefilledAuthor,
        prefilledWork: prefilledWork,
        hitokotoData: hitokotoData,
      );
      return;
    }

    logDebug('显示添加笔记对话框，可用标签数: ${_tags.length}');

    // 使用延迟显示，确保动画流畅
    Future.microtask(() {
      if (mounted) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
          builder: (context) => AddNoteDialog(
            prefilledContent: prefilledContent,
            prefilledAuthor: prefilledAuthor,
            prefilledWork: prefilledWork,
            hitokotoData: hitokotoData,
            tags: _tags, // 使用预加载的标签数据
            onSave: (_) {
              // 笔记保存后刷新标签列表
              _loadTags();
              // 新增：强制刷新NoteListView
              if (_noteListViewKey.currentState != null) {
                _noteListViewKey.currentState!.resetAndLoad();
              }
            },
          ),
        );
      }
    });
  }

  /// 直接打开全屏编辑器（跳过非全屏编辑器）
  Future<void> _openFullscreenEditorDirectly({
    String? prefilledContent,
    String? prefilledAuthor,
    String? prefilledWork,
    dynamic hitokotoData,
  }) async {
    try {
      final settingsService = context.read<SettingsService>();
      String content = prefilledContent ?? '';
      String? author = prefilledAuthor;
      String? work = prefilledWork;

      // 处理一言数据
      final isHitokotoQuickAdd = hitokotoData is Map<String, dynamic>;
      if (isHitokotoQuickAdd) {
        content = hitokotoData['hitokoto'] ?? content;
        author = hitokotoData['from_who'] ?? author;
        work = hitokotoData['from'] ?? work;
      }

      final hasExplicitAuthorOrWork = author != null || work != null;

      // 如果没有指定作者/出处，使用默认值
      if (author == null &&
          settingsService.defaultAuthor != null &&
          settingsService.defaultAuthor!.isNotEmpty) {
        author = settingsService.defaultAuthor;
      }
      if (work == null &&
          settingsService.defaultSource != null &&
          settingsService.defaultSource!.isNotEmpty) {
        work = settingsService.defaultSource;
      }

      if (!mounted) return;

      // 导航到全屏编辑器
      // 全屏编辑器会处理自动位置/天气
      // 如果我们传递了作者/出处，跳过编辑器内的默认元数据自动填充
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => NoteFullEditorPage(
            initialContent: content,
            initialQuote: null, // 新建笔记
            allTags: _tags,
            initialAuthor: author,
            initialWork: work,
            skipDefaultMetadataAutofill: hasExplicitAuthorOrWork,
          ),
        ),
      );

      // 如果保存成功，刷新列表
      if (saved == true && mounted) {
        logDebug('全屏编辑器保存成功返回，触发列表刷新');
        _loadTags();
        if (_noteListViewKey.currentState != null) {
          _noteListViewKey.currentState!.resetAndLoad();
        }
      }
    } catch (e) {
      logError('打开全屏编辑器失败', error: e, source: 'HomePage');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(AppLocalizations.of(context).openFullEditorFailedSimple),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// 显示编辑笔记对话框
  void _showEditQuoteDialog(Quote quote) {
    // 检查笔记是否来自全屏编辑器
    if (quote.editSource == 'fullscreen') {
      // 如果是来自全屏编辑器的笔记，则直接打开全屏编辑页面
      try {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => NoteFullEditorPage(
              initialContent: quote.content,
              initialQuote: quote,
              allTags: _tags,
            ),
          ),
        );
      } catch (e) {
        // 显示错误信息
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).cannotOpenFullEditor(e.toString()),
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: AppLocalizations.of(context).retry,
                onPressed: () => _showEditQuoteDialog(quote),
                textColor: Colors.white,
              ),
            ),
          );
        }
      }
    } else {
      // 否则，打开常规编辑对话框
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).brightness == Brightness.light
            ? Colors.white
            : Theme.of(context).colorScheme.surface,
        builder: (context) => AddNoteDialog(
          initialQuote: quote,
          tags: _tags,
          onSave: (_) {
            // 笔记更新后刷新标签列表
            _loadTags();
          },
        ),
      );
    }
  }

  /// 显示删除确认对话框
  void _showDeleteConfirmDialog(Quote quote) {
    final pageContext = context;
    final l10n = AppLocalizations.of(context);
    final retentionDays = context.read<SettingsService>().trashRetentionDays;
    final messenger = ScaffoldMessenger.of(pageContext);

    showDialog(
      context: pageContext,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.moveNoteToTrashTitle),
        content: Text(l10n.moveNoteToTrashConfirmation(retentionDays)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              final db =
                  Provider.of<DatabaseService>(pageContext, listen: false);
              try {
                await db.deleteQuote(quote.id!);
                if (!dialogContext.mounted || !pageContext.mounted) {
                  return;
                }
                Navigator.pop(dialogContext);
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(l10n.noteMovedToTrash),
                    duration: const Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                // 显示回收站位置引导（仅第一次删除笔记时）
                _scheduleTrashLocationGuide();
              } catch (e, stackTrace) {
                logError(
                  '移动笔记到回收站失败: $e',
                  error: e,
                  stackTrace: stackTrace,
                  source: 'HomePage',
                );
                if (!dialogContext.mounted || !pageContext.mounted) {
                  return;
                }
                Navigator.pop(dialogContext);
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(l10n.deleteFailed(e.toString())),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }
}
