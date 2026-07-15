part of '../ai_assistant_page.dart';

extension _AIAssistantPageUI on _AIAssistantPageState {
  void _onInputFocusChanged() {
    if (!mounted || _isInputFocused == _inputFocusNode.hasFocus) {
      return;
    }
    _setState(() {
      _isInputFocused = _inputFocusNode.hasFocus;
    });
  }

  Widget _buildPage(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _hasBoundNote ? l10n.askNoteTitle : l10n.aiAssistantLabel,
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment),
            tooltip: l10n.newChat,
            onPressed: _startNewChat,
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: l10n.chatHistory,
            onPressed: _isLoading ? null : _showSessionHistory,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_hasBoundNote) _buildNoteContextBanner(theme),
          if (_entrySource == AIAssistantEntrySource.explore &&
              widget.exploreGuideSummary?.trim().isNotEmpty == true)
            _buildExploreGuideBanner(theme, l10n),
          Expanded(
            child: Stack(
              children: [
                NotificationListener<ScrollUpdateNotification>(
                  onNotification: (notification) {
                    if (notification.scrollDelta != null &&
                        notification.dragDetails != null) {
                      if (notification.scrollDelta! < 0) {
                        _setAutoScrollEnabled(false);
                      }
                    }
                    return false;
                  },
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return _buildMessageBubble(_messages[index], theme, l10n);
                    },
                  ),
                ),
                if (_showScrollToBottom)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Material(
                          color: theme.colorScheme.surfaceContainerHigh,
                          elevation: 2,
                          shape: const CircleBorder(),
                          child: IconButton(
                            key: const ValueKey(
                              'ai_assistant_scroll_to_bottom',
                            ),
                            onPressed: _resumeAutoScroll,
                            icon: const Icon(Icons.arrow_downward, size: 18),
                            visualDensity: VisualDensity.compact,
                            tooltip: l10n.scrollToBottom,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _buildInputArea(theme, l10n),
        ],
      ),
    );
  }

  Widget _buildExploreGuideBanner(ThemeData theme, AppLocalizations l10n) {
    // Removed DataOverview banner - user guidance moved to welcome message only
    return const SizedBox.shrink();
  }

  Widget _buildNoteContextBanner(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(8),
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Row(
        children: [
          Icon(Icons.description, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${AppLocalizations.of(context).currentNoteContext}: ${_getQuotePreview()}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(
    app_chat.ChatMessage message,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    if (message.metaJson != null) {
      try {
        final meta = jsonDecode(message.metaJson!) as Map<String, dynamic>;
        switch (meta['type']) {
          case NoteProposalArtifact.typeName:
            final rawArtifact = meta['artifact'];
            if (rawArtifact is! Map) return const SizedBox.shrink();
            final artifact = NoteProposalArtifact.fromJson(
              rawArtifact.map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            );
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: NoteProposalCard(
                key: const ValueKey('ai_workflow_result_note_proposal'),
                artifact: artifact,
                plainCreateOpensRich:
                    artifact.action == NoteProposalAction.create &&
                        artifact.resultKind == NoteDocumentKind.plain &&
                        context.read<SettingsService>().skipNonFullscreenEditor,
                initialCompleted: meta['saved_note_id'] != null,
                onOpenInEditor: () => _openNoteProposalInEditor(artifact),
                onApply: () async {
                  final noteId = await _applyNoteProposal(artifact);
                  if (noteId == null) return false;
                  _updateSmartResultSavedNoteId(message.id, noteId);
                  return true;
                },
              ),
            );
          case 'smart_result':
            final action = meta['action']?.toString();
            final isNewNoteProposal = action == 'create';
            final legacyReadOnly =
                !isNewNoteProposal && meta['rich_edit'] == null;
            final initialNewNoteMetadata =
                isNewNoteProposal ? _resolveInitialNewNoteMetadata(meta) : null;
            final rawTagNames = meta['tag_names'] as List<dynamic>? ?? const [];
            final tagNames = rawTagNames
                .map((item) => item.toString().trim())
                .where((item) => item.isNotEmpty)
                .toList();
            final tagIds = _extractStringList(meta['tag_ids']);
            final rawTagIconNames =
                meta['tag_icon_names'] as List<dynamic>? ?? const [];
            final tags = <NoteCategory>[
              for (var index = 0; index < tagNames.length; index++)
                NoteCategory(
                  id: index < tagIds.length ? tagIds[index] : tagNames[index],
                  name: tagNames[index],
                  iconName: index < rawTagIconNames.length
                      ? rawTagIconNames[index]?.toString()
                      : null,
                ),
            ];
            final locationService = context.read<LocationService>();
            final weatherService = context.read<WeatherService>();
            final originalLocation =
                meta['original_location']?.toString() ?? widget.quote?.location;
            final locationPreview = isNewNoteProposal
                ? (locationService.getDisplayLocation().isNotEmpty
                    ? locationService.getDisplayLocation()
                    : null)
                : (LocationService.isNonDisplayMarker(originalLocation)
                    ? null
                    : LocationService.formatLocationForDisplay(
                        originalLocation,
                      ));
            final weatherKey = isNewNoteProposal
                ? weatherService.currentWeather
                : (meta['original_weather']?.toString() ??
                    widget.quote?.weather);
            final temperature = isNewNoteProposal
                ? weatherService.temperature
                : (meta['original_temperature']?.toString() ??
                    widget.quote?.temperature);
            final weatherPreview = weatherKey != null
                ? '${WeatherCodeMapper.getLocalizedDescription(l10n, weatherKey)}${temperature != null ? ' $temperature' : ''}'
                : null;
            final existingHasLocation = meta['original_has_location'] == true ||
                (!LocationService.isNonDisplayMarker(
                      widget.quote?.location,
                    ) ||
                    (widget.quote?.latitude != null &&
                        widget.quote?.longitude != null));
            final existingHasWeather = meta['original_has_weather'] == true ||
                widget.quote?.weather != null;
            final initialIncludeLocation = isNewNoteProposal
                ? initialNewNoteMetadata!.includeLocation
                : (_readOptionalBool(meta, 'include_location') ??
                    existingHasLocation);
            final initialIncludeWeather = isNewNoteProposal
                ? initialNewNoteMetadata!.includeWeather
                : (_readOptionalBool(meta, 'include_weather') ??
                    existingHasWeather);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SmartResultCard(
                key: const ValueKey('ai_workflow_result_smart_result'),
                title: meta['title'] as String? ?? l10n.analysisResult,
                content: message.content,
                author: meta['author']?.toString(),
                source: meta['source']?.toString(),
                tags: tags,
                locationPreview: locationPreview,
                weatherPreview: weatherPreview,
                editorSource: isNewNoteProposal ? 'new_note' : 'fullscreen',
                initialIncludeLocation: initialIncludeLocation,
                initialIncludeWeather: initialIncludeWeather,
                initialSavedNoteId: meta['saved_note_id']?.toString(),
                readOnly: legacyReadOnly,
                onOpenDraftInEditor: (draft) async {
                  try {
                    final updatedMeta =
                        await _buildSmartResultMetaFromDraft(meta, draft);
                    if (isNewNoteProposal) {
                      final confirmedMetadata =
                          _resolveConfirmedNewNoteMetadata(
                        updatedMeta,
                        includeLocation: draft.includeLocation,
                        includeWeather: draft.includeWeather,
                      );
                      await _openSmartResultAsNewNote(
                        draft.content,
                        richDocument: updatedMeta['rich_document'],
                        tagIds: confirmedMetadata.tagIds,
                        author: confirmedMetadata.author,
                        source: confirmedMetadata.source,
                        includeLocation: confirmedMetadata.includeLocation,
                        includeWeather: confirmedMetadata.includeWeather,
                      );
                    } else {
                      await _openSmartResultInEditor(
                        updatedMeta,
                        draft.content,
                      );
                    }
                  } catch (e, stack) {
                    logError(
                      '打开编辑器失败',
                      error: e,
                      stackTrace: stack,
                      source: 'ai_assistant_page_ui',
                    );
                    if (mounted) {
                      final l10n = AppLocalizations.of(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            l10n.openFullEditorFailedSimple,
                          ),
                        ),
                      );
                    }
                  }
                },
                onSaveDraftDirectly: (draft) async {
                  final updatedMeta =
                      await _buildSmartResultMetaFromDraft(meta, draft);
                  if (isNewNoteProposal) {
                    final confirmedMetadata = _resolveConfirmedNewNoteMetadata(
                      updatedMeta,
                      includeLocation: draft.includeLocation,
                      includeWeather: draft.includeWeather,
                    );
                    updatedMeta['tag_ids'] = confirmedMetadata.tagIds;
                    updatedMeta['author'] = confirmedMetadata.author;
                    updatedMeta['source'] = confirmedMetadata.source;
                    updatedMeta['include_location'] =
                        confirmedMetadata.includeLocation;
                    updatedMeta['include_weather'] =
                        confirmedMetadata.includeWeather;
                    return _saveSmartResultAsNewNote(
                      updatedMeta,
                      draft.content,
                    );
                  } else {
                    return _saveSmartResultToExistingNote(
                      updatedMeta,
                      draft.content,
                    );
                  }
                },
                onSavedNoteId: (noteId) {
                  _updateSmartResultSavedNoteId(message.id, noteId);
                },
              ),
            );
          case 'notice':
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: AIWorkflowNoticeCard(
                title: meta['title'] as String? ?? l10n.notice,
                message: message.content,
                icon: Icons.info_outline,
              ),
            );
          case 'source_analysis_result':
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: AISourceAnalysisResultCard(
                title: meta['title'] as String? ?? l10n.analysisResult,
                author: meta['author'] as String?,
                work: meta['work'] as String?,
                confidence: meta['confidence'] as String? ?? l10n.unknown,
                explanation: message.content.isNotEmpty
                    ? message.content
                    : (meta['explanation'] as String? ?? ''),
                authorLabel: '${l10n.possibleAuthor} ',
                workLabel: '${l10n.possibleWork} ',
                confidenceLabel: '${l10n.confidenceLabel} ',
              ),
            );
          case 'insight_config':
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: AIInsightWorkflowCard(
                title: l10n.commandInsight,
                analysisTypes: _buildInsightTypeLabels(l10n),
                analysisStyles: _buildInsightStyleLabels(l10n),
                selectedType: _selectedInsightType,
                selectedStyle: _selectedInsightStyle,
                onSelectType: (value) {
                  _setState(() {
                    _selectedInsightType = value;
                  });
                },
                onSelectStyle: (value) {
                  _setState(() {
                    _selectedInsightStyle = value;
                  });
                },
                onRun: () {
                  _runInsightsWorkflow();
                },
                runLabel: l10n.startAnalysis,
              ),
            );
          case 'tool_progress':
            final rawItems = meta['items'] as List<dynamic>? ?? [];
            // 从历史恢复的 tool_progress 消息不应再转圈：
            // 如果 message 不处于 loading 状态，强制 inProgress=false
            final inProgress =
                message.isLoading && (meta['inProgress'] as bool? ?? false);
            final progressItems = rawItems.map((item) {
              final map = item as Map<String, dynamic>;
              return ToolProgressItem(
                toolCallId: map['toolCallId'] as String?,
                toolName: map['toolName'] as String? ?? '',
                description: map['description'] as String?,
                status: ToolProgressStatus.values.firstWhere(
                  (s) => s.name == (map['status'] as String? ?? 'pending'),
                  orElse: () => ToolProgressStatus.pending,
                ),
                result: map['result'] as String?,
                narrationText: map['narrationText'] as String?,
              );
            }).toList();
            return Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 6,
                horizontal: 12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: 4,
                      left: 4,
                      right: 4,
                    ),
                    child: Text(
                      l10n.aiAssistantUser,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  ToolProgressPanel(
                    title: l10n.toolExecutionProgress,
                    items: progressItems,
                    inProgress: inProgress,
                    accentColor: theme.colorScheme.primary,
                    thinkingText: meta['thinkingText'] as String?,
                  ),
                ],
              ),
            );
        }
      } catch (e, stack) {
        logError(
          'Failed to render AI workflow message',
          error: e,
          stackTrace: stack,
          source: 'ai_assistant_page_ui',
        );
      }
    }

    final isUser = message.isUser;

    // Material 3 semantic colors
    final userBubbleColor = theme.colorScheme.primary;
    final agentBubbleColor = theme.colorScheme.surfaceContainerHigh;
    final bubbleColor = isUser ? userBubbleColor : agentBubbleColor;

    final bubbleTextColor =
        isUser ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;

    final bubbleRadius = const Radius.circular(24);
    final borderRadius = BorderRadius.only(
      topLeft: isUser ? bubbleRadius : Radius.zero,
      topRight: isUser ? Radius.zero : bubbleRadius,
      bottomLeft: bubbleRadius,
      bottomRight: bubbleRadius,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Sender Label with Timestamp
          Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment:
                  isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                Text(
                  isUser ? l10n.meUser : l10n.aiAssistantUser,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  TimeUtils.formatRelativeDateTimeLocalized(
                      context, message.timestamp),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // 思考内容显示（仅当有思考且非用户消息时）
          // 性能优化：只 join 一次，避免重复字符串拼接
          if (!isUser && message.thinkingChunks.isNotEmpty)
            Builder(
              builder: (context) {
                final thinkingText = message.thinkingChunks.join('');
                if (thinkingText.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ThinkingWidget(
                    key: ValueKey('thinking_${message.id}'),
                    thinkingText: thinkingText,
                    inProgress: message.state == MessageState.thinking,
                    accentColor: theme.colorScheme.primary,
                  ),
                );
              },
            ),
          // Main Content Bubble
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: borderRadius,
            ),
            child: isUser
                ? Text(
                    message.content,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: bubbleTextColor,
                      height: 1.5,
                    ),
                  )
                : MarkdownBody(
                    data: message.content.isEmpty
                        ? l10n.thinkingInProgress
                        : message.content,
                    selectable: true,
                    // 性能优化：缓存 MarkdownStyleSheet，避免每帧重建
                    styleSheet: _getMarkdownStyleSheet(theme, bubbleTextColor),
                  ),
          ),
        ],
      ),
    );
  }

  Map<String, String> _buildInsightTypeLabels(AppLocalizations l10n) {
    return <String, String>{
      for (final option in AIInsightWorkflowOptions.analysisTypes)
        option.key: switch (option.l10nKey) {
          'comprehensive' => l10n.analysisTypeComprehensive,
          'emotional' => l10n.analysisTypeEmotional,
          'mindmap' => l10n.analysisTypeMindmap,
          'growth' => l10n.analysisTypeGrowth,
          _ => option.key,
        },
    };
  }

  Map<String, String> _buildInsightStyleLabels(AppLocalizations l10n) {
    return <String, String>{
      for (final option in AIInsightWorkflowOptions.analysisStyles)
        option.key: switch (option.l10nKey) {
          'professional' => l10n.analysisStyleProfessional,
          'friendly' => l10n.analysisStyleFriendly,
          'humorous' => l10n.analysisStyleHumorous,
          'literary' => l10n.analysisStyleLiterary,
          _ => option.key,
        },
    };
  }

  void _onAgentServiceChanged() {
    if (!mounted) return;
  }

  Widget _buildInputArea(ThemeData theme, AppLocalizations l10n) {
    final shellBorderColor = _isInputFocused
        ? theme.colorScheme.primary.withValues(alpha: 0.6)
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.75);

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: shellBorderColor,
            width: _isInputFocused ? 1.4 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: theme.brightness == Brightness.dark ? 0.26 : 0.07,
              ),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Text field
            TextField(
              controller: _textController,
              focusNode: _inputFocusNode,
              decoration: InputDecoration(
                hintText: l10n.aiAssistantInputHint,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              maxLines: null,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: _handleSubmitted,
            ),
            // Action row: thinking | send
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
              child: Row(
                children: [
                  // Agent requests do not yet apply provider thinking settings.
                  if (!_isAgentMode && _currentModelSupportsThinking)
                    IconButton(
                      icon: Icon(
                        _enableThinking
                            ? Icons.psychology
                            : Icons.psychology_outlined,
                        size: 20,
                        color: _enableThinking
                            ? theme.colorScheme.secondary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      onPressed: _isLoading
                          ? null
                          : () {
                              unawaited(
                                _setThinkingEnabled(!_enableThinking),
                              );
                            },
                      style: IconButton.styleFrom(
                        padding: const EdgeInsets.all(8),
                        minimumSize: const Size(36, 36),
                      ),
                    ),
                  const Spacer(),
                  // Send / Stop
                  IconButton(
                    icon: Icon(
                      _isLoading ? Icons.stop : Icons.arrow_upward,
                      size: 20,
                    ),
                    onPressed: _isLoading
                        ? _stopGenerating
                        : () {
                            if (_textController.text.trim().isNotEmpty) {
                              _handleSubmitted(_textController.text);
                            }
                          },
                    style: IconButton.styleFrom(
                      backgroundColor: _isLoading
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                      foregroundColor: _isLoading
                          ? theme.colorScheme.onError
                          : theme.colorScheme.onPrimary,
                      padding: const EdgeInsets.all(8),
                      minimumSize: const Size(36, 36),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSmartResultInEditor(
    Map<String, dynamic> meta,
    String content,
  ) async {
    final modeAction =
        meta['action']?.toString() == 'append' ? 'append' : 'replace';
    final noteId = meta['note_id']?.toString() ??
        (_hasBoundNote ? widget.quote!.id : null);

    if (noteId != null && noteId.isNotEmpty) {
      final db = context.read<DatabaseService>();
      final note = await db.getQuoteById(noteId);
      final tags = await db.getCategories();
      if (!mounted) {
        return;
      }
      if (note != null) {
        Quote? richEditedNote;
        try {
          richEditedNote = _applyStructuredEdit(note, meta);
        } on RichTextEditConflict {
          _showRichEditConflict();
          return;
        } on RichTextEditMatchFailure {
          _showRichEditConflict();
          return;
        }
        // 根据润色(replace) / 续写(append) 决定带入编辑器的初始文本
        final plainContent = DeltaBuilder.markdownToPlainText(content);
        final mergedContent = richEditedNote?.content ??
            (modeAction == 'append'
                ? '${note.content}\n$plainContent'
                : plainContent);

        // 合并 Agent 建议的元数据（标签、作者、出处）
        final rawSuggestedTagIds = meta['tag_ids'] as List<dynamic>?;
        final suggestedTagIds = rawSuggestedTagIds
            ?.map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList();
        final suggestedAuthor = meta['author']?.toString();
        final suggestedSource = meta['source']?.toString();
        // 使用 DeltaBuilder 合并修改并生成新的 deltaContent，保持双存储一致
        final String updatedDeltaContent;
        if (richEditedNote != null) {
          updatedDeltaContent = richEditedNote.deltaContent!;
        } else if (modeAction == 'append') {
          final updatedOps = DeltaBuilder.appendMarkdownToDelta(
            originalDeltaJson: note.deltaContent,
            markdown: content,
          );
          updatedDeltaContent = DeltaBuilder.deltaToJson(updatedOps);
        } else {
          final updatedOps = DeltaBuilder.replaceMarkdownInDelta(
            originalDeltaJson: note.deltaContent,
            markdown: content,
          );
          updatedDeltaContent = DeltaBuilder.deltaToJson(updatedOps);
        }

        final noteForEditor = note.copyWith(
          content: mergedContent,
          deltaContent: updatedDeltaContent,
          tagIds: suggestedTagIds ?? note.tagIds,
          sourceAuthor: suggestedAuthor ?? note.sourceAuthor,
          sourceWork: suggestedSource ?? note.sourceWork,
        );
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NoteFullEditorPage(
              initialContent: mergedContent,
              initialQuote: noteForEditor,
              allTags: tags,
              skipDefaultMetadataAutofill: true,
            ),
          ),
        );
        return;
      }
    }

    // 没有 note_id 或找不到笔记时，fallback 为新建笔记
    final rawTagIds = meta['tag_ids'] as List<dynamic>? ?? const [];
    final tagIds = rawTagIds
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
    await _openSmartResultAsNewNote(
      content,
      richDocument: meta['rich_document'],
      tagIds: tagIds,
      author: meta['author']?.toString(),
      source: meta['source']?.toString(),
      includeLocation: meta['include_location'] == true,
      includeWeather: meta['include_weather'] == true,
    );
  }

  Future<void> _openNoteProposalInEditor(
    NoteProposalArtifact artifact,
  ) async {
    final db = context.read<DatabaseService>();
    if (artifact.action == NoteProposalAction.create) {
      final validatedOps = _validatedArtifactOps(artifact);
      if (artifact.resultKind == NoteDocumentKind.plain &&
          !context.read<SettingsService>().skipNonFullscreenEditor) {
        final tags = await db.getCategories();
        if (!mounted) return;
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => AddNoteDialog(
            prefilledContent: artifact.content,
            prefilledTagIds: _extractStringList(
              artifact.metadata['tag_ids'],
            ),
            prefilledAuthor: artifact.metadata['author']?.toString(),
            prefilledWork: artifact.metadata['source']?.toString(),
            prefilledIncludeLocation:
                artifact.metadata['include_location'] == true,
            prefilledIncludeWeather:
                artifact.metadata['include_weather'] == true,
            useAIPrefilledLocationWeather: true,
            tags: tags,
            onSave: db.addQuote,
          ),
        );
        return;
      }
      final richOps = validatedOps ??
          [
            {'insert': '${artifact.content}\n'}
          ];
      await _openSmartResultAsNewNote(
        artifact.content,
        richDocument: richOps,
        tagIds: _extractStringList(artifact.metadata['tag_ids']),
        author: artifact.metadata['author']?.toString(),
        source: artifact.metadata['source']?.toString(),
        includeLocation: artifact.metadata['include_location'] == true,
        includeWeather: artifact.metadata['include_weather'] == true,
      );
      return;
    }

    final note = await db.getQuoteById(artifact.noteId!);
    if (note == null ||
        ProposeNoteEditTool.revisionForQuote(note) != artifact.baseRevision) {
      _showRichEditConflict();
      return;
    }
    final proposed = _quoteFromArtifact(note, artifact);
    final tags = await db.getCategories();
    if (!mounted) return;
    if (artifact.resultKind == NoteDocumentKind.rich) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NoteFullEditorPage(
            initialContent: proposed.content,
            initialQuote: proposed,
            allTags: tags,
            skipDefaultMetadataAutofill: true,
          ),
        ),
      );
    } else {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => AddNoteDialog(
          initialQuote: proposed,
          tags: tags,
          onSave: db.updateQuote,
        ),
      );
    }
  }

  Future<String?> _applyNoteProposal(NoteProposalArtifact artifact) async {
    if (artifact.action == NoteProposalAction.create) {
      final validatedOps = _validatedArtifactOps(artifact);
      return _saveSmartResultAsNewNote(
        {
          ...artifact.metadata,
          'document_kind': artifact.resultKind.name,
          if (validatedOps != null) 'rich_document': validatedOps,
        },
        artifact.content,
      );
    }
    final db = context.read<DatabaseService>();
    final note = await db.getQuoteById(artifact.noteId!);
    if (note == null ||
        ProposeNoteEditTool.revisionForQuote(note) != artifact.baseRevision) {
      _showRichEditConflict();
      return null;
    }
    final result = await db.updateQuote(_quoteFromArtifact(note, artifact));
    if (result != QuoteUpdateResult.updated) {
      _showRichEditConflict();
      return null;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).saveSuccess)),
      );
    }
    return artifact.noteId;
  }

  Quote _quoteFromArtifact(Quote original, NoteProposalArtifact artifact) {
    var tagIds = original.tagIds;
    String? author = original.sourceAuthor;
    String? source = original.sourceWork;
    final tagPatch = artifact.metadata['tag_ids'];
    final authorPatch = artifact.metadata['author'];
    final sourcePatch = artifact.metadata['source'];
    if (tagPatch is Map) {
      tagIds = tagPatch['action'] == 'clear'
          ? const []
          : _extractStringList(tagPatch['value']);
    }
    if (authorPatch is Map) {
      author = authorPatch['action'] == 'clear'
          ? null
          : authorPatch['value']?.toString();
    }
    if (sourcePatch is Map) {
      source = sourcePatch['action'] == 'clear'
          ? null
          : sourcePatch['value']?.toString();
    }
    final rich = artifact.resultKind == NoteDocumentKind.rich;
    final documentOps = _validatedArtifactOps(artifact, original: original);
    return original.copyWith(
      content: artifact.content,
      source: authorPatch is Map || sourcePatch is Map ? null : original.source,
      deltaContent: rich ? jsonEncode(documentOps) : null,
      editSource: rich ? 'fullscreen' : null,
      tagIds: tagIds,
      sourceAuthor: author,
      sourceWork: source,
      lastModified: DateTime.now().toIso8601String(),
    );
  }

  List<Map<String, dynamic>>? _validatedArtifactOps(
    NoteProposalArtifact artifact, {
    Quote? original,
  }) {
    if (artifact.resultKind == NoteDocumentKind.plain) {
      if (artifact.documentOps != null) {
        throw const FormatException('plain proposal contains delta');
      }
      return null;
    }
    final ops = AgentNoteDocumentCodec.validateAndNormalize(
      NoteDocumentKind.rich,
      artifact.documentOps,
      allowExistingEmbeds: original != null,
    );
    if (AgentNoteDocumentCodec.plainTextOf(ops) != artifact.content) {
      throw const FormatException('proposal content and delta differ');
    }
    if (original != null) {
      final originalEmbeds = ProposeNoteEditTool.opsForQuote(original)
          .where((op) => op['insert'] is! String)
          .map((op) => jsonEncode(op['insert']))
          .toSet();
      final hasNewEmbed = ops
          .where((op) => op['insert'] is! String)
          .map((op) => jsonEncode(op['insert']))
          .any((embed) => !originalEmbeds.contains(embed));
      if (hasNewEmbed) {
        throw const FormatException('proposal contains a new media reference');
      }
    }
    return ops;
  }

  Future<Map<String, dynamic>> _buildSmartResultMetaFromDraft(
    Map<String, dynamic> meta,
    SmartResultDraft draft,
  ) async {
    final updatedMeta = Map<String, dynamic>.from(meta);
    updatedMeta['author'] = draft.author;
    updatedMeta['source'] = draft.source;
    final previousTagNames = (meta['tag_names'] as List<dynamic>? ?? const [])
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
    final previousTagIds = (meta['tag_ids'] as List<dynamic>? ?? const [])
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
    updatedMeta['tag_names'] = draft.tagNames;
    updatedMeta['tag_ids'] =
        _sameStringList(previousTagNames, draft.tagNames) &&
                previousTagIds.isNotEmpty
            ? previousTagIds
            : await _resolveDraftTagIds(draft.tagNames);
    updatedMeta['include_location'] = draft.includeLocation;
    updatedMeta['include_weather'] = draft.includeWeather;
    return updatedMeta;
  }

  Future<List<String>> _resolveDraftTagIds(List<String> tagNames) async {
    if (tagNames.isEmpty) {
      return const <String>[];
    }
    final db = context.read<DatabaseService>();
    final noMatchingTags = AppLocalizations.of(context).noMatchingTags;
    final categories = await db.getCategories();
    final nameToId = <String, String>{
      for (final tag in categories)
        if (tag.id != DatabaseService.hiddenTagId) tag.name.trim(): tag.id,
    };
    final ids = <String>[];
    final unknownNames = <String>[];
    for (final name in tagNames) {
      final id = nameToId[name.trim()];
      if (id == null) {
        unknownNames.add(name);
        continue;
      }
      if (!ids.contains(id)) {
        ids.add(id);
      }
    }
    if (unknownNames.isNotEmpty) {
      throw Exception('$noMatchingTags: ${unknownNames.join(', ')}');
    }
    return ids;
  }

  bool _sameStringList(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  void _updateSmartResultSavedNoteId(String messageId, String noteId) {
    _setState(() {
      final index = _messages.indexWhere((message) => message.id == messageId);
      if (index == -1) return;
      final oldMessage = _messages[index];
      final rawMeta = oldMessage.metaJson;
      if (rawMeta == null) return;
      final meta = jsonDecode(rawMeta) as Map<String, dynamic>;
      meta['saved_note_id'] = noteId;
      final updatedMessage = oldMessage.copyWith(metaJson: jsonEncode(meta));
      _messages[index] = updatedMessage;
      if (_currentSessionId != null) {
        unawaited(
          _chatSessionService.addMessage(_currentSessionId!, updatedMessage),
        );
      }
    });
  }

  bool _isShortContent(String content) {
    return !AiSmartResultUtils.shouldOpenFullEditor(content);
  }

  AiSmartResultMetadata _resolveInitialNewNoteMetadata(
    Map<String, dynamic> meta,
  ) {
    final settings = context.read<SettingsService>();
    return AiSmartResultUtils.resolveNewNoteMetadata(
      aiAuthor: meta['author']?.toString(),
      aiSource: meta['source']?.toString(),
      aiTagIds: _extractStringList(meta['tag_ids']),
      defaultTagIds: settings.defaultTagIds,
      aiIncludeLocation: _readOptionalBool(meta, 'include_location'),
      aiIncludeWeather: _readOptionalBool(meta, 'include_weather'),
      userAutoAttachLocation: settings.autoAttachLocation,
      userAutoAttachWeather: settings.autoAttachWeather,
    );
  }

  AiSmartResultMetadata _resolveConfirmedNewNoteMetadata(
    Map<String, dynamic> meta, {
    required bool includeLocation,
    required bool includeWeather,
  }) {
    final settings = context.read<SettingsService>();
    return AiSmartResultMetadata(
      author: _trimToNull(meta['author']?.toString()),
      source: _trimToNull(meta['source']?.toString()),
      tagIds: AiSmartResultUtils.resolveNewNoteMetadata(
        aiAuthor: null,
        aiSource: null,
        aiTagIds: _extractStringList(meta['tag_ids']),
        defaultTagIds: settings.defaultTagIds,
        aiIncludeLocation: false,
        aiIncludeWeather: false,
        userAutoAttachLocation: false,
        userAutoAttachWeather: false,
      ).tagIds,
      includeLocation: includeLocation,
      includeWeather: includeWeather,
    );
  }

  List<String> _extractStringList(Object? value) {
    final rawItems = value is List ? value : const [];
    return rawItems
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String? _trimToNull(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  bool? _readOptionalBool(Map<String, dynamic> values, String key) {
    final value = values[key];
    return value is bool ? value : null;
  }

  Future<void> _openSmartResultAsNewNote(
    String content, {
    Object? richDocument,
    List<String>? tagIds,
    String? author,
    String? source,
    bool includeLocation = false,
    bool includeWeather = false,
  }) async {
    if (richDocument == null &&
        _isShortContent(content) &&
        !DeltaBuilder.hasMarkdownFormatting(content)) {
      final db = context.read<DatabaseService>();
      final tags = await db.getCategories();
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
        builder: (_) => AddNoteDialog(
          prefilledContent: content,
          prefilledTagIds: tagIds,
          prefilledAuthor: author,
          prefilledWork: source,
          prefilledIncludeLocation: includeLocation,
          prefilledIncludeWeather: includeWeather,
          useAIPrefilledLocationWeather: true,
          tags: tags,
          onSave: db.addQuote,
        ),
      );
      return;
    }

    final db = context.read<DatabaseService>();
    final locationService = context.read<LocationService>();
    final weatherService = context.read<WeatherService>();
    final l10n = AppLocalizations.of(context);
    final tags = await db.getCategories();

    // 预获取位置/天气数据，确保传入编辑器的 initialQuote 包含真实数据
    if (includeLocation) {
      if (!locationService.hasLocationPermission) {
        final granted = await locationService.requestLocationPermission();
        if (!granted) {
          if (mounted) {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(l10n.cannotGetLocationTitle),
                content: Text(l10n.cannotGetLocationPermissionShort),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(l10n.iKnow),
                  ),
                ],
              ),
            );
          }
        }
      }
      if (locationService.hasLocationPermission) {
        await locationService.getCurrentLocation();
      }
    }

    if (includeWeather) {
      final pos = locationService.currentPosition;
      if (pos != null) {
        try {
          await weatherService.getWeatherData(pos.latitude, pos.longitude);
        } catch (e) {
          logDebug('AI 打开编辑器获取天气失败: $e');
        }
      }
    }

    final position = locationService.currentPosition;

    // 始终创建 initialQuote，防止编辑器自动应用用户偏好设置
    var formattedLocation = locationService.getFormattedLocation();
    // 修复：如果 getFormattedLocation() 为空但 getDisplayLocation() 有值，
    // 使用显示格式的地址作为 fallback
    if (formattedLocation.isEmpty && includeLocation) {
      final displayLocation = locationService.getDisplayLocation();
      if (displayLocation.isNotEmpty) {
        formattedLocation = displayLocation;
      }
    }
    final structuredOps = _opsFromRichDocument(richDocument);
    final plainContent = structuredOps == null
        ? DeltaBuilder.markdownToPlainText(content)
        : QuillStructuredEdit.plainTextOf(structuredOps);
    final initialQuote = Quote(
      content: plainContent,
      date: DateTime.now().toIso8601String(),
      tagIds: tagIds ?? [],
      sourceAuthor: author,
      sourceWork: source,
      location: includeLocation
          ? (formattedLocation.isNotEmpty
              ? formattedLocation
              : (position != null ? LocationService.kAddressPending : null))
          : null,
      // 修复：只有勾选位置时才保存坐标，避免仅勾选天气时显示坐标
      latitude: includeLocation ? position?.latitude : null,
      longitude: includeLocation ? position?.longitude : null,
      weather: includeWeather ? weatherService.currentWeather : null,
      temperature: includeWeather ? weatherService.temperature : null,
      dayPeriod: TimeUtils.getCurrentDayPeriodKey(),
      editSource: 'fullscreen',
      deltaContent: DeltaBuilder.deltaToJson(
        structuredOps ?? DeltaBuilder.markdownToDelta(content),
      ),
    );

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteFullEditorPage(
          initialContent: plainContent,
          initialQuote: initialQuote,
          allTags: tags,
          skipDefaultMetadataAutofill: true,
        ),
      ),
    );
  }

  Future<String?> _saveSmartResultToExistingNote(
    Map<String, dynamic> meta,
    String content,
  ) async {
    final l10n = AppLocalizations.of(context);
    final modeAction =
        meta['action']?.toString() == 'append' ? 'append' : 'replace';
    final noteId = meta['note_id']?.toString() ??
        (_hasBoundNote ? widget.quote!.id : null);

    if (noteId != null && noteId.isNotEmpty) {
      try {
        final db = context.read<DatabaseService>();
        final locationService = context.read<LocationService>();
        final weatherService = context.read<WeatherService>();
        final existingNote = await db.getQuoteById(noteId);
        if (existingNote == null) {
          throw Exception('Note not found');
        }

        final richEditedNote = _applyStructuredEdit(existingNote, meta);
        final plainContent = DeltaBuilder.markdownToPlainText(content);
        final newContent = richEditedNote?.content ??
            (modeAction == 'append'
                ? '${existingNote.content}\n$plainContent'
                : plainContent);

        // 合并 Agent 建议的元数据（标签、作者、出处）
        final rawSuggestedTagIds = meta['tag_ids'] as List<dynamic>?;
        final suggestedTagIds = rawSuggestedTagIds
            ?.map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList();
        final suggestedAuthor = meta['author']?.toString();
        final suggestedSource = meta['source']?.toString();
        var includeLocation = meta['include_location'] == true;
        var includeWeather = meta['include_weather'] == true;
        var nextLocation = includeLocation ? existingNote.location : null;
        var nextLatitude = includeLocation ? existingNote.latitude : null;
        var nextLongitude = includeLocation ? existingNote.longitude : null;
        var nextPoiName = includeLocation ? existingNote.poiName : null;
        var nextWeather = includeWeather ? existingNote.weather : null;
        var nextTemperature = includeWeather ? existingNote.temperature : null;

        final needsLocation = includeLocation &&
            (LocationService.isNonDisplayMarker(nextLocation) &&
                (nextLatitude == null || nextLongitude == null));
        final needsWeather = includeWeather && nextWeather == null;
        if (needsLocation || needsWeather) {
          var hasPermission = locationService.hasLocationPermission;
          if (!hasPermission) {
            hasPermission = await locationService.requestLocationPermission();
          }

          if (hasPermission) {
            await locationService.getCurrentLocation();
            final position = locationService.currentPosition;
            if (needsLocation) {
              var formattedLocation = locationService.getFormattedLocation();
              if (formattedLocation.isEmpty) {
                formattedLocation = locationService.getDisplayLocation();
              }
              nextLocation = formattedLocation.isNotEmpty
                  ? formattedLocation
                  : (position != null ? LocationService.kAddressPending : null);
              nextLatitude = position?.latitude;
              nextLongitude = position?.longitude;
            }
            if (needsWeather && position != null) {
              try {
                await weatherService.getWeatherData(
                  position.latitude,
                  position.longitude,
                );
                nextWeather = weatherService.currentWeather;
                nextTemperature = weatherService.temperature;
              } catch (e) {
                logDebug('AI 更新现有笔记获取天气失败: $e');
              }
            }
          }

          if ((needsLocation && nextLocation == null) ||
              (needsWeather && nextWeather == null)) {
            includeLocation = includeLocation && nextLocation != null;
            includeWeather = includeWeather && nextWeather != null;
            if (mounted) {
              await showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(l10n.weatherFetchFailedTitle),
                  content: Text(l10n.locationAndWeatherUnavailable),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(l10n.iKnow),
                    ),
                  ],
                ),
              );
            }
          }
        }

        final String updatedDeltaContent;
        if (richEditedNote != null) {
          updatedDeltaContent = richEditedNote.deltaContent!;
        } else if (modeAction == 'append') {
          final updatedOps = DeltaBuilder.appendMarkdownToDelta(
            originalDeltaJson: existingNote.deltaContent,
            markdown: content,
          );
          updatedDeltaContent = DeltaBuilder.deltaToJson(updatedOps);
        } else {
          final updatedOps = DeltaBuilder.replaceMarkdownInDelta(
            originalDeltaJson: existingNote.deltaContent,
            markdown: content,
          );
          updatedDeltaContent = DeltaBuilder.deltaToJson(updatedOps);
        }

        final updatedNote = existingNote.copyWith(
          content: newContent,
          deltaContent: updatedDeltaContent,
          tagIds: suggestedTagIds ?? existingNote.tagIds,
          sourceAuthor: suggestedAuthor ?? existingNote.sourceAuthor,
          sourceWork: suggestedSource ?? existingNote.sourceWork,
          location: includeLocation ? nextLocation : null,
          latitude: includeLocation ? nextLatitude : null,
          longitude: includeLocation ? nextLongitude : null,
          poiName: includeLocation ? nextPoiName : null,
          weather: includeWeather ? nextWeather : null,
          temperature: includeWeather ? nextTemperature : null,
          lastModified: DateTime.now().toIso8601String(),
        );

        await db.updateQuote(updatedNote);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.saveSuccess)),
          );
        }
        return noteId;
      } on RichTextEditConflict catch (e, stack) {
        logError(
          '结构化编辑版本冲突',
          error: e,
          stackTrace: stack,
          source: 'AIAssistantPage',
        );
        _showRichEditConflict();
        return null;
      } on RichTextEditMatchFailure catch (e, stack) {
        logError(
          '结构化编辑目标不再匹配',
          error: e,
          stackTrace: stack,
          source: 'AIAssistantPage',
        );
        _showRichEditConflict();
        return null;
      } catch (e, stack) {
        logError(
          'AIAssistantPage._saveSmartResultToExistingNote 失败',
          error: e,
          stackTrace: stack,
          source: 'AIAssistantPage',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.saveFailed(e.toString()))),
          );
        }
        rethrow;
      }
    }

    return _saveSmartResultAsNewNote(meta, content);
  }

  Quote? _applyStructuredEdit(Quote note, Map<String, dynamic> meta) {
    final rawRequest = meta['rich_edit'];
    if (rawRequest is! Map) return null;
    final request = RichTextEditRequest.fromJson(
      rawRequest.map((key, value) => MapEntry(key.toString(), value)),
    );
    final result = QuillStructuredEdit.apply(
      originalOps: DeltaBuilder.deltaFromJson(note.deltaContent) ??
          [
            {
              'insert': note.content.endsWith('\n')
                  ? note.content
                  : '${note.content}\n',
            },
          ],
      request: request,
    );
    final plainContent = result.ops
        .map((op) => op['insert'])
        .whereType<String>()
        .join()
        .replaceFirst(RegExp(r'\n$'), '');
    return note.copyWith(
      content: plainContent,
      deltaContent: jsonEncode(result.ops),
    );
  }

  void _showRichEditConflict() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).agentRichEditConflict),
      ),
    );
  }

  List<Map<String, dynamic>>? _opsFromRichDocument(Object? rawBlocks) {
    if (rawBlocks is! List || rawBlocks.isEmpty) return null;
    if (rawBlocks.first is Map &&
        (rawBlocks.first as Map).containsKey('insert')) {
      return rawBlocks
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    }
    final blocks = rawBlocks
        .whereType<Map>()
        .map((item) => RichTextBlock.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ))
        .toList(growable: false);
    return blocks.isEmpty
        ? null
        : QuillStructuredEdit.documentFromBlocks(blocks);
  }

  Future<String?> _saveSmartResultAsNewNote(
    Map<String, dynamic> meta,
    String content,
  ) async {
    final l10n = AppLocalizations.of(context);

    try {
      final db = context.read<DatabaseService>();
      final locationService = context.read<LocationService>();
      final weatherService = context.read<WeatherService>();
      var includeLocation = meta['include_location'] == true;
      var includeWeather = meta['include_weather'] == true;
      final rawTagIds = meta['tag_ids'] as List<dynamic>? ?? const [];
      final tagIds = rawTagIds
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
      final author = meta['author']?.toString();
      final source = meta['source']?.toString();

      // 主动获取位置/天气数据（直接保存时必须触发获取，不能依赖缓存）
      if (includeLocation) {
        if (!locationService.hasLocationPermission) {
          final granted = await locationService.requestLocationPermission();
          if (!granted) {
            includeLocation = false;
            includeWeather = false;
            if (mounted) {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(l10n.cannotGetLocationTitle),
                  content: Text(l10n.cannotGetLocationPermissionShort),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(l10n.iKnow),
                    ),
                  ],
                ),
              );
            }
          }
        }
        if (includeLocation) {
          await locationService.getCurrentLocation();
        }
      }

      if (includeWeather) {
        final pos = locationService.currentPosition;
        if (pos != null) {
          try {
            await weatherService.getWeatherData(
              pos.latitude,
              pos.longitude,
            );
          } catch (e) {
            logDebug('AI 直接保存获取天气失败: $e');
            includeWeather = false;
          }
        } else {
          includeWeather = false;
          if (mounted) {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(l10n.weatherFetchFailedTitle),
                content: Text(l10n.locationAndWeatherUnavailable),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(l10n.iKnow),
                  ),
                ],
              ),
            );
          }
        }
      }

      final position = locationService.currentPosition;
      var formattedLocation = locationService.getFormattedLocation();
      // 修复：如果 getFormattedLocation() 为空但 getDisplayLocation() 有值，
      // 使用显示格式的地址作为 fallback，确保预览能显示的位置也能正确保存
      if (formattedLocation.isEmpty && includeLocation) {
        final displayLocation = locationService.getDisplayLocation();
        if (displayLocation.isNotEmpty) {
          formattedLocation = displayLocation;
        }
      }
      final storedLocation = includeLocation
          ? (formattedLocation.isNotEmpty
              ? formattedLocation
              : (position != null ? LocationService.kAddressPending : null))
          : null;

      final noteId = _uuid.v4();
      final structuredOps = _opsFromRichDocument(meta['rich_document']);
      final isRich = meta['document_kind'] == 'rich' || structuredOps != null;
      final plainContent =
          !isRich ? content : QuillStructuredEdit.plainTextOf(structuredOps!);
      final quote = Quote.validated(
        id: noteId,
        content: plainContent,
        date: DateTime.now().toIso8601String(),
        tagIds: tagIds,
        sourceAuthor: author,
        sourceWork: source,
        location: storedLocation,
        // 只有勾选位置时才保存坐标，避免仅勾选天气时显示坐标
        latitude: includeLocation ? position?.latitude : null,
        longitude: includeLocation ? position?.longitude : null,
        weather: includeWeather ? weatherService.currentWeather : null,
        temperature: includeWeather ? weatherService.temperature : null,
        dayPeriod: TimeUtils.getCurrentDayPeriodKey(),
        editSource: isRich ? 'fullscreen' : null,
        deltaContent: isRich ? DeltaBuilder.deltaToJson(structuredOps!) : null,
      );

      await db.addQuote(quote);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.saveSuccess)),
        );
      }
      return noteId;
    } catch (e, stack) {
      logError(
        'AIAssistantPage._saveSmartResultAsNewNote 失败',
        error: e,
        stackTrace: stack,
        source: 'AIAssistantPage',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.saveFailed(e.toString()))),
        );
      }
      rethrow;
    }
  }
}
