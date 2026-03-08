part of '../note_full_editor_page.dart';

/// Main build method for the note editor page.
extension NoteEditorBuild on _NoteFullEditorPageState {
  Widget _buildEditorPage(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        // 有未保存的内容，提示用户
        final hasUnsavedChanges = _hasUnsavedChanges();
        if (!hasUnsavedChanges) {
          if (context.mounted) {
            // 没有未保存的更改，安全退出并清理草稿
            _clearDraft();
            Navigator.pop(context);
          }
          return;
        }

        final shouldDiscard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.unsavedChangesTitle),
            content: Text(l10n.unsavedChangesDesc),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.continueEditing),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  l10n.discardChanges,
                  style: TextStyle(color: Colors.red.shade400),
                ),
              ),
            ],
          ),
        );

        if (shouldDiscard ?? false) {
          if (context.mounted) {
            // 用户选择放弃更改，清理草稿
            _clearDraft();
            Navigator.pop(context);
          }
        }
      },
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          title: const SizedBox.shrink(),
          actions: [
            IconButton(
              key: _metadataButtonKey, // 功能引导 key
              icon: const Icon(Icons.edit_note),
              tooltip: l10n.editMetadataShort,
              onPressed: () => _showMetadataDialog(context),
            ),
            IconButton(
              icon: const Icon(Icons.auto_awesome),
              tooltip: l10n.aiAssistantLabel,
              onPressed: () => _showAIOptions(context),
            ),
            IconButton(
              icon: _isLoadingFullQuote
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.grey, // 适配 AppBar 颜色
                      ),
                    )
                  : const Icon(Icons.save),
              tooltip: l10n.save,
              onPressed: _isLoadingFullQuote
                  ? null
                  : () async {
                      try {
                        await pauseAllMediaPlayers();
                      } catch (e) {
                        debugPrint('[NoteFullEditorPage] pauseAllMediaPlayers failed: $e');
                      }
                      await _saveContent();
                    },
            ),
          ],
          automaticallyImplyLeading: true,
        ),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  UnifiedQuillToolbar(
                    key: _toolbarGuideKey, // 新增：用于气泡定位
                    controller: _controller,
                    onMediaImported: (String filePath) {
                      _sessionImportedMedia.add(filePath);
                    },
                  ),
                  if (_selectedTagIds.isNotEmpty ||
                      _selectedColorHex != null ||
                      _showLocation ||
                      _showWeather)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        border: Border(
                          bottom: BorderSide(
                            color:
                                theme.colorScheme.outlineVariant.applyOpacity(
                              0.1,
                            ),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          if (_selectedTagIds.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Chip(
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                label: Text(
                                  l10n.tagsCount(_selectedTagIds.length),
                                ),
                                avatar: const Icon(Icons.tag, size: 16),
                              ),
                            ),
                          if (_selectedColorHex != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: Color(
                                    int.parse(
                                          _selectedColorHex!.substring(1),
                                          radix: 16,
                                        ) |
                                        0xFF000000,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color:
                                        theme.colorScheme.outline.applyOpacity(
                                      0.2,
                                    ),
                                    width: 1,
                                  ),
                                ),
                                key: ValueKey(
                                  'color-indicator-$_selectedColorHex',
                                ),
                              ),
                            ),
                          if (_showLocation &&
                              (_location != null ||
                                  (_latitude != null && _longitude != null)))
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Icon(
                                Icons.location_on,
                                size: 16,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          if (_showWeather && _weather != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Icon(
                                _getWeatherIcon(_weather!),
                                size: 16,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => _showMetadataDialog(context),
                            child: const Text(
                              '编辑元数据',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: Container(
                      color: theme.colorScheme.surface,
                      padding: const EdgeInsets.all(16),
                      child: quill.QuillEditor(
                        controller: _controller,
                        scrollController: ScrollController(),
                        focusNode: FocusNode(),
                        config: quill.QuillEditorConfig(
                          embedBuilders: kIsWeb
                              ? FlutterQuillEmbeds.editorWebBuilders()
                              : QuillEditorExtensions.getEmbedBuilders(
                                  optimizedImages: false,
                                ),
                          placeholder: AppLocalizations.of(context)
                              .fullscreenEditorPlaceholder,
                          padding: const EdgeInsets.all(16),
                          autoFocus: false,
                          expands: false,
                          scrollable: true,
                          enableInteractiveSelection: true,
                          enableSelectionToolbar: true,
                          showCursor: true,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_isSaving)
                Positioned.fill(
                  child: Container(
                    color: theme.colorScheme.surface.withValues(alpha: 0.72),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 300),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 24,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 18,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      value: _saveProgress >= 0.99
                                          ? 1.0
                                          : (_saveProgress <= 0
                                              ? null
                                              : _saveProgress),
                                      strokeWidth: 3,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    _saveProgress < 1.0 ? '正在保存' : '完成',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              LinearProgressIndicator(
                                value: _saveProgress.clamp(0.0, 1.0),
                                minHeight: 6,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              const SizedBox(height: 12),
                              if (_saveStatus != null)
                                Text(
                                  _saveStatus!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              const SizedBox(height: 8),
                              Text(
                                '${(_saveProgress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                                style: theme.textTheme.labelMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
