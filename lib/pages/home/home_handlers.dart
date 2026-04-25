part of '../home_page.dart';

/// Extension for event handlers
extension _HomeHandlers on _HomePageState {
  /// 检查剪贴板内容并处理
  Future<void> _checkClipboard() async {
    if (!mounted) return;

    final clipboardService = Provider.of<ClipboardService>(
      context,
      listen: false,
    );

    // 如果剪贴板监控功能未启用，则不进行检查
    if (!clipboardService.enableClipboardMonitoring) {
      logDebug('剪贴板监控已禁用，跳过检查');
      return;
    }

    logDebug('执行剪贴板检查');
    // 检查剪贴板内容
    final clipboardData = await clipboardService.checkClipboard();
    if (clipboardData != null && mounted) {
      // 显示确认对话框
      clipboardService.showClipboardConfirmationDialog(context, clipboardData);
    }
  }

  /// 消费待处理的摘录意图
  Future<void> _consumePendingExcerptIntent() async {
    if (!mounted || _isHandlingExcerptIntent) {
      return;
    }

    final settingsService = context.read<SettingsService>();
    if (!settingsService.excerptIntentEnabled) {
      return;
    }

    _isHandlingExcerptIntent = true;
    try {
      const excerptIntentService = ExcerptIntentService();
      final excerptText =
          await excerptIntentService.consumePendingExcerptText();
      if (!mounted || excerptText == null) {
        return;
      }

      if (_lastConsumedExcerptText == excerptText) {
        return;
      }

      _lastConsumedExcerptText = excerptText;
      _showAddQuoteDialog(prefilledContent: excerptText);
    } catch (e) {
      logError('消费外部摘录失败', error: e, source: 'HomePage');
    } finally {
      _isHandlingExcerptIntent = false;
    }
  }

