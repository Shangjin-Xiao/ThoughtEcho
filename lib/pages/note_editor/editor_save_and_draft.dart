part of '../note_full_editor_page.dart';

/// Draft management, save logic, and state helper methods.
extension _NoteEditorSaveAndDraft on _NoteFullEditorPageState {
  void _initializeAsPlainText() {
    try {
      if (mounted) {
        _updateState(() {
          _controller.dispose(); // 释放旧控制器
          _controller = quill.QuillController(
            document: quill.Document()..insert(0, widget.initialContent),
            selection: const TextSelection.collapsed(offset: 0),
          );
          _attachDraftListener();
        });
      }
    } catch (e) {
      // 如果即使初始化纯文本也失败，使用空文档
      logDebug('初始化编辑器为纯文本失败: $e');
      _initializeEmptyDocument();
    }
  }

  void _initializeEmptyDocument() {
    try {
      if (mounted) {
        _updateState(() {
          _controller.dispose(); // 释放旧控制器
          _controller = quill.QuillController.basic();
          _attachDraftListener();

          // 尝试安全地添加内容
          try {
            if (widget.initialContent.isNotEmpty) {
              // 修复：分批添加内容，避免一次性插入大量文本，并正确跟踪插入位置
              final content = widget.initialContent;
              const chunkSize = 1000; // 每次插入1000字符
              int currentInsertPosition = 0; // 跟踪当前插入位置

              for (int i = 0; i < content.length; i += chunkSize) {
                final end = (i + chunkSize < content.length)
                    ? i + chunkSize
                    : content.length;
                final chunk = content.substring(i, end);

                // 确保插入位置在有效范围内
                final docLength = _controller.document.length;
                final safeInsertPosition = currentInsertPosition.clamp(
                  0,
                  docLength - 1,
                );

                _controller.document.insert(safeInsertPosition, chunk);

                // 更新插入位置：当前位置 + 插入的文本长度
                currentInsertPosition = safeInsertPosition + chunk.length;
              }
            }
          } catch (insertError) {
            logDebug('插入内容失败: $insertError');
            // 最后的兜底：创建一个包含错误信息的文档
            try {
              final errorMessage = AppLocalizations.of(
                context,
              ).documentLoadFailed;
              _controller.document.insert(0, errorMessage);
            } catch (_) {
              // 完全失败，保持空文档
            }
          }
        });
      }
    } catch (e) {
      logDebug('初始化空文档也失败: $e');
      // 这种情况下，保持现有控制器状态
    }
  }

  String _buildDraftStorageKey() {
    // 1. 如果明确指定了恢复草稿的ID，优先使用它
    if (widget.restoredDraftId != null && widget.restoredDraftId!.isNotEmpty) {
      return widget.restoredDraftId!;
    }
    // 2. 如果是编辑现有笔记，使用笔记ID
    if (widget.initialQuote?.id != null &&
        widget.initialQuote!.id!.isNotEmpty) {
      return widget.initialQuote!.id!;
    }
    // 3. 新建笔记，使用初始内容的哈希值作为临时ID
    // 注意：如果是恢复的草稿，应优先使用 restoredDraftId
    return 'new_note_${widget.initialContent.hashCode}';
  }

  void _attachDraftListener() {
    _controller.removeListener(_onDraftChanged);
    _controller.addListener(_onDraftChanged);
  }

  void _onDraftChanged() {
    if (_draftLoaded) {
      _draftSaveTimer?.cancel();
      _draftSaveTimer = Timer(const Duration(seconds: 2), () {
        _saveDraft();
      });
    }
  }

