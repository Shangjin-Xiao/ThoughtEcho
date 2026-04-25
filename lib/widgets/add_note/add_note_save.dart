part of '../add_note_dialog.dart';

extension _AddNoteDialogSave on _AddNoteDialogState {
  String _updateFailureMessage(
    AppLocalizations l10n,
    QuoteUpdateResult result,
  ) {
    switch (result) {
      case QuoteUpdateResult.notFound:
        return l10n.noteNotFound;
      case QuoteUpdateResult.skippedDeleted:
        return l10n.noteUpdateSkippedDeleted;
      case QuoteUpdateResult.updated:
        return l10n.noteUpdated;
    }
  }

  // 解析格式如"——作者《作品》"的字符串
  void _parseSource(
    String source,
    TextEditingController authorController,
    TextEditingController workController,
  ) {
    String author = '';
    String work = '';

    // 提取作者（在"——"之后，"《"之前）
    final authorMatch = RegExp(r'——([^《]+)').firstMatch(source);
    if (authorMatch != null && authorMatch.groupCount >= 1) {
      author = authorMatch.group(1)?.trim() ?? '';
    }

    // 提取作品（在《》之间）
    final workMatch = RegExp(r'《(.+?)》').firstMatch(source);
    if (workMatch != null && workMatch.groupCount >= 1) {
      work = workMatch.group(1) ?? '';
    }

    authorController.text = author;
    workController.text = work;
  }

  // 格式化来源
  String _formatSource(String author, String work) {
    if (author.isEmpty && work.isEmpty) {
      return '';
    }

    String result = '';
    if (author.isNotEmpty) {
      result += '——$author';
    }

    if (work.isNotEmpty) {
      if (result.isNotEmpty) {
        result += ' ';
      } else {
        result += '——';
      }
      result += '《$work》';
    }

    return result;
  }

  /// 检查是否有未保存的用户输入内容
  bool _hasUnsavedChanges() {
    // 检查正文内容是否有变化
    if (_contentController.text.trim() != _initialContent.trim()) {
      return true;
    }

    // 检查作者是否有变化
    if (_authorController.text.trim() != _initialAuthor.trim()) {
      return true;
    }

    // 检查作品是否有变化
    if (_workController.text.trim() != _initialWork.trim()) {
      return true;
    }

    // 检查标签是否有变化
    final currentTagSet = Set.from(_selectedTagIds);
    final initialTagSet = Set.from(_initialTagIds);
    if (!currentTagSet.containsAll(initialTagSet) ||
        !initialTagSet.containsAll(currentTagSet)) {
      return true;
    }

    // 检查颜色是否有变化
    if (_selectedColorHex != _initialColorHex) {
      return true;
    }

    return false;
  }

  /// 保存笔记并退出
  Future<void> _saveAndExit() async {
    // 如果内容为空，直接返回
    if (_contentController.text.isEmpty) {
      if (context.mounted) {
        Navigator.pop(context);
      }
      return;
    }

    // 获取当前时间段
    final String currentDayPeriodKey = TimeUtils.getCurrentDayPeriodKey();

    // 创建或更新笔记
    final isEditing = widget.initialQuote != null;
    final baseQuote = _fullInitialQuote ?? widget.initialQuote;

    final Quote quote = Quote(
      id: widget.initialQuote?.id ?? const Uuid().v4(),
      content: _contentController.text,
      date: widget.initialQuote?.date ?? DateTime.now().toIso8601String(),
      aiAnalysis: _aiSummary,
      source: _formatSource(
        _authorController.text,
        _workController.text,
      ),
      sourceAuthor: _authorController.text,
      sourceWork: _workController.text,
      tagIds: _selectedTagIds,
      sentiment: baseQuote?.sentiment,
      keywords: baseQuote?.keywords,
      summary: baseQuote?.summary,
      categoryId: _selectedCategory?.id ?? widget.initialQuote?.categoryId,
      colorHex: _selectedColorHex,
      location: _includeLocation
          ? (isEditing
              ? _originalLocation
              : () {
                  final loc = _newLocation ??
                      _cachedLocationService?.getFormattedLocation();
                  if ((loc == null || loc.isEmpty) && _newLatitude != null) {
                    return LocationService.kAddressPending;
                  }
                  return loc;
                }())
          : null,
      latitude: (_includeLocation || _includeWeather)
          ? (isEditing ? _originalLatitude : _newLatitude)
          : null,
      longitude: (_includeLocation || _includeWeather)
          ? (isEditing ? _originalLongitude : _newLongitude)
          : null,
      weather: _includeWeather
          ? (isEditing
              ? _originalWeather
              : _cachedWeatherService?.currentWeather)
          : null,
      temperature: _includeWeather
          ? (isEditing
              ? _originalTemperature
              : _cachedWeatherService?.temperature)
          : null,
      dayPeriod: widget.initialQuote?.dayPeriod ?? currentDayPeriodKey,
      editSource: widget.initialQuote?.editSource,
      deltaContent: widget.initialQuote?.deltaContent,
    );

    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final db = Provider.of<DatabaseService>(context, listen: false);

      if (widget.initialQuote != null) {
        final updateResult = await db.updateQuote(quote);
        if (updateResult != QuoteUpdateResult.updated) {
          if (!mounted) return;
          messenger.showSnackBar(
            SnackBar(
              content: Text(_updateFailureMessage(l10n, updateResult)),
              duration: AppConstants.snackBarDurationError,
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.noteUpdated),
            duration: AppConstants.snackBarDurationImportant,
          ),
        );
      } else {
        await db.addQuote(quote);
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.noteSaved),
            duration: AppConstants.snackBarDurationImportant,
          ),
        );
      }

      // 调用保存回调
      if (widget.onSave != null) {
        widget.onSave!(quote);
      }

      // 关闭对话框
      if (!mounted) return;
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.saveFailedWithError(e.toString())),
          duration: AppConstants.snackBarDurationError,
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// 显示未保存内容的确认对话框
  /// 返回值: null=继续编辑, true=放弃更改, 'save'=保存并退出
  Future<dynamic> _showUnsavedChangesDialog() async {
    final l10n = AppLocalizations.of(context);
    final result = await showDialog<dynamic>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.unsavedChangesTitle),
        content: Text(l10n.unsavedChangesDesc),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text(l10n.continueEditing),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.discardChanges,
              style: TextStyle(color: Colors.red.shade400),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: Text(l10n.saveAndExit),
          ),
        ],
      ),
    );
    return result;
  }
}
