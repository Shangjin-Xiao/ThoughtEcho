part of '../ai_assistant_page.dart';

extension _AIAssistantPageUI on _AIAssistantPageState {
  void _onTextChanged() {
    final text = _textController.text.trimLeft();
    final shouldShow = text.startsWith('/');
    if (shouldShow != _showSlashCommands) {
      _setState(() {
        _showSlashCommands = shouldShow;
      });
    }
  }

  void _onInputFocusChanged() {
    if (!mounted || _isInputFocused == _inputFocusNode.hasFocus) {
      return;
    }
    _setState(() {
      _isInputFocused = _inputFocusNode.hasFocus;
    });
  }

  /// 选择并附加媒体文件
  Future<void> _pickAndAttachMedia() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
        onFileLoading: (FilePickerStatus status) {
          // Optional: Handle loading state
        },
      );

      if (result != null && result.files.isNotEmpty) {
        _setState(() {
          _selectedMediaFiles.addAll(result.files);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick files: $e')),
      );
    }
  }

  /// 移除已选择的媒体文件
  void _removeMediaFile(int index) {
    _setState(() {
      _selectedMediaFiles.removeAt(index);
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
            child: NotificationListener<ScrollUpdateNotification>(
              onNotification: (notification) {
                if (notification.dragDetails != null && notification.scrollDelta != null) {
                  if (_inputFocusNode.hasFocus) {
                    _inputFocusNode.unfocus();
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
          case 'smart_result':
            final action = meta['action']?.toString();
            final isNewNoteProposal = action == 'create';
            final noteId = meta['note_id']?.toString().trim() ?? '';
            final canApplyToExistingNote =
                !isNewNoteProposal && (_hasBoundNote || noteId.isNotEmpty);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SmartResultCard(
                key: const ValueKey('ai_workflow_result_smart_result'),
                title: meta['title'] as String? ?? l10n.analysisResult,
                content: message.content,
                replaceButtonText: meta['replaceButtonText'] as String? ??
                    (canApplyToExistingNote
                        ? l10n.replaceOriginalNote
                        : l10n.applyChanges),
                appendButtonText: meta['appendButtonText'] as String? ??
                    (canApplyToExistingNote
                        ? l10n.appendToEnd
                        : l10n.appendToNote),
                editorSource: isNewNoteProposal ? 'new_note' : 'fullscreen',
                initialIncludeLocation: meta['include_location'] == true,
                initialIncludeWeather: meta['include_weather'] == true,
                onReplace: canApplyToExistingNote
                    ? () async {
                        final updatedMeta = Map<String, dynamic>.from(meta);
                        updatedMeta['action'] = 'replace';
                        await _openSmartResultInEditor(
                          updatedMeta,
                          message.content,
                        );
                      }
                    : null,
                onAppend: canApplyToExistingNote
                    ? () async {
                        final updatedMeta = Map<String, dynamic>.from(meta);
                        updatedMeta['action'] = 'append';
                        await _openSmartResultInEditor(
                          updatedMeta,
                          message.content,
                        );
                      }
                    : null,
                onOpenInEditor: (includeLocation, includeWeather) async {
                  if (isNewNoteProposal) {
                    final rawTagIds =
                        meta['tag_ids'] as List<dynamic>? ?? const [];
                    final tagIds = rawTagIds
                        .map((item) => item.toString().trim())
                        .where((item) => item.isNotEmpty)
                        .toList();
                    await _openSmartResultAsNewNote(
                      message.content,
                      tagIds: tagIds,
                      includeLocation: includeLocation,
                      includeWeather: includeWeather,
                    );
                  } else {
                    final updatedMeta = Map<String, dynamic>.from(meta);
                    await _openSmartResultInEditor(
                      updatedMeta,
                      message.content,
                    );
                  }
                },
                onSaveDirectly: (includeLocation, includeWeather) async {
                  if (isNewNoteProposal) {
                    final updatedMeta = Map<String, dynamic>.from(meta);
                    updatedMeta['include_location'] = includeLocation;
                    updatedMeta['include_weather'] = includeWeather;
                    await _saveSmartResultAsNewNote(
                      updatedMeta,
                      message.content,
                    );
                  } else {
                    final updatedMeta = Map<String, dynamic>.from(meta);
                    await _saveSmartResultToExistingNote(
                      updatedMeta,
                      message.content,
                    );
                  }
                },
              ),
            );
          case 'notice':
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
      } catch (e) {
        AppLogger.e('Failed to render AI workflow message', error: e);
      }
    }

    final isUser = message.isUser;

    // Material 3 semantic colors
    final userBubbleColor = theme.colorScheme.primary;
    final agentBubbleColor = theme.colorScheme.surfaceContainerHigh;
    final bubbleColor = isUser ? userBubbleColor : agentBubbleColor;

    final bubbleTextColor = isUser ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;

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
          if (!isUser &&
              message.thinkingChunks.isNotEmpty &&
              message.thinkingChunks.join('').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ThinkingWidget(
                key: ValueKey('thinking_${message.id}'),
                thinkingText: message.thinkingChunks.join(''),
                inProgress: message.state == MessageState.thinking,
                accentColor: theme.colorScheme.primary,
              ),
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
                    styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                      p: theme.textTheme.bodyMedium?.copyWith(
                        color: bubbleTextColor,
                        height: 1.6,
                      ),
                      listBullet: theme.textTheme.bodyMedium?.copyWith(
                        color: bubbleTextColor,
                      ),
                      code: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFamily: 'monospace',
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
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
    final workflowDescriptors = _buildWorkflowDescriptors(l10n);
    final inputText = _textController.text.toLowerCase();
    final filteredWorkflowDescriptors = workflowDescriptors
        .where(
          (descriptor) =>
              inputText.isEmpty ||
              descriptor.command.toLowerCase().startsWith(inputText),
        )
        .toList(growable: false);
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
            // Slash commands
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child:
                  _showSlashCommands && filteredWorkflowDescriptors.isNotEmpty
                      ? Padding(
                          key: const ValueKey('slash_commands_visible'),
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children:
                                  filteredWorkflowDescriptors.map((descriptor) {
                                return ActionChip(
                                  label: Text(descriptor.command),
                                  onPressed: () {
                                    _textController.clear();
                                    _handleSubmitted(descriptor.command);
                                  },
                                );
                              }).toList(),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(
                          key: ValueKey('slash_commands_hidden'),
                        ),
            ),
            // Selected media files
            if (_selectedMediaFiles.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: SizedBox(
                  height: 64,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _selectedMediaFiles.length,
                    itemBuilder: (context, index) {
                      final file = _selectedMediaFiles[index];
                      final isImage = ['jpg', 'jpeg', 'png', 'webp', 'gif']
                          .contains(file.extension?.toLowerCase());
                      
                      return Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Stack(
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant,
                                  width: 1,
                                ),
                              ),
                              child: isImage && file.path != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(11),
                                      child: Image.file(
                                        File(file.path!),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Icon(
                                          Icons.image_not_supported_outlined,
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    )
                                  : Icon(
                                      Icons.insert_drive_file_outlined,
                                      color: theme.colorScheme.onSurfaceVariant,
                                      size: 28,
                                    ),
                            ),
                            Positioned(
                              top: -4,
                              right: -4,
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => _removeMediaFile(index),
                                  customBorder: const CircleBorder(),
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.inverseSurface,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.close,
                                      size: 14,
                                      color: theme.colorScheme.onInverseSurface,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
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
            // Action row: + | mode toggle | thinking | send
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
              child: Row(
                children: [
                  // Add media
                  IconButton(
                    icon: const Icon(Icons.add, size: 20),
                    onPressed: _isLoading ? null : _pickAndAttachMedia,
                    style: IconButton.styleFrom(
                      padding: const EdgeInsets.all(8),
                      minimumSize: const Size(36, 36),
                    ),
                  ),
                  // Mode toggle (direct tap)
                  if (_entryConfig.allowsMode(AIAssistantPageMode.agent))
                    GestureDetector(
                      onTap: _isLoading
                          ? null
                          : () {
                              final next = _isAgentMode
                                  ? _entryConfig.defaultMode
                                  : AIAssistantPageMode.agent;
                              _setMode(next);
                            },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _isAgentMode
                              ? theme.colorScheme.primaryContainer
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isAgentMode
                                  ? Icons.smart_toy
                                  : Icons.chat_outlined,
                              size: 16,
                              color: _isAgentMode
                                  ? theme.colorScheme.onPrimaryContainer
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _isAgentMode ? l10n.aiModeAgent : l10n.aiModeChat,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: _isAgentMode
                                    ? theme.colorScheme.onPrimaryContainer
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Thinking toggle
                  if (_currentModelSupportsThinking)
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
    final noteId = meta['note_id']?.toString();

    if (_hasBoundNote) {
      Navigator.pop(context, {
        'action': 'edit',
        'mode': modeAction,
        'text': content,
      });
      return;
    }

    if (noteId != null && noteId.isNotEmpty) {
      final db = context.read<DatabaseService>();
      final note = await db.getQuoteById(noteId);
      if (!mounted) {
        return;
      }
      if (note != null) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NoteFullEditorPage(
              initialContent: content,
              initialQuote: note,
            ),
          ),
        );
        return;
      }
    }

    await _openSmartResultAsNewNote(content);
  }

  bool _isShortContent(String content) {
    return content.length < 200 && '\n'.allMatches(content).length <= 2;
  }

  Future<void> _openSmartResultAsNewNote(
    String content, {
    List<String>? tagIds,
    bool includeLocation = false,
    bool includeWeather = false,
  }) async {
    if (_isShortContent(content)) {
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
          prefilledIncludeLocation: includeLocation,
          prefilledIncludeWeather: includeWeather,
          tags: tags,
          onSave: (_) {},
        ),
      );
      return;
    }

    final locationService = context.read<LocationService>();
    final weatherService = context.read<WeatherService>();
    final position = locationService.currentPosition;

    Quote? initialQuote;
    if (tagIds != null || includeLocation || includeWeather) {
      final formattedLocation = locationService.getFormattedLocation();
      initialQuote = Quote(
        content: content,
        date: DateTime.now().toIso8601String(),
        tagIds: tagIds ?? [],
        location: includeLocation
            ? (formattedLocation.isNotEmpty
                ? formattedLocation
                : (position != null ? LocationService.kAddressPending : null))
            : null,
        latitude:
            (includeLocation || includeWeather) ? position?.latitude : null,
        longitude:
            (includeLocation || includeWeather) ? position?.longitude : null,
        weather: includeWeather ? weatherService.currentWeather : null,
        temperature: includeWeather ? weatherService.temperature : null,
        dayPeriod: TimeUtils.getCurrentDayPeriodKey(),
      );
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteFullEditorPage(
          initialContent: content,
          initialQuote: initialQuote,
        ),
      ),
    );
  }

  Future<void> _saveSmartResultToExistingNote(
    Map<String, dynamic> meta,
    String content,
  ) async {
    final l10n = AppLocalizations.of(context);
    final modeAction =
        meta['action']?.toString() == 'append' ? 'append' : 'replace';
    final noteId = meta['note_id']?.toString();

    if (_hasBoundNote) {
      Navigator.pop(context, {
        'action': 'save',
        'mode': modeAction,
        'text': content,
      });
      return;
    }

    if (noteId != null && noteId.isNotEmpty) {
      try {
        final db = context.read<DatabaseService>();
        final existingNote = await db.getQuoteById(noteId);
        if (existingNote == null) {
          throw Exception('Note not found');
        }

        final newContent = modeAction == 'append'
            ? '${existingNote.content}\n$content'
            : content;

        final updatedNote = existingNote.copyWith(
          content: newContent,
          deltaContent: existingNote.deltaContent,
          lastModified: DateTime.now().toIso8601String(),
        );

        await db.updateQuote(updatedNote);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.saveSuccess)),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.saveFailed(e.toString()))),
          );
        }
      }
      return;
    }

    await _saveSmartResultAsNewNote(meta, content);
  }

  Future<void> _saveSmartResultAsNewNote(
    Map<String, dynamic> meta,
    String content,
  ) async {
    final l10n = AppLocalizations.of(context);

    try {
      final db = context.read<DatabaseService>();
      final locationService = context.read<LocationService>();
      final weatherService = context.read<WeatherService>();
      final includeLocation = meta['include_location'] == true;
      final includeWeather = meta['include_weather'] == true;
      final rawTagIds = meta['tag_ids'] as List<dynamic>? ?? const [];
      final tagIds = rawTagIds
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();

      final position = locationService.currentPosition;
      final formattedLocation = locationService.getFormattedLocation();
      final storedLocation = includeLocation
          ? (formattedLocation.isNotEmpty
              ? formattedLocation
              : (position != null ? LocationService.kAddressPending : null))
          : null;

      final quote = Quote.validated(
        content: content,
        date: DateTime.now().toIso8601String(),
        tagIds: tagIds,
        location: storedLocation,
        latitude:
            (includeLocation || includeWeather) ? position?.latitude : null,
        longitude:
            (includeLocation || includeWeather) ? position?.longitude : null,
        weather: includeWeather ? weatherService.currentWeather : null,
        temperature: includeWeather ? weatherService.temperature : null,
        dayPeriod: TimeUtils.getCurrentDayPeriodKey(),
      );

      await db.addQuote(quote);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.saveSuccess)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.saveFailed(e.toString()))),
        );
      }
    }
  }
}