  Future<void> _saveDraft() async {
    try {
      final key = _draftStorageKey;
      if (key == null || key.isEmpty) return;
      final plainText = _controller.document.toPlainText().trim();

      // 只有用户实际编写了正文内容才保存草稿
      // 自动添加的天气、位置、标签等不应该触发草稿保存
      if (plainText.isEmpty) {
        // 如果正文为空，删除已存在的草稿
        await _clearDraft();
        return;
      }

      // 检查是否有用户实际输入的内容（非自动填充）
      final hasUserContent = _hasActualUserContent();

      final deltaJson = await _getDocumentContentSafely();
      final payload = {
        'deltaContent': deltaJson,
        'plainText': plainText,
        'author': _authorController.text,
        'work': _workController.text,
        'tagIds': _selectedTagIds,
        'colorHex': _selectedColorHex,
        'location': _showLocation ? _location : null,
        'latitude': (_showLocation || _showWeather) ? _latitude : null,
        'longitude': (_showLocation || _showWeather) ? _longitude : null,
        'weather': _showWeather ? _weather : null,
        'temperature': _showWeather ? _temperature : null,
        'aiAnalysis': _currentAiAnalysis,
        'timestamp': DateTime.now().toIso8601String(),
        'hasUserContent': hasUserContent,
      };
      // 使用 DraftService 保存草稿
      await DraftService().saveDraft(key, payload);
    } catch (e) {
      logDebug('保存草稿失败: $e');
    }
  }

  /// 检查是否有用户实际输入的内容（非自动填充的内容）
  bool _hasActualUserContent() {
    // 检查正文内容是否有变化
    final currentPlainText = _controller.document.toPlainText().trim();
    if (currentPlainText != _initialPlainText.trim() &&
        currentPlainText.isNotEmpty) {
      return true;
    }

    // 如果是恢复的草稿，视为有用户内容
    if (_isRestoredFromDraft) {
      return true;
    }

    return false;
  }

  Future<void> _clearDraft() async {
    try {
      final key = _draftStorageKey;
      if (key == null || key.isEmpty) return;
      // 使用 DraftService 删除草稿
      await DraftService().deleteDraft(key);
    } catch (e) {
      logDebug('清理草稿失败: $e');
    }
  }

  IconData _getWeatherIcon(String weatherKey) {
    return WeatherService.getWeatherIconDataByKey(weatherKey);
  }

  bool _hasUnsavedChanges() {
    // 如果是从草稿恢复的且尚未保存，则视为有未保存更改
    if (_isRestoredFromDraft) {
      return true;
    }

    // 如果是来自每日一言且内容未修改，不提示未保存（双击每日一言快速进入，不需要提示）
    final currentPlainText = _controller.document.toPlainText().trim();
    if (widget.isFromDailyQuote &&
        currentPlainText == _initialPlainText.trim()) {
      return false;
    }

    // 检查主要内容
    if (currentPlainText != _initialPlainText.trim()) {
      return true;
    }

    // 检查元数据
    if (_authorController.text != _initialAuthor) {
      return true;
    }
    if (_workController.text != _initialWork) {
      return true;
    }

    // 检查标签
    final selectedTagSet = Set.from(_selectedTagIds);
    final initialTagSet = Set.from(_initialTagIds);
    if (!selectedTagSet.containsAll(initialTagSet) ||
        !initialTagSet.containsAll(selectedTagSet)) {
      return true;
    }

    // 检查颜色
    if (_selectedColorHex != _initialColorHex) {
      return true;
    }

    // 对于编辑已有笔记的情况，检查位置和天气变化
    // 对于新建笔记，位置和天气是自动获取的，不视为用户修改
    if (widget.initialQuote != null) {
      // 检查位置
      if (_location != _initialLocation) {
        return true;
      }
      if (_latitude != _initialLatitude) {
        return true;
      }
      if (_longitude != _initialLongitude) {
        return true;
      }

      // 检查天气
      if (_weather != _initialWeather) {
        return true;
      }
      if (_temperature != _initialTemperature) {
        return true;
      }
    }

    // 检查 AI 分析
    if (_currentAiAnalysis != _initialAiAnalysis) {
      return true;
    }

    // 使用 _initialDeltaContent 避免编译器警告
    // 富文本内容如果被修改，纯文本内容通常也会反映这个变化
    // 所以这里仅用于记录初始状态，实际比对通过纯文本进行
    // ignore: unused_local_variable
    final _ = _initialDeltaContent;

    return false;
  }

