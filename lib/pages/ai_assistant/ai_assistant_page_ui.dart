part of '../ai_assistant_page.dart';

extension _AIAssistantPageUI on _AIAssistantPageState {
  void _onInputFocusChanged() {
    if (!mounted || _isInputFocused == _inputFocusNode.hasFocus) {
      return;
    }
    final gainedFocus = _inputFocusNode.hasFocus;
    _setState(() {
      _isInputFocused = gainedFocus;
    });
    // 键盘弹出后 Scaffold 会 resize，需要等布局完成再滚动到底部，
    // 否则已有消息会被键盘 + 输入框遮挡。
    if (gainedFocus) {
      // 延迟一帧让键盘 resize 生效后再滚动
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToBottom(force: true);
      });
    }
  }

  Widget _buildPage(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                // 编辑器的所有 AI 功能都汇入 Thoughter，标题不再按入口分叉
                l10n.aiAssistantLabel,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            const ExperimentalBadge(compact: true),
          ],
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
                      final message = _messages[index];
                      final keepAlive = _shouldKeepAliveMessage(message);
                      return _KeepAliveMessageItem(
                        key: ValueKey('msg_keepalive_${message.id}'),
                        keepAlive: keepAlive,
                        child: _buildMessageBubble(message, theme, l10n),
                      );
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

  Widget _buildMessageBubble(
    app_chat.ChatMessage message,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    final meta = message.parsedMeta;
    if (meta != null) {
      try {
        switch (meta['type']) {
          case NoteProposalArtifact.typeName:
            final rawArtifact = meta['artifact'];
            if (rawArtifact is! Map) return const SizedBox.shrink();
            final artifact = NoteProposalArtifact.fromJson(
              rawArtifact.map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            );
            final proposalLocation =
                context.read<LocationService>().getDisplayLocation();
            final proposalWeatherService = context.read<WeatherService>();
            final proposalWeatherKey = proposalWeatherService.currentWeather;
            final proposalTemperature = proposalWeatherService.temperature;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: NoteProposalCard(
                key: ValueKey('ai_workflow_result_note_proposal_${message.id}'),
                artifact: artifact,
                locationPreview:
                    proposalLocation.isNotEmpty ? proposalLocation : null,
                weatherPreview: proposalWeatherKey != null
                    ? '${WeatherCodeMapper.getLocalizedDescription(l10n, proposalWeatherKey)}${proposalTemperature != null ? ' $proposalTemperature' : ''}'
                    : null,
                onMetadataChanged: (includeLocation, includeWeather) =>
                    _persistNoteProposalMetadataFlags(
                  message.id,
                  meta,
                  includeLocation: includeLocation,
                  includeWeather: includeWeather,
                ),
                plainCreateOpensRich:
                    artifact.action == NoteProposalAction.create &&
                        (artifact.resultKind == NoteDocumentKind.plain ||
                            !_opsHaveRichFormatting(artifact.documentOps)) &&
                        context.read<SettingsService>().skipNonFullscreenEditor,
                initialCompleted: meta['saved_note_id'] != null,
                initialSavedNoteId: meta['saved_note_id']?.toString(),
                tags: _resolveProposalDisplayTags(artifact),
                onQuickEdit: artifact.readOnly
                    ? null
                    : (current) => _handleNoteProposalQuickEdit(
                          message.id,
                          meta,
                          artifact,
                          current,
                        ),
                onViewNote: _viewSavedNote,
                onOpenInEditor: () async {
                  final noteId = await _openNoteProposalInEditor(artifact);
                  if (noteId != null && noteId.isNotEmpty) {
                    _updateSmartResultSavedNoteId(message.id, noteId);
                  }
                },
                onApply: () async {
                  final noteId = await _applyNoteProposal(artifact);
                  if (noteId != null) {
                    _updateSmartResultSavedNoteId(message.id, noteId);
                  }
                  return noteId;
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
                    onTapLink: (text, href, title) async {
                      if (href == null || href.isEmpty) return;
                      try {
                        final uri = Uri.tryParse(href);
                        if (uri != null && await canLaunchUrl(uri)) {
                          await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        }
                      } catch (_) {}
                    },
                  ),
          ),
          // 出错时保留正文并显式标记，避免内容被静默删除
          if (!isUser && message.state == MessageState.error)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 14,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    l10n.agentErrorGeneric,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
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
                      tooltip: _enableThinking
                          ? l10n.hideThinking
                          : l10n.showThinking,
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
                    tooltip: _isLoading ? l10n.stopGenerate : l10n.send,
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

  Future<String?> _openNoteProposalInEditor(
    NoteProposalArtifact artifact,
  ) async {
    final db = context.read<DatabaseService>();
    if (artifact.action == NoteProposalAction.create) {
      final validatedOps = _validatedArtifactOps(artifact);
      // 按内容实际形态而不是模型声明的 kind 选编辑器：声明 rich 但
      // ops 里没有任何格式时也是普通笔记，应走快速编辑弹窗。
      final effectivelyPlain = artifact.resultKind == NoteDocumentKind.plain ||
          !_opsHaveRichFormatting(validatedOps);
      if (effectivelyPlain &&
          !context.read<SettingsService>().skipNonFullscreenEditor) {
        final tags = await db.getCategories();
        if (!mounted) return null;
        String? savedId;
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
            onSave: (quote) async {
              await db.addQuote(quote);
              savedId = quote.id;
            },
          ),
        );
        return savedId;
      }
      final richOps = validatedOps ??
          [
            {'insert': '${artifact.content}\n'}
          ];
      return _openSmartResultAsNewNote(
        artifact.content,
        richDocument: richOps,
        tagIds: _extractStringList(artifact.metadata['tag_ids']),
        author: artifact.metadata['author']?.toString(),
        source: artifact.metadata['source']?.toString(),
        includeLocation: artifact.metadata['include_location'] == true,
        includeWeather: artifact.metadata['include_weather'] == true,
      );
    }

    final note = await db.getQuoteById(artifact.noteId!);
    if (note == null ||
        ProposeNoteEditTool.revisionForQuote(note) != artifact.baseRevision) {
      _showRichEditConflict();
      return null;
    }
    final proposed = _quoteFromArtifact(note, artifact);
    final tags = await db.getCategories();
    if (!mounted) return null;
    String? savedId;
    if (artifact.resultKind == NoteDocumentKind.rich) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NoteFullEditorPage(
            initialContent: proposed.content,
            initialQuote: proposed,
            allTags: tags,
            skipDefaultMetadataAutofill: true,
            onSaved: (savedQuote) => savedId = savedQuote.id,
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
          onSave: (quote) async {
            await db.updateQuote(quote);
            savedId = quote.id;
          },
        ),
      );
    }
    return savedId;
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
      lastModified: DateTime.now().toUtc().toIso8601String(),
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
      if (!AgentNoteDocumentCodec.hasSameEmbeds(
        ProposeNoteEditTool.opsForQuote(original),
        ops,
      )) {
        throw const FormatException('proposal changes media references');
      }
    }
    return ops;
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
      meta['applied'] = true;
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

  List<String> _extractStringList(Object? value) {
    final rawItems = value is List ? value : const [];
    return rawItems
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  /// 以新建笔记方式打开编辑器，返回保存成功的笔记 ID（未保存则为 null）。
  Future<String?> _openSmartResultAsNewNote(
    String content, {
    Object? richDocument,
    List<String>? tagIds,
    String? author,
    String? source,
    bool includeLocation = false,
    bool includeWeather = false,
  }) async {
    // 没有真实格式的 delta 等同于纯文本，不应该被当成富文本强推全屏编辑器
    if (richDocument != null &&
        !_opsHaveRichFormatting(_opsFromRichDocument(richDocument))) {
      richDocument = null;
    }
    if (richDocument == null &&
        _isShortContent(content) &&
        !DeltaBuilder.hasMarkdownFormatting(content)) {
      final db = context.read<DatabaseService>();
      final tags = await db.getCategories();
      if (!mounted) return null;
      String? savedNoteId;
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
          onSave: (quote) {
            savedNoteId = quote.id;
            return db.addQuote(quote);
          },
        ),
      );
      return savedNoteId;
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

    if (!mounted) return null;
    String? savedNoteId;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteFullEditorPage(
          initialContent: plainContent,
          initialQuote: initialQuote,
          allTags: tags,
          skipDefaultMetadataAutofill: true,
          onSaved: (savedQuote) => savedNoteId = savedQuote.id,
        ),
      ),
    );
    return savedNoteId;
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

  /// ops 里是否含真正的富文本格式。全部是无属性的纯文本 insert 时返回 false，
  /// 这类"名义 rich、实则纯文本"的内容应按普通笔记走快速编辑弹窗。
  bool _opsHaveRichFormatting(List<Map<String, dynamic>>? ops) {
    if (ops == null || ops.isEmpty) return false;
    for (final op in ops) {
      // 非字符串 insert 表示图片等嵌入对象，必须走全屏编辑器
      if (op['insert'] is! String) return true;
      final attributes = op['attributes'];
      if (attributes is Map && attributes.isNotEmpty) return true;
    }
    return false;
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

  /// 判断消息是否包含交互式卡片（需要保留离屏 Widget 状态）
  bool _shouldKeepAliveMessage(app_chat.ChatMessage message) {
    final meta = message.parsedMeta;
    if (meta == null) return false;
    final type = meta['type']?.toString();
    return type == NoteProposalArtifact.typeName;
  }
}

class _KeepAliveMessageItem extends StatefulWidget {
  final Widget child;
  final bool keepAlive;

  const _KeepAliveMessageItem({
    super.key,
    required this.child,
    this.keepAlive = false,
  });

  @override
  State<_KeepAliveMessageItem> createState() => _KeepAliveMessageItemState();
}

class _KeepAliveMessageItemState extends State<_KeepAliveMessageItem>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.keepAlive;

  @override
  void didUpdateWidget(covariant _KeepAliveMessageItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keepAlive != widget.keepAlive) {
      updateKeepAlive();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