  /// 检查是否有未保存的草稿
  Future<bool> _checkDraftRecovery() async {
    if (!mounted) return false;

    try {
      final draftData = await DraftService().getLatestDraft();
      if (draftData == null) return false;

      if (!mounted) return false;

      final l10n = AppLocalizations.of(context);
      final shouldRestore = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.draftRecoverTitle),
          content: Text(l10n.draftRecoverMessage),
          actions: [
            TextButton(
              onPressed: () {
                // 用户选择丢弃，删除所有草稿，避免重复提示
                DraftService().deleteAllDrafts();
                Navigator.pop(ctx, false);
              },
              child: Text(
                l10n.discard,
                style: TextStyle(color: Colors.red.shade400),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.restore),
            ),
          ],
        ),
      );

      if (shouldRestore == true && mounted) {
        final draftId = draftData['id'] as String;
        final isNew = draftId.startsWith('new_');

        Quote? initialQuote;
        Quote? original;

        if (!isNew) {
          // 如果是现有笔记，尝试从数据库获取原始信息
          try {
            final db = context.read<DatabaseService>();
            original = await db.getQuoteById(draftId);
            if (original != null) {
              initialQuote = buildRestoredDraftQuote(
                draftData: draftData,
                original: original,
              );
            } else {
              logDebug('恢复草稿时发现原始笔记已删除，将作为新笔记处理');
            }
          } catch (e) {
            logDebug('恢复草稿时获取原始笔记失败: $e');
          }
        }

        initialQuote ??= buildRestoredDraftQuote(
          draftData: draftData,
          original: original,
        );

        // 导航到全屏编辑器
        if (mounted) {
          final saved = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (context) => NoteFullEditorPage(
                initialContent: initialQuote!.content,
                initialQuote: initialQuote,
                isRestoredDraft: true, // 标记为恢复的草稿
                restoredDraftId: draftId, // 传递恢复草稿的原始ID，确保 key 稳定
                // 如果有标签信息，也可以传递 allTags，但这通常由编辑器自己加载
              ),
            ),
          );

          // 如果保存成功返回，强制刷新列表
          if (saved == true && mounted) {
            logDebug('编辑器保存成功返回，触发列表刷新');
            context.read<DatabaseService>().refreshQuotes();
          }
          return true; // 已处理恢复
        }
      }
    } catch (e) {
      logError('检查草稿恢复失败', error: e, source: 'HomePage');
    }
    return false;
  }

  /// 处理心形按钮点击
  void _handleFavoriteClick(Quote quote) async {
    try {
      final db = Provider.of<DatabaseService>(context, listen: false);
      await db.incrementFavoriteCount(quote.id!);

      // 检查mounted以确保widget还在树中
      if (!mounted) return;

      final l10n = AppLocalizations.of(context);
      // 显示简洁的反馈
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.favorite, color: Colors.red, size: 16),
              const SizedBox(width: 8),
              Text(l10n.favoriteCountWithNum(quote.favoriteCount + 1)),
            ],
          ),
          duration: const Duration(milliseconds: 1500),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade400,
        ),
      );
    } catch (e) {
      // 检查mounted以确保widget还在树中
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).favoriteFailed),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// 处理心形按钮长按（清除收藏）
  void _handleLongPressFavorite(Quote quote) async {
    if (quote.favoriteCount <= 0) return;

    final l10n = AppLocalizations.of(context);

    // 显示确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.clearFavoriteTitle),
        content: Text(l10n.clearFavoriteMessage(quote.favoriteCount)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    try {
      final db = Provider.of<DatabaseService>(context, listen: false);
      await db.resetFavoriteCount(quote.id!);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.favorite_border, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text(l10n.clearFavoriteSuccess),
            ],
          ),
          duration: const Duration(milliseconds: 1500),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.clearFavoriteFailed),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// 显示AI问答聊天界面
  void _showAIQuestionDialog(Quote quote) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => NoteQAChatPage(quote: quote)),
    );
  }

  /// 处理排序变更
  void _handleSortChanged(String sortType, bool sortAscending) {
    setState(() {
      _sortType = sortType;
      _sortAscending = sortAscending;
    });
  }

  /// FAB 短按处理
  void _onFABTap() {
    _showAddQuoteDialog();
  }

  /// FAB 长按处理 - 显示语音录制浮层
  void _onFABLongPress() {
    final settingsService = Provider.of<SettingsService>(
      context,
      listen: false,
    );
    final localAISettings = settingsService.localAISettings;

    // 检查是否启用了本地AI和语音转文字功能，未启用则直接返回无反应
    if (!localAISettings.enabled || !localAISettings.speechToTextEnabled) {
      return;
    }

    _showVoiceInputOverlay();
  }

  /// 显示语音输入浮层
  Future<void> _showVoiceInputOverlay() async {
    if (!mounted) return;

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'voice_input_overlay',
      barrierColor: Colors.transparent,
      pageBuilder: (context, animation, secondaryAnimation) {
        return VoiceInputOverlay(
          transcribedText: null,
          onSwipeUpForOCR: () async {
            Navigator.of(context).pop();
            await _openOCRFlow();
          },
          onRecordComplete: () {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(this.context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLocalizations.of(this.context).featureComingSoon,
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        );
        return FadeTransition(opacity: curved, child: child);
      },
      transitionDuration: const Duration(milliseconds: 180),
    );
  }

  /// 打开OCR流程
  Future<void> _openOCRFlow() async {
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const OCRCapturePage()),
    );

    if (!mounted) return;

    final l10n = AppLocalizations.of(context);
    String resultText = l10n.featureComingSoon;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        return OCRResultSheet(
          recognizedText: resultText,
          onTextChanged: (text) {
            resultText = text;
          },
          onInsertToEditor: () {
            Navigator.of(context).pop();
            _showAddQuoteDialog(prefilledContent: resultText);
          },
          onRecognizeSource: () {},
        );
      },
    );
  }
}
