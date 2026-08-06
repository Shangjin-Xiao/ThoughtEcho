part of '../thoughter_page.dart';

/// 用户气泡最宽占可用宽度的比例。留出左侧空白，让"谁在说话"靠位置而不是
/// 靠标签来表达。
const double _kUserBubbleWidthFactor = 0.78;

/// 流式生成时接在正文末尾的光标。用字符而不是独立 widget，是为了让它跟着
/// markdown 的排版落在最后一个字后面，而不是另起一行。
const String _kStreamingCursor = '▌';

extension _ThoughterUI on _ThoughterPageState {
  /// 消息区可用高度变小（键盘上推、输入框变多行）时跟着贴底，
  /// 保证最后一条消息不会被顶出可视区。
  /// 注意不能监听 MediaQuery 的 viewInsets：Scaffold 已经把键盘 inset
  /// 消费掉了，body 子树里读到的恒为 0，只有布局高度反映真实变化。
  void _onMessageViewportHeightChanged(double height) {
    if (height == _lastMessageViewportHeight) return;
    final shrinking = height < _lastMessageViewportHeight;
    _lastMessageViewportHeight = height;
    if (!shrinking || !_autoScrollEnabled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (position.pixels < position.maxScrollExtent) {
        _scrollController.jumpTo(position.maxScrollExtent);
      }
    });
  }

  /// 弹浮层（抽屉 / 编辑器 / 历史页）前先丢掉输入焦点。
  ///
  /// 不丢的话：浮层拿走焦点、键盘收起，浮层关掉时 Flutter 把焦点还给输入框，
  /// 键盘二次弹出，输入框在底部窜一下。
  void _dropInputFocus() {
    if (_inputFocusNode.hasFocus) {
      _inputFocusNode.unfocus();
    }
  }

  /// 实体键盘上的回车：Enter 发送，Shift+Enter 换行——键盘用户的肌肉记忆。
  ///
  /// 只在桌面生效。手机上按下软键盘的回车走的是 textInputAction（已设成换行），
  /// 不产生按键事件；但个别输入法会补一个 Enter 键码，桌面之外一律不接，
  /// 免得刚改成换行的回车又变回发送。
  KeyEventResult _handleComposerKey(FocusNode node, KeyEvent event) {
    const desktop = {
      TargetPlatform.linux,
      TargetPlatform.macOS,
      TargetPlatform.windows,
    };
    if (!desktop.contains(defaultTargetPlatform)) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) return KeyEventResult.ignored;
    final text = _textController.text;
    if (_isLoading || text.trim().isEmpty) return KeyEventResult.ignored;
    unawaited(_handleSubmitted(text));
    return KeyEventResult.handled;
  }

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

  /// 列表末尾要不要补一个等待光标。
  ///
  /// 流式消息要收到第一个 token 才建出来，在那之前（刚发出提问、正在调工具）
  /// 对话流末尾什么都没有，看着像没反应。正文已经在流的时候不补：那种情况下
  /// 光标接在最后一个字后面，补一个会出现两个。
  bool get _showWaitingCursor {
    if (!_isLoading) return false;
    final last = _messages.isEmpty ? null : _messages.last;
    if (last == null) return true;
    if (!last.isUser && last.parsedMeta == null && last.isLoading) return false;
    return true;
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
          if (_entrySource == ThoughterEntrySource.explore &&
              widget.exploreGuideSummary?.trim().isNotEmpty == true)
            _buildExploreGuideBanner(theme, l10n),
          Expanded(
            // 键盘弹出是一段动画，消息区高度逐帧变矮。只在获得焦点那一帧滚一次
            // 会停在"当时"的底部，键盘继续上推后消息又被盖住，所以整段动画
            // 期间每次布局都重新贴底。
            child: LayoutBuilder(
              builder: (context, constraints) {
                _onMessageViewportHeightChanged(constraints.maxHeight);
                return Stack(
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
                        // 水平留白下放给每条消息自己——AI 回复要铺满可读宽度，
                        // 用户气泡要贴右边缘，两者的左右边距不一样。
                        padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                        itemCount:
                            _messages.length + (_showWaitingCursor ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= _messages.length) {
                            return Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 10, 16, 14),
                              child: _BlinkingCursor(
                                key: const ValueKey('ai_assistant_waiting'),
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            );
                          }
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
                                icon:
                                    const Icon(Icons.arrow_downward, size: 18),
                                visualDensity: VisualDensity.compact,
                                tooltip: l10n.scrollToBottom,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: NoteProposalCard(
                key: ValueKey('ai_workflow_result_note_proposal_${message.id}'),
                artifact: artifact,
                locationPreview:
                    proposalLocation.isNotEmpty ? proposalLocation : null,
                weatherPreview: proposalWeatherKey != null
                    ? '${WeatherCodeMapper.getLocalizedDescription(l10n, proposalWeatherKey)}${proposalTemperature != null ? ' $proposalTemperature' : ''}'
                    : null,
                onResolveLocation: _resolveProposalLocation,
                onResolveWeather: _resolveProposalWeather,
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: AIWorkflowNoticeCard(
                title: meta['title'] as String? ?? l10n.notice,
                message: message.content,
                icon: Icons.info_outline,
              ),
            );
          case 'source_analysis_result':
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: ToolProgressPanel(
                title: l10n.toolExecutionProgress,
                items: progressItems,
                inProgress: inProgress,
                accentColor: theme.colorScheme.primary,
                thinkingText: meta['thinkingText'] as String?,
              ),
            );
        }
      } catch (e, stack) {
        logError(
          'Failed to render AI workflow message',
          error: e,
          stackTrace: stack,
          source: 'thoughter_ui',
        );
      }
    }

    if (message.isUser) {
      return _buildUserMessage(message, theme);
    }
    if (_isOpeningMessage(message)) {
      return _buildOpeningMessage(message, theme);
    }
    return _buildAgentMessage(message, theme, l10n);
  }

  /// 会话的第一句话——每日提示、探索洞察、笔记欢迎语。
  ///
  /// 它是被调用方塞进来的引子，不是模型对着用户说的一轮回答，所以既不该带
  /// 复制/重试（重试无从谈起：它前面没有提问），也不该长得和 AI 回复一样。
  bool _isOpeningMessage(app_chat.ChatMessage message) {
    if (_messages.isEmpty) return false;
    final first = _messages.first;
    return !first.isUser && first.id == message.id;
  }

  /// 开场白：左侧一条细竖线的引言块，正文弱一档，不带任何操作。
  Widget _buildOpeningMessage(app_chat.ChatMessage message, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 2,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            Expanded(
              child: MarkdownBody(
                data: message.content,
                selectable: true,
                styleSheet: _getMarkdownStyleSheet(
                  theme,
                  theme.colorScheme.onSurface,
                ).copyWith(
                  p: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.6,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 用户消息：右对齐药丸，限宽后随内容收缩。
  /// 不带发送者标签和时间戳——只有两个说话人的界面里那两行是纯噪音。
  Widget _buildUserMessage(app_chat.ChatMessage message, ThemeData theme) {
    // 圆角随主题风格变化，不能是 const。
    final radius = BorderRadius.circular(
      AppShapeTokens.of(context).dialogRadius,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      // FractionallySizedBox 给出 78% 宽的紧约束，内层 Align 再放松成松约束，
      // 于是气泡短时贴着内容收缩、长时在 78% 处换行。
      child: FractionallySizedBox(
        alignment: Alignment.centerRight,
        widthFactor: _kUserBubbleWidthFactor,
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: radius,
            ),
            child: Text(
              message.content,
              // 和 AI 正文同字号：两侧字号不一样时，用户会觉得自己说的话
              // 和 AI 说的话不在一个层级上
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onPrimary,
                height: 1.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// AI 回复：不套气泡，正文直接铺在页面背景上占满可读宽度。
  /// markdown 里的标题、列表、代码块套气泡会被挤窄，长文阅读体验差。
  Widget _buildAgentMessage(
    app_chat.ChatMessage message,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    // 已经收到内容但仍在生成：正文末尾接一个光标，位置准确且随文字增长。
    final isStreaming = message.state == MessageState.responding ||
        (message.isLoading && message.state != MessageState.error);
    final hasContent = message.content.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 思考内容显示（仅当有思考时）
          // 性能优化：只 join 一次，避免重复字符串拼接
          if (message.thinkingChunks.isNotEmpty)
            Builder(
              builder: (context) {
                final thinkingText = message.thinkingChunks.join('');
                if (thinkingText.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ThinkingWidget(
                    key: ValueKey('thinking_${message.id}'),
                    thinkingText: thinkingText,
                    inProgress: message.state == MessageState.thinking,
                    accentColor: theme.colorScheme.primary,
                  ),
                );
              },
            ),
          // 还没有首个 token：正文是空的，光标先自己闪着占住位置
          if (!hasContent && isStreaming)
            _BlinkingCursor(color: theme.colorScheme.onSurfaceVariant)
          else if (hasContent)
            MarkdownBody(
              data: isStreaming
                  ? '${message.content}$_kStreamingCursor'
                  : message.content,
              selectable: true,
              // 性能优化：缓存 MarkdownStyleSheet，避免每帧重建
              styleSheet: _getMarkdownStyleSheet(
                theme,
                theme.colorScheme.onSurface,
              ),
              onTapLink: (text, href, title) async {
                if (href == null || href.isEmpty) return;
                try {
                  final uri = Uri.tryParse(href);
                  if (uri != null && await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                } catch (_) {}
              },
            ),
          // 生成完成后才给操作行：流式过程中正文还在长，复制到的是半截；
          // 一轮里只有收尾那条挂操作行（见 _isTurnClosingMessage）
          if (!isStreaming && hasContent && _isTurnClosingMessage(message))
            _buildMessageActions(message, theme, l10n),
          // 出错时保留正文并显式标记，避免内容被静默删除
          if (message.state == MessageState.error)
            Padding(
              padding: const EdgeInsets.only(top: 8),
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

  /// 这条回复是不是这一轮的收尾。
  ///
  /// AI 常常先说一句「我看看你最近写了什么」，调完工具再给结论——那是一轮，
  /// 不是两轮。每段正文各挂一行复制/重试会把一轮切成两半，所以操作行只跟在
  /// 这一轮最后一段正文后面。工具进度和提案卡不算"话"，跨过去继续找。
  bool _isTurnClosingMessage(app_chat.ChatMessage message) {
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index == -1) return false;
    // 本轮还在跑：后面随时可能再接一段正文，先不挂
    if (_isLoading && index > _messages.lastIndexWhere((m) => m.isUser)) {
      return false;
    }
    for (var i = index + 1; i < _messages.length; i++) {
      final next = _messages[i];
      if (next.isUser) return true; // 下一轮开始了
      if (next.role == 'system') continue; // 轮次上限之类的提示不是回答
      if (next.parsedMeta != null) continue; // 工具进度、提案卡
      if (next.content.trim().isNotEmpty) return false;
    }
    return true;
  }

  /// AI 回复下方的操作行：复制 / 重新生成 / 查看过程。
  Widget _buildMessageActions(
    app_chat.ChatMessage message,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    final toolSnapshot = _toolProcessBefore(message);
    // 只思考的那轮说「查看思考过程」，调了工具才说「查看过程」——按钮文案
    // 得对得上点开后看到的东西。
    final thinkingOnly = toolSnapshot != null && toolSnapshot.items.isEmpty;
    final processLabel =
        thinkingOnly ? l10n.showThinking : l10n.viewToolProcess;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      // 按钮的热区自带 8 的横向留白，整行往左挪回去，第一枚图标才和正文
      // 左边缘对齐——否则这一行看起来比正文缩进了一点。
      child: Transform.translate(
        offset: const Offset(-8, 0),
        child: Row(
          children: [
            _MessageAction(
              icon: Icons.content_copy_outlined,
              tooltip: l10n.copy,
              onTap: () => _copyMessage(message, l10n),
            ),
            _MessageAction(
              icon: Icons.refresh,
              tooltip: l10n.regenerate,
              // 生成中重来会和进行中的请求打架
              onTap: _isLoading ? null : () => _regenerateFrom(message),
            ),
            if (toolSnapshot != null)
              _MessageAction(
                icon: thinkingOnly
                    ? Icons.psychology_outlined
                    : Icons.account_tree_outlined,
                tooltip: processLabel,
                label: processLabel,
                onTap: () => showToolProgressSheet(
                  context,
                  ValueNotifier(toolSnapshot),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyMessage(
    app_chat.ChatMessage message,
    AppLocalizations l10n,
  ) async {
    await Clipboard.setData(ClipboardData(text: message.content));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.copiedToClipboard)),
    );
  }

  /// 重新生成：删掉这条回复以及它和上一条用户提问之间的工具进度，
  /// 然后拿那条提问重问一次。
  Future<void> _regenerateFrom(app_chat.ChatMessage message) async {
    if (_isLoading) return;
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index == -1) return;

    final userIndex =
        _messages.sublist(0, index).lastIndexWhere((m) => m.isUser);
    if (userIndex == -1) return;
    final question = _messages[userIndex].content.trim();
    if (question.isEmpty) return;

    // 这一轮产生的所有助手侧消息（回复 + 工具进度）一起清掉，
    // 只留下用户那条提问
    final doomed = _messages.sublist(userIndex + 1, index + 1).toList();
    _setState(() {
      _messages.removeRange(userIndex + 1, index + 1);
    });
    for (final removed in doomed) {
      unawaited(_chatSessionService.deleteMessage(removed.id));
    }

    _setAutoScrollEnabled(true);
    _agentStatusDismissTimer?.cancel();
    _setState(() {
      _isLoading = true;
    });
    await _askAgent(question);
  }

  /// 找出这条回复之前、同一轮里的过程记录，用来喂「查看过程」抽屉。
  ///
  /// 过程不只有工具调用：模型可能这一轮什么都没查，只是想了一会儿再回答。
  /// 那一样是过程，一样该能翻回去看——否则「只思考」的那轮，回答定稿后正文上方
  /// 只剩一行折叠标题，下面的操作行却什么都不给，看着像思考被吞了。
  ToolProgressSnapshot? _toolProcessBefore(app_chat.ChatMessage message) {
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index <= 0) return null;
    for (var i = index - 1; i >= 0; i--) {
      final candidate = _messages[i];
      // 回到上一条用户提问就说明这一轮没有过程可看
      if (candidate.isUser) return null;
      final meta = candidate.parsedMeta;
      if (meta == null || meta['type'] != 'tool_progress') continue;
      final rawItems = meta['items'] as List<dynamic>? ?? const [];
      final thinkingText = meta['thinkingText']?.toString().trim() ?? '';
      if (rawItems.isEmpty && thinkingText.isEmpty) return null;
      final items = rawItems.map((item) {
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
      final l10n = AppLocalizations.of(context);
      return ToolProgressSnapshot(
        // 标题按这一轮实际发生的事说：没调工具就别报「执行了 0 个操作」。
        title: items.isEmpty
            ? l10n.thinking
            : l10n.executedNOperations(items.length),
        items: items,
        thinkingText: thinkingText.isEmpty ? null : thinkingText,
      );
    }
    return null;
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

  /// 深度思考开关。带文字的 chip 而不是一枚图标按钮：图标按钮在这一行里
  /// 左边一大片空白，且"大脑图标亮着"表达不出它是个可切换的模式。
  Widget _buildThinkingChip(ThemeData theme, AppLocalizations l10n) {
    final on = _enableThinking;
    final foreground = on
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurfaceVariant;
    return Semantics(
      toggled: on,
      child: Tooltip(
        message: on ? l10n.hideThinking : l10n.showThinking,
        child: Material(
          color: on ? theme.colorScheme.secondaryContainer : Colors.transparent,
          shape: StadiumBorder(
            side: on
                ? BorderSide.none
                : BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap:
                _isLoading ? null : () => unawaited(_setThinkingEnabled(!on)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    on ? Icons.psychology : Icons.psychology_outlined,
                    size: 16,
                    color: foreground,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    l10n.thinkingMode,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: foreground,
                      fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea(ThemeData theme, AppLocalizations l10n) {
    final scheme = theme.colorScheme;
    final shape = AppShapeTokens.of(context);
    // 输入壳比卡片再圆一档：它是一个会长高的容器，方角在多行时显得笨重。
    // 仍然跟着主题的 cardRadius 走，纸/素笺的方正不会被这里拉圆。
    final shellRadius = (shape.cardRadius * 1.4).clamp(0.0, 26.0).toDouble();
    final focused = _isInputFocused;
    // 描边宽度恒定：聚焦时改宽会让内部文字横跳半个像素。只换颜色。
    final borderColor = focused
        ? scheme.primary.withValues(alpha: 0.55)
        : scheme.outlineVariant.withValues(alpha: 0.7);

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          // 壳比对话背景高一层，靠明度自己划出边界；聚焦时再抬一层，
          // 「正在输入」是被点亮的，不是被托起来的。
          color: focused
              ? scheme.surfaceContainerHighest
              : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(shellRadius),
          border: Border.all(color: borderColor),
          // 不投影：输入框不是浮在对话上的一张卡，一圈落地的阴影反而把它和
          // 消息流割开。聚焦时改画一圈贴边的强调色高光——ChatGPT / Claude /
          // Gemini 都是这个路子，而且它在纸墨这类零投影的风格下同样成立。
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: focused ? 0.14 : 0.0),
              blurRadius: 0,
              spreadRadius: focused ? 3 : 0,
            ),
          ],
        ),
        // 整个壳都是输入热区：只有细细一行文字能点，在手机上太难命中。
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (!_inputFocusNode.hasFocus) {
              _inputFocusNode.requestFocus();
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 输入区默认一行高，随换行增高；超过上限后内部滚动，
              // 避免长输入把对话内容整个挤出屏幕。
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 148),
                child: TextField(
                  controller: _textController,
                  focusNode: _inputFocusNode,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.35),
                  decoration: InputDecoration(
                    hintText: l10n.aiAssistantInputHint,
                    hintStyle: theme.textTheme.bodyLarge?.copyWith(
                      height: 1.35,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                    border: InputBorder.none,
                    isCollapsed: true,
                    contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  ),
                  maxLines: null,
                  minLines: 1,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  // 软键盘的回车是换行，不是发送：手机上问长一点的问题要分段，
                  // 回车即发会把半句话打出去，且没有撤回。发送只走右下角那枚键。
                  // 接了实体键盘（桌面/平板）的场景由 _handleComposerKey 兜底：
                  // 那里 Enter 发送、Shift+Enter 换行，符合键盘用户的肌肉记忆。
                  textInputAction: TextInputAction.newline,
                ),
              ),
              // 动作行：左边是模式开关，右边是发送。和主流 AI 输入框一致，
              // 让「写什么」和「怎么发」分成上下两层。
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                child: Row(
                  children: [
                    // Agent requests do not yet apply provider thinking settings.
                    if (!_isAgentMode && _currentModelSupportsThinking)
                      _buildThinkingChip(theme, l10n),
                    const Spacer(),
                    _buildSendButton(theme, l10n),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 发送 / 停止按钮。
  ///
  /// 一枚固定尺寸的圆：位置不随图标和状态变，眼睛不用重新找。停止态不用错误
  /// 红——中止生成不是出错，红色会把一个日常操作说成事故。
  Widget _buildSendButton(ThemeData theme, AppLocalizations l10n) {
    final scheme = theme.colorScheme;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _textController,
      builder: (context, value, _) {
        final canSend = value.text.trim().isNotEmpty;
        return IconButton(
          key: const ValueKey('ai_assistant_send_button'),
          // 发送→停止的切换做个淡入淡出，避免图标硬跳。
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 140),
            child: Icon(
              _isLoading ? Icons.stop_rounded : Icons.arrow_upward,
              key: ValueKey(_isLoading),
              size: 20,
            ),
          ),
          tooltip: _isLoading ? l10n.stopGenerate : l10n.send,
          onPressed: _isLoading
              ? _stopGenerating
              : canSend
                  ? () => _handleSubmitted(_textController.text)
                  : null,
          style: IconButton.styleFrom(
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
            disabledBackgroundColor: scheme.surfaceContainerHighest,
            disabledForegroundColor:
                scheme.onSurfaceVariant.withValues(alpha: 0.55),
            shape: const CircleBorder(),
            padding: EdgeInsets.zero,
            fixedSize: const Size(38, 38),
            minimumSize: const Size(38, 38),
          ),
        );
      },
    );
  }

  Future<String?> _openNoteProposalInEditor(
    NoteProposalArtifact artifact,
  ) async {
    _dropInputFocus();
    final db = context.read<DatabaseService>();
    if (artifact.action == NoteProposalAction.create) {
      final validatedOps = _validatedArtifactOps(artifact);
      // 按内容实际形态而不是模型声明的 kind 选编辑器：声明 rich 但
      // ops 里没有任何格式时也是普通笔记，应走快速编辑弹窗。
      final effectivelyPlain = artifact.resultKind == NoteDocumentKind.plain ||
          !_opsHaveRichFormatting(validatedOps);
      if (effectivelyPlain &&
          !context.read<SettingsService>().skipNonFullscreenEditor) {
        final tags = await db.getTags();
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
    final tags = await db.getTags();
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
    final result = await NoteProposalApplier(db).applyEdit(artifact);
    if (!result.isApplied) {
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

  Quote _quoteFromArtifact(Quote original, NoteProposalArtifact artifact) =>
      NoteProposalApplier.quoteFromArtifact(original, artifact);

  List<Map<String, dynamic>>? _validatedArtifactOps(
    NoteProposalArtifact artifact, {
    Quote? original,
  }) =>
      NoteProposalApplier.validatedArtifactOps(artifact, original: original);

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

  List<String> _extractStringList(Object? value) =>
      NoteProposalApplier.extractStringList(value);

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
    _dropInputFocus();
    // 没有真实格式的 delta 等同于纯文本，不应该被当成富文本强推全屏编辑器
    if (richDocument != null &&
        !_opsHaveRichFormatting(_opsFromRichDocument(richDocument))) {
      richDocument = null;
    }
    if (richDocument == null &&
        _isShortContent(content) &&
        !DeltaBuilder.hasMarkdownFormatting(content)) {
      final db = context.read<DatabaseService>();
      final tags = await db.getTags();
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
    final tags = await db.getTags();

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
        'ThoughterPage._saveSmartResultAsNewNote 失败',
        error: e,
        stackTrace: stack,
        source: 'ThoughterPage',
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

/// 回复下方的一枚操作按钮。默认只有图标（复制/重新生成的图标是通用语汇），
/// 传了 [label] 的会带上文字——「查看过程」没有约定俗成的图标，光一个图标
/// 没人知道点了会发生什么。
class _MessageAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final String? label;
  final VoidCallback? onTap;

  const _MessageAction({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;
    final foreground = theme.colorScheme.onSurfaceVariant
        .withValues(alpha: enabled ? 1.0 : 0.38);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        // 手指按的是这块 40×40，不是那枚 16 的图标——原来整个可点区域只有
        // 28 见方，复制和重来挨在一起，很容易点成隔壁那个。
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: label == null ? 8 : 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: foreground),
                if (label != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    label!,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: foreground,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 等待中的光标。正文流式输出时光标是接在文字末尾的字符（[_kStreamingCursor]），
/// 还没有正文可接的那段时间——刚发出提问、正在调工具——由它顶上，用的是同一个
/// 字形，于是从"等着"到"开始说"是同一个光标在延续，而不是换了个动画。
class _BlinkingCursor extends StatefulWidget {
  final Color color;

  const _BlinkingCursor({super.key, required this.color});

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );

  late final Animation<double> _opacity = Tween<double>(
    // 不闪到全透明：完全消失一拍会让人以为断了
    begin: 0.25,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 系统开了"减弱动态效果"就定住不闪——一个持续跳动的光标正是这项设置
    // 想要屏蔽的东西。
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      _controller.stop();
      _controller.value = 1.0;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FadeTransition(
      opacity: _opacity,
      child: Text(
        _kStreamingCursor,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: widget.color,
          height: 1.65,
        ),
      ),
    );
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
