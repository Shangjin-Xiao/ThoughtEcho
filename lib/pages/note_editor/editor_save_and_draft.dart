part of '../note_full_editor_page.dart';

/// Draft management, save logic, and state helper methods.
extension _NoteEditorSaveAndDraft on _NoteFullEditorPageState {
  void _initializeAsPlainText([String? text]) {
    try {
      if (mounted) {
        final contentText = text ??
            ((widget.initialQuote != null &&
                    widget.initialQuote!.content.isNotEmpty)
                ? widget.initialQuote!.content
                : widget.initialContent);
        _updateState(() {
          _editorState.controller = quill.QuillController(
            document: quill.Document()..insert(0, contentText),
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
          _editorState.controller = quill.QuillController.basic();
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
                final docLength = _editorState.controller.document.length;
                final safeInsertPosition = currentInsertPosition.clamp(
                  0,
                  docLength - 1,
                );

                _editorState.controller.document
                    .insert(safeInsertPosition, chunk);

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
              _editorState.controller.document.insert(0, errorMessage);
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

  void _attachDraftListener() {
    _editorState.setDraftChangeListener(_onDraftChanged);
  }

  void _onDraftChanged() {
    _editorState.scheduleDraftSave(
      const Duration(seconds: 2),
      _saveDraft,
    );
  }

  Future<void> _saveDraft() async {
    try {
      final key = _editorState.draftStorageKey;
      if (key.isEmpty) return;
      final plainText = _editorState.controller.document.toPlainText().trim();

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
        'author': _metadataState.authorController.text,
        'work': _metadataState.workController.text,
        'tagIds': _metadataState.selectedTagIds,
        'colorHex': _metadataState.selectedColorHex,
        'location':
            _metadataState.showLocation ? _metadataState.location : null,
        'poiName': _metadataState.showLocation ? _metadataState.poiName : null,
        'latitude': (_metadataState.showLocation || _metadataState.showWeather)
            ? _metadataState.latitude
            : null,
        'longitude': (_metadataState.showLocation || _metadataState.showWeather)
            ? _metadataState.longitude
            : null,
        'weather': _metadataState.showWeather ? _metadataState.weather : null,
        'temperature':
            _metadataState.showWeather ? _metadataState.temperature : null,
        'aiAnalysis': _metadataState.currentAiAnalysis,
        'timestamp': DateTime.now().toIso8601String(),
        'hasUserContent': hasUserContent,
      };
      // 使用 DraftService 保存草稿
      await DraftService().saveDraft(key, payload);
    } catch (e) {
      logDebug('保存草稿失败: $e');
    }
  }

  void _resetSaveUiAfterFailure() {
    if (!mounted) return;

    _updateState(() {
      _mediaState.saveProgress = 0.0;
      _mediaState.isSaving = false;
    });
  }

  /// 检查是否有用户实际输入的内容（非自动填充的内容）
  bool _hasActualUserContent() {
    // 检查正文内容是否有变化
    final currentPlainText =
        _editorState.controller.document.toPlainText().trim();
    if (currentPlainText != _editorState.initialPlainText.trim() &&
        currentPlainText.isNotEmpty) {
      return true;
    }

    // 如果是恢复的草稿，视为有用户内容
    if (_editorState.restoredFromDraft) {
      return true;
    }

    return false;
  }

  Future<void> _clearDraft() async {
    try {
      final key = _editorState.draftStorageKey;
      if (key.isEmpty) return;
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
    if (_editorState.restoredFromDraft) {
      return true;
    }

    // 如果是来自每日一言且内容未修改，不提示未保存（双击每日一言快速进入，不需要提示）
    final currentPlainText =
        _editorState.controller.document.toPlainText().trim();
    if (widget.isFromDailyQuote &&
        currentPlainText == _editorState.initialPlainText.trim()) {
      return false;
    }

    // 检查主要内容
    if (currentPlainText != _editorState.initialPlainText.trim()) {
      return true;
    }
    if (_metadataState.hasChanges(
      isExistingNote: widget.initialQuote != null,
    )) {
      return true;
    }

    // Notes that predate rich text have no persisted Delta. Their plain-text
    // comparison above is the authoritative change signal until the note is
    // saved once in the editor; comparing a generated Delta would otherwise
    // mark an untouched note as edited.
    final initialDeltaContent = _editorState.initialDeltaContent;
    if (initialDeltaContent != null) {
      final currentDeltaContent = jsonEncode(
        _editorState.controller.document.toDelta().toJson(),
      );
      if (currentDeltaContent != initialDeltaContent) {
        return true;
      }
    }

    return false;
  }

  Future<void> _saveContent() async {
    // Set the guard before the first await so every save entry point, including
    // the app-bar action, is protected from rapid repeated taps.
    if (_mediaState.isSaving) return;
    _mediaState.isSaving = true;

    _editorState.cancelDraftSave();
    _editorState.draftLoaded = false;

    final db = Provider.of<DatabaseService>(context, listen: false);

    final l10n = AppLocalizations.of(context);
    bool saveSucceeded = false;
    logDebug('开始保存笔记内容...');
    if (mounted) {
      _updateState(() {
        _mediaState.saveProgress = 0.0;
        _mediaState.saveStatus = l10n.preparingProcess;
      });
    }

    try {
      await pauseAllMediaPlayers();
    } catch (e) {
      debugPrint('[NoteFullEditorPage] pauseAllMediaPlayers failed: $e');
    }

    // 处理临时媒体文件，带进度
    // 为了在保存失败时回滚，记录本次从临时目录移动到永久目录的文件
    final List<String> movedToPermanentForThisSave = [];
    try {
      await _processTemporaryMediaFiles(
        onProgress: (p, status) {
          if (mounted) {
            _updateState(() {
              _mediaState.saveProgress = p.clamp(0.0, 1.0);
              if (status != null) _mediaState.saveStatus = status;
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
    final baseQuote = _editorState.fullInitialQuote ?? widget.initialQuote;

    if (_editorState.richTextLoadFailed && baseQuote?.deltaContent != null) {
      logDebug('富文本未能无损加载，阻止保存覆盖原始deltaContent');
      await _rollbackMovedPermanentMediaFiles(movedToPermanentForThisSave);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.richTextSaveUnavailable),
            backgroundColor: Colors.red,
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
      _editorState.draftLoaded = true;
      _resetSaveUiAfterFailure();
      return;
    }

    try {
      plainTextContent = _editorState.controller.document.toPlainText().trim();
      logDebug('获取到纯文本内容: ${plainTextContent.length} 字符');

      // 使用内存安全的方法获取富文本内容
      deltaJson = await _getDocumentContentSafely();

      logDebug('富文本JSON长度: ${deltaJson.length}');
      logDebug(
        '富文本JSON内容示例: ${deltaJson.substring(0, min(100, deltaJson.length))}...',
      );
    } on DeltaContentSerializationException catch (e) {
      logDebug('获取文档内容失败: $e');
      await _rollbackMovedPermanentMediaFiles(movedToPermanentForThisSave);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.richTextSaveUnavailable),
            backgroundColor: Colors.red,
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
      _editorState.draftLoaded = true;
      _resetSaveUiAfterFailure();
      return;
    } catch (e) {
      logDebug('获取文档内容失败: $e');
      await _rollbackMovedPermanentMediaFiles(movedToPermanentForThisSave);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.documentLoadFailed),
            backgroundColor: Colors.orange,
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
      _editorState.draftLoaded = true;
      _resetSaveUiAfterFailure();
      return;
    }

    final now = DateTime.now().toIso8601String();

    // 获取当前时间段
    final String currentDayPeriodKey =
        TimeUtils.getCurrentDayPeriodKey(); // 使用 Key

    // 构建笔记对象
    // 优先使用 _editorState.fullInitialQuote 中的数据，以保留未加载的字段（如aiAnalysis等）
    final quote = Quote(
      id: baseQuote?.id ?? const Uuid().v4(),
      content: plainTextContent,
      date: baseQuote?.date ?? now,
      aiAnalysis: _metadataState.currentAiAnalysis ?? baseQuote?.aiAnalysis,
      source: _formatSource(_metadataState.authorController.text,
          _metadataState.workController.text),
      sourceAuthor: _metadataState.authorController.text,
      sourceWork: _metadataState.workController.text,
      tagIds: _metadataState.selectedTagIds,
      sentiment: baseQuote?.sentiment,
      keywords: baseQuote?.keywords,
      summary: baseQuote?.summary,
      categoryId: baseQuote?.categoryId,
      colorHex: _metadataState.selectedColorHex,
      location: _metadataState.showLocation
          ? (_metadataState.location ??
              (_metadataState.latitude != null
                  ? LocationService.kAddressPending
                  : null))
          : null,
      poiName: _metadataState.showLocation ? _metadataState.poiName : null,
      latitude: _metadataState.showLocation ? _metadataState.latitude : null,
      longitude: _metadataState.showLocation ? _metadataState.longitude : null,
      weather: _metadataState.showWeather ? _metadataState.weather : null,
      temperature:
          _metadataState.showWeather ? _metadataState.temperature : null,
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
          _mediaState.saveStatus = l10n.writingDatabase;
          _mediaState.saveProgress =
              _mediaState.saveProgress < 0.9 ? 0.9 : _mediaState.saveProgress;
        });
      }

      if (widget.initialQuote != null && widget.initialQuote?.id != null) {
        // 只有当initialQuote存在且有ID时，才更新现有笔记
        logDebug('更新现有笔记，ID: ${quote.id}');
        final updateResult = await db.updateQuote(quote);
        if (updateResult != QuoteUpdateResult.updated) {
          await _rollbackMovedPermanentMediaFiles(movedToPermanentForThisSave);
          _editorState.draftLoaded = true;
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
        _editorState.cancelDraftSave();
        await _clearDraft();
        _mediaState.markSavedSuccessfully();
        _editorState.markDraftSaved();
        saveSucceeded = true;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).noteSaved),
              duration: AppConstants.snackBarDurationImportant,
            ),
          );
          Navigator.of(context).pop(true);
        }
      } else {
        logDebug('添加新笔记');
        await db.addQuote(quote);
        _editorState.cancelDraftSave();
        await _clearDraft();
        _mediaState.markSavedSuccessfully();
        _editorState.markDraftSaved();
        saveSucceeded = true;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).noteSaved),
              duration: AppConstants.snackBarDurationImportant,
            ),
          );
          Navigator.of(context).pop(true);
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
          if (saveSucceeded) {
            _mediaState.saveProgress = 1.0;
            _mediaState.saveStatus = l10n.saveComplete;
          } else {
            _mediaState.saveProgress = 0.0;
          }
        });
        Future.delayed(const Duration(milliseconds: 320), () {
          if (mounted) {
            _updateState(() {
              _mediaState.isSaving = false;
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
    List<String> movedPaths,
  ) async {
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
            logError(
              '单个媒体文件回滚删除失败: $p',
              error: itemErr,
              source: 'NoteFullEditorPage',
            );
          }
        }),
      );
    } catch (rollbackErr) {
      logError(
        '保存失败后的媒体回滚删除出错',
        error: rollbackErr,
        source: 'NoteFullEditorPage',
      );
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