  Future<void> _saveContent() async {
    // 立即取消草稿保存定时器，防止在保存过程中再次触发草稿保存
    _draftSaveTimer?.cancel();
    _draftLoaded = false; // 标记草稿已处理，防止后续监听再次开启定时器

    final db = Provider.of<DatabaseService>(context, listen: false);

    final l10n = AppLocalizations.of(context);
    logDebug('开始保存笔记内容...');
    if (mounted) {
      _updateState(() {
        _isSaving = true;
        _saveProgress = 0.0;
        _saveStatus = l10n.preparingProcess;
      });
    }

    // 处理临时媒体文件，带进度
    // 为了在保存失败时回滚，记录本次从临时目录移动到永久目录的文件
    final List<String> movedToPermanentForThisSave = [];
    try {
      await _processTemporaryMediaFiles(
        onProgress: (p, status) {
          if (mounted) {
            _updateState(() {
              _saveProgress = p.clamp(0.0, 1.0);
              if (status != null) _saveStatus = status;
            });
          }
        },
        onFileMoved: (permanentPath) {
          // 仅记录位于应用永久媒体目录下的路径
          if (permanentPath.isNotEmpty) {
            movedToPermanentForThisSave.add(permanentPath);
          }
        },
      );
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.mediaProcessFailed(e.toString())),
            backgroundColor: Colors.orange,
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    }

    // 获取纯文本内容
    String plainTextContent = '';
    String deltaJson = '';

