part of '../home_page.dart';

extension _HomePageDialogsExtension on _HomePageState {
  // 显示添加笔记对话框（优化性能）
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

  // FAB 短按处理
  void _onFABTap() {
    _showAddQuoteDialog();
  }

  // FAB 长按处理 - 显示语音录制浮层
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

  // 显示编辑笔记对话框
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

  // 显示删除确认对话框
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

  // 处理心形按钮点击
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

  // 处理心形按钮长按（清除收藏）
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

  // 显示AI问答聊天界面
  void _showAIQuestionDialog(Quote quote) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => NoteQAChatPage(quote: quote)),
    );
  }

  // 生成AI卡片
  void _generateAICard(Quote quote) async {
    if (_aiCardService == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).aiCardServiceNotInitialized,
          ),
          duration: AppConstants.snackBarDurationError,
        ),
      );
      return;
    }

    // 显示加载对话框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const CardGenerationLoadingDialog(),
    );

    try {
      // 生成卡片
      final card = await _aiCardService!.generateCard(
        note: quote,
        brandName: AppLocalizations.of(context).appTitle,
      );

      // 关闭加载对话框
      if (mounted) Navigator.of(context).pop();

      // 显示卡片预览对话框
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => CardPreviewDialog(
            card: card,
            onShare: (selected) => _shareCard(selected),
            onSave: (selected) => _saveCard(selected),
            onRegenerate: () => _aiCardService!.generateCard(
              note: quote,
              isRegeneration: true,
              brandName: AppLocalizations.of(context).appTitle,
            ),
          ),
        );
      }
    } catch (e) {
      // 关闭加载对话框
      if (mounted) Navigator.of(context).pop();

      // 显示错误信息
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).generateCardFailed(e.toString()),
            ),
            backgroundColor: Colors.red,
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    }
  }

  // 分享卡片
  Future<void> _shareCard(GeneratedCard card) async {
    try {
      // 显示加载指示器
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Text(AppLocalizations.of(context).generatingShareImage),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }

      // 生成高质量图片
      final imageBytes = await card.toImageBytes(
        width: 800,
        height: 1200,
        context: context,
        scaleFactor: 2.0,
        renderMode: ExportRenderMode.contain,
      );

      final tempDir = await getTemporaryDirectory();
      final fileName = '心迹_Card_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(imageBytes);

      // 分享文件
      await SharePlus.instance.share(
        ShareParams(
          text:
              '来自心迹的精美卡片\n\n"${card.originalContent.length > 50 ? '${card.originalContent.substring(0, 50)}...' : card.originalContent}"',
          files: [XFile(file.path)],
        ),
      );

      // 显示成功提示
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text(AppLocalizations.of(context).cardSharedSuccessfully),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context).shareFailed(e.toString()),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // 保存卡片
  Future<void> _saveCard(GeneratedCard card) async {
    try {
      // 显示加载指示器
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Text(AppLocalizations.of(context).savingCardToGallery),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }

      // 保存高质量图片
      final filePath = await _aiCardService!.saveCardAsImage(
        card,
        width: 800,
        height: 1200,
        scaleFactor: 2.0,
        renderMode: ExportRenderMode.contain,
        context: context,
        fileNamePrefix: AppLocalizations.of(context).cardFileNamePrefix,
      );

      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(l10n.cardSavedToGallery(filePath))),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: l10n.view,
              textColor: Colors.white,
              onPressed: () {
                // 这里可以添加打开相册的逻辑
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context).saveFailed(e.toString()),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}