    try {
      plainTextContent = _controller.document.toPlainText().trim();
      logDebug('获取到纯文本内容: ${plainTextContent.length} 字符');

      // 使用内存安全的方法获取富文本内容
      deltaJson = await _getDocumentContentSafely();

      logDebug('富文本JSON长度: ${deltaJson.length}');
      logDebug(
        '富文本JSON内容示例: ${deltaJson.substring(0, min(100, deltaJson.length))}...',
      );
    } catch (e) {
      logDebug('获取文档内容失败: $e');
      // 显示错误但继续尝试保存
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.documentLoadFailed),
            backgroundColor: Colors.orange,
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }

      // 尝试获取内容
      try {
        plainTextContent = _controller.document.toPlainText().trim();
        if (plainTextContent.isEmpty) {
          plainTextContent = widget.initialContent; // 回退到初始内容
        }
        // 不设置deltaJson，这样将不会保存富文本格式
      } catch (_) {
        plainTextContent = widget.initialContent; // 回退到初始内容
      }
    }

    final now = DateTime.now().toIso8601String();

    // 获取当前时间段
    final String currentDayPeriodKey =
        TimeUtils.getCurrentDayPeriodKey(); // 使用 Key

    // 构建笔记对象
    // 优先使用 _fullInitialQuote 中的数据，以保留未加载的字段（如aiAnalysis等）
    final baseQuote = _fullInitialQuote ?? widget.initialQuote;

    final quote = Quote(
      id: baseQuote?.id ?? const Uuid().v4(),
      content: plainTextContent,
      date: baseQuote?.date ?? now,
      aiAnalysis: _currentAiAnalysis ?? baseQuote?.aiAnalysis,
      source: _formatSource(_authorController.text, _workController.text),
      sourceAuthor: _authorController.text,
      sourceWork: _workController.text,
      tagIds: _selectedTagIds,
      sentiment: baseQuote?.sentiment,
      keywords: baseQuote?.keywords,
      summary: baseQuote?.summary,
      categoryId: baseQuote?.categoryId,
      colorHex: _selectedColorHex,
      location: _showLocation
          ? (_location ??
              (_latitude != null ? LocationService.kAddressPending : null))
          : null,
      latitude: _showLocation ? _latitude : null,
      longitude: _showLocation ? _longitude : null,
      weather: _showWeather ? _weather : null,
      temperature: _showWeather ? _temperature : null,
      deltaContent: deltaJson,
      editSource: 'fullscreen',
      dayPeriod: baseQuote?.dayPeriod ?? currentDayPeriodKey, // 保存 Key
      lastModified: now, // 更新最后修改时间
      favoriteCount: baseQuote?.favoriteCount ?? 0, // 保留喜爱计数
    );

    try {
      logDebug('保存笔记: ID=${quote.id}, 是否为更新模式=${widget.initialQuote != null}');
      logDebug(
        '笔记内容长度: ${quote.content.length}, 富文本长度: ${quote.deltaContent?.length ?? 0}',
      );

      if (mounted) {
        _updateState(() {
          _saveStatus = l10n.writingDatabase;
          _saveProgress = _saveProgress < 0.9 ? 0.9 : _saveProgress;
        });
      }

      if (widget.initialQuote != null && widget.initialQuote?.id != null) {
        // 只有当initialQuote存在且有ID时，才更新现有笔记
        logDebug('更新现有笔记，ID: ${quote.id}');
        final updateResult = await db.updateQuote(quote);
        if (updateResult != QuoteUpdateResult.updated) {
          await _rollbackMovedPermanentMediaFiles(movedToPermanentForThisSave);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_updateFailureMessage(l10n, updateResult)),
                backgroundColor: Colors.orange,
                duration: AppConstants.snackBarDurationError,
              ),
            );
          }
          return;
        }
        _draftSaveTimer?.cancel();
        await _clearDraft();
        _didSaveSuccessfully = true; // 标记保存成功，避免会话级清理
        _isRestoredFromDraft = false; // 保存成功后，不再视为恢复的草稿
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).noteSaved),
              duration: AppConstants.snackBarDurationImportant,
            ),
          );
          // 成功更新后，关闭页面并返回
          Navigator.of(context).pop(true); // 返回true表示更新成功
        }
      } else {
        // 添加新笔记（初始Quote为null或无ID时）
        logDebug('添加新笔记');
        await db.addQuote(quote);
        _draftSaveTimer?.cancel();
        await _clearDraft();
        _didSaveSuccessfully = true; // 标记保存成功，避免会话级清理
        _isRestoredFromDraft = false; // 保存成功后，不再视为恢复的草稿
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).noteSaved),
              duration: AppConstants.snackBarDurationImportant,
            ),
          );
          // 成功添加后，关闭页面并返回
          Navigator.of(context).pop(true); // 返回true表示保存成功
        }
      }
    } catch (e) {
      await _rollbackMovedPermanentMediaFiles(movedToPermanentForThisSave);
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.saveFailed(e.toString())),
            backgroundColor: Colors.red,
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    } finally {
      if (mounted) {
        _updateState(() {
          _saveProgress = 1.0;
          _saveStatus = l10n.saveComplete;
        });
        Future.delayed(const Duration(milliseconds: 320), () {
          if (mounted) {
            _updateState(() {
              _isSaving = false;
            });
          }
        });
      }
    }
  }

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

  Future<void> _rollbackMovedPermanentMediaFiles(
      List<String> movedPaths) async {
    if (movedPaths.isEmpty) {
      return;
    }
    try {
      await Future.wait(
        movedPaths.map((p) async {
          try {
            final deleted = await MediaFileService.deleteMediaFile(p);
            if (deleted) {
              logDebug('因保存失败，回滚删除永久媒体文件: $p');
            }
          } catch (itemErr) {
            logDebug('单个媒体文件回滚删除失败: $p, $itemErr');
          }
        }),
      );
    } catch (rollbackErr) {
      logDebug('保存失败后的媒体回滚删除出错: $rollbackErr');
    }
  }

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

  Widget _tagAvatarSmall(String? iconName) {
    if (IconUtils.isEmoji(iconName)) {
      return Text(
        IconUtils.getDisplayIcon(iconName),
        style: const TextStyle(fontSize: 16),
      );
    }
    return Icon(IconUtils.getIconData(iconName), size: 16);
  }

  Widget _buildTagIcon(NoteCategory tag) {
    return _tagAvatarSmall(tag.iconName);
  }
}
