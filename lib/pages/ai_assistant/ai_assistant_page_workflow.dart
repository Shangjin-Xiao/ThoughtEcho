part of '../ai_assistant_page.dart';

extension _AIAssistantPageWorkflow on _AIAssistantPageState {
  Future<void> _handleSubmitted(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isLoading) return;
    final l10n = AppLocalizations.of(context);

    _textController.clear();

    final userMsg = app_chat.ChatMessage(
      id: _uuid.v4(),
      content: trimmed,
      isUser: true,
      role: 'user',
      timestamp: DateTime.now(),
    );

    _setState(() {
      _messages.add(userMsg);
      _isLoading = true;
    });
    _scrollToBottom();

    await _ensureSessionCreated(trimmed);
    await _chatSessionService.addMessage(_currentSessionId!, userMsg);

    final descriptor = _matchWorkflowCommand(trimmed, l10n);
    if (descriptor != null) {
      await _runExplicitWorkflow(descriptor, trimmed);
      return;
    }

    // 检测自然语言触发（Agent模式下）
    if (_isAgentMode && descriptor == null) {
      final workflows = _buildWorkflowDescriptors(l10n);
      final triggeredId =
          NaturalLanguageTriggerDetector.shouldAutoTrigger(trimmed, workflows);
      if (triggeredId != null) {
        final triggered = workflows.firstWhere(
          (d) => d.id == triggeredId,
          orElse: () => workflows.first,
        );
        logDebug('自然语言触发命令: ${triggered.command}');
        // 可以选择自动触发或提示用户
        // 这里我们可以添加用户提示或直接执行
      }
    }

    if (_isAgentMode) {
      _agentStatusDismissTimer?.cancel();
      await _askAgent(trimmed);
      return;
    }

    if (_currentMode == AIAssistantPageMode.noteChat) {
      await _askBoundNote(trimmed);
      return;
    }

    await _askGeneralChat(trimmed);
  }

  Future<void> _runExplicitWorkflow(
    AIWorkflowDescriptor descriptor,
    String text,
  ) async {
    final l10n = AppLocalizations.of(context);

    if (descriptor.requiresBoundNote && !_hasBoundNote) {
      _appendCardMessage(
        type: 'notice',
        content: l10n.aiWorkflowNeedsBoundNote,
        meta: <String, dynamic>{
          'title': l10n.workflowUnavailable,
          'icon': Icons.lock_outline.codePoint,
        },
      );
      _finishLoading();
      return;
    }

    switch (descriptor.id) {
      case AIWorkflowId.polish:
        await _runEditableWorkflow(
          title: l10n.polishResult,
          loadingText: l10n.polishingText,
          command: descriptor.command,
          stream: _aiService.streamPolishText(widget.quote!.content),
        );
        break;
      case AIWorkflowId.continueWriting:
        await _runEditableWorkflow(
          title: l10n.continueResult,
          loadingText: l10n.continuingText,
          command: descriptor.command,
          stream: _aiService.streamContinueText(widget.quote!.content),
        );
        break;
      case AIWorkflowId.deepAnalysis:
        await _runMarkdownWorkflow(
          title: l10n.commandDeepAnalysis,
          loadingText: l10n.analyzingNote,
          stream: _aiService.streamSummarizeNote(widget.quote!),
        );
        break;
      case AIWorkflowId.sourceAnalysis:
        await _runSourceAnalysisWorkflow(
          stream: _aiService.streamAnalyzeSource(widget.quote!.content),
        );
        break;
      case AIWorkflowId.insights:
        _showInsightWorkflowCard();
        _finishLoading();
        break;
      case AIWorkflowId.webFetch:
        await _handleWebFetchWorkflow(text, descriptor);
        break;
    }
  }

  void _showInsightWorkflowCard() {
    _appendCardMessage(
      type: 'insight_config',
      content: '',
      meta: <String, dynamic>{'title': 'insight_config'},
    );
  }

  Future<void> _runEditableWorkflow({
    required String title,
    required String loadingText,
    required String command,
    required Stream<String> stream,
  }) async {
    final l10n = AppLocalizations.of(context);
    final aiMsgId = _uuid.v4();
    _appendMessage(
      app_chat.ChatMessage(
        id: aiMsgId,
        content: loadingText,
        isUser: false,
        role: 'assistant',
        timestamp: DateTime.now(),
        isLoading: true,
      ),
    );

    String fullResponse = '';
    _streamSubscription?.cancel();
    _streamSubscription = stream.listen(
      (chunk) {
        fullResponse += chunk;
        _updateMessage(aiMsgId, fullResponse, isLoading: true);
      },
      onDone: () {
        _updateMessage(
          aiMsgId,
          fullResponse,
          isLoading: false,
          metaJson: jsonEncode(<String, dynamic>{
            'type': 'smart_result',
            'command': command,
            'title': title,
            'replaceButtonText': l10n.replaceOriginalNote,
            'appendButtonText': l10n.appendToEnd,
          }),
        );
      },
      onError: (error) {
        _updateMessage(aiMsgId, l10n.aiResponseError(error.toString()),
            isLoading: false);
      },
    );
  }

  Future<void> _runMarkdownWorkflow({
    required String title,
    required String loadingText,
    required Stream<String> stream,
  }) async {
    final l10n = AppLocalizations.of(context);
    final aiMsgId = _uuid.v4();
    _appendMessage(
      app_chat.ChatMessage(
        id: aiMsgId,
        content: loadingText,
        isUser: false,
        role: 'assistant',
        timestamp: DateTime.now(),
        isLoading: true,
      ),
    );

    String fullResponse = '';
    _streamSubscription?.cancel();
    _streamSubscription = stream.listen(
      (chunk) {
        fullResponse += chunk;
        _updateMessage(aiMsgId, fullResponse, isLoading: true);
      },
      onDone: () {
        _updateMessage(
          aiMsgId,
          fullResponse.isNotEmpty ? fullResponse : l10n.aiMisunderstoodQuestion,
          isLoading: false,
          metaJson: jsonEncode(<String, dynamic>{
            'type': 'markdown_result',
            'title': title,
          }),
        );
      },
      onError: (error) {
        _updateMessage(aiMsgId, l10n.aiResponseError(error.toString()),
            isLoading: false);
      },
    );
  }

  Future<void> _runSourceAnalysisWorkflow({
    required Stream<String> stream,
  }) async {
    final l10n = AppLocalizations.of(context);
    final aiMsgId = _uuid.v4();
    _appendMessage(
      app_chat.ChatMessage(
        id: aiMsgId,
        content: l10n.analyzingSource,
        isUser: false,
        role: 'assistant',
        timestamp: DateTime.now(),
        isLoading: true,
      ),
    );

    String fullResponse = '';
    _streamSubscription?.cancel();
    _streamSubscription = stream.listen(
      (chunk) {
        fullResponse += chunk;
        _updateMessage(aiMsgId, fullResponse, isLoading: true);
      },
      onDone: () {
        try {
          final sourceData =
              SourceAnalysisResultDialog.parseResult(fullResponse);
          _updateMessage(
            aiMsgId,
            fullResponse,
            isLoading: false,
            metaJson: jsonEncode(<String, dynamic>{
              'type': 'source_analysis_result',
              'title': l10n.analysisResult,
              'author': sourceData['author'],
              'work': sourceData['work'],
              'confidence': sourceData['confidence'] ?? l10n.unknown,
              'explanation': sourceData['explanation'] ?? '',
            }),
          );
        } catch (_) {
          _updateMessage(
            aiMsgId,
            fullResponse,
            isLoading: false,
            metaJson: jsonEncode(<String, dynamic>{
              'type': 'markdown_result',
              'title': l10n.analysisResult,
            }),
          );
        }
      },
      onError: (error) {
        _updateMessage(aiMsgId, l10n.aiResponseError(error.toString()),
            isLoading: false);
      },
    );
  }

  Future<void> _handleWebFetchWorkflow(
    String text,
    AIWorkflowDescriptor descriptor,
  ) async {
    final l10n = AppLocalizations.of(context);

    // 从命令文本提取URL
    final url = WebCommandHelper.extractUrl(text);

    if (url == null || url.isEmpty) {
      _appendCardMessage(
        type: 'notice',
        content: l10n
            .aiResponseError('Please provide a valid URL with /web command'),
        meta: <String, dynamic>{
          'title': 'Invalid URL',
          'icon': Icons.info_outline.codePoint,
        },
      );
      _finishLoading();
      return;
    }

    // 显示工具调用指示
    final toolCallMsg = SessionMessageHelper.createToolCallIndicatorMessage(
      toolName: 'web_fetch',
      parameters: {'url': url},
    );
    _appendMessage(toolCallMsg, persist: true);

    // 运行网页抓取工作流
    await _runMarkdownWorkflow(
      title: 'Web Content',
      loadingText: 'Fetching web content from: $url',
      stream: _aiService.streamFetchWebContent(url),
    );
  }

  Future<void> _runInsightsWorkflow() async {
    final l10n = AppLocalizations.of(context);
    final databaseService = _tryGetDatabaseService();
    if (databaseService == null) {
      _appendCardMessage(
        type: 'notice',
        content: l10n.aiResponseError('DatabaseService unavailable'),
        meta: <String, dynamic>{
          'title': l10n.workflowUnavailable,
          'icon': Icons.error_outline.codePoint,
        },
      );
      return;
    }

    final quotes = await databaseService.getUserQuotes();
    if (quotes.isEmpty) {
      _appendCardMessage(
        type: 'notice',
        content: l10n.noNotesFound,
        meta: <String, dynamic>{
          'title': l10n.commandInsight,
          'icon': Icons.info_outline.codePoint,
        },
      );
      return;
    }

    await _runMarkdownWorkflow(
      title: l10n.commandInsight,
      loadingText: l10n.generatingInsightsForPeriod(l10n.thisWeek),
      stream: _aiService.streamGenerateInsights(
        quotes,
        analysisType: _selectedInsightType,
        analysisStyle: _selectedInsightStyle,
      ),
    );
  }

  Future<void> _askBoundNote(String text) async {
    final l10n = AppLocalizations.of(context);
    final aiMsgId = _uuid.v4();

    // 初始化AI回复消息，状态为thinking
    _appendMessage(
      app_chat.ChatMessage(
        id: aiMsgId,
        content: l10n.thinkingInProgress,
        isUser: false,
        role: 'assistant',
        timestamp: DateTime.now(),
        isLoading: true,
        state: MessageState.thinking,
      ),
    );

    String fullResponse = '';
    final thinkingParts = <String>[];
    final history = _messages
        .where((m) => m.includedInContext && m.id != aiMsgId && !m.isLoading)
        .toList();

    _streamSubscription?.cancel();

    int uiChunkCount = 0;

    // 使用流式订阅，支持实时更新
    _streamSubscription = _aiService.streamAskQuestion(
      widget.quote!,
      text,
      history: history,
      onThinking: (thinkingChunk) {
        thinkingParts.add(thinkingChunk);
        _updateMessage(
          aiMsgId,
          fullResponse,
          isLoading: true,
          state: MessageState.thinking,
          thinkingChunks: List<String>.from(thinkingParts),
        );
      },
    ).listen(
      (chunk) {
        uiChunkCount++;
        fullResponse += chunk;
        _updateMessage(
          aiMsgId,
          fullResponse,
          isLoading: true,
          state: MessageState.responding,
          thinkingChunks: thinkingParts.isNotEmpty
              ? List<String>.from(thinkingParts)
              : null,
        );
      },
      onDone: () {
        logDebug('[UI] _askBoundNote 完成: $uiChunkCount 个 UI chunk');
        _updateMessage(
          aiMsgId,
          fullResponse.isNotEmpty ? fullResponse : l10n.aiMisunderstoodQuestion,
          isLoading: false,
          state: MessageState.complete,
          thinkingChunks: thinkingParts.isNotEmpty
              ? List<String>.from(thinkingParts)
              : null,
        );
      },
      onError: (error) {
        _updateMessage(
          aiMsgId,
          l10n.aiResponseError(error.toString()),
          isLoading: false,
          state: MessageState.error,
        );
      },
    );
  }

  Future<void> _askGeneralChat(String text) async {
    final l10n = AppLocalizations.of(context);
    final aiMsgId = _uuid.v4();

    // 初始化AI回复消息，状态为thinking
    _appendMessage(
      app_chat.ChatMessage(
        id: aiMsgId,
        content: l10n.thinkingInProgress,
        isUser: false,
        role: 'assistant',
        timestamp: DateTime.now(),
        isLoading: true,
        state: MessageState.thinking,
      ),
    );

    String fullResponse = '';
    final thinkingParts = <String>[];
    final history = _messages
        .where((m) => m.includedInContext && m.id != aiMsgId && !m.isLoading)
        .toList();

    _streamSubscription?.cancel();

    int uiChunkCount = 0;

    // 使用流式订阅，支持实时更新
    _streamSubscription = _aiService.streamGeneralConversation(
      text,
      history: history,
      systemContext: widget.exploreGuideSummary,
      onThinking: (thinkingChunk) {
        thinkingParts.add(thinkingChunk);
        _updateMessage(
          aiMsgId,
          fullResponse,
          isLoading: true,
          state: MessageState.thinking,
          thinkingChunks: List<String>.from(thinkingParts),
        );
      },
    ).listen(
      (chunk) {
        uiChunkCount++;
        fullResponse += chunk;
        _updateMessage(
          aiMsgId,
          fullResponse,
          isLoading: true,
          state: MessageState.responding,
          thinkingChunks: thinkingParts.isNotEmpty
              ? List<String>.from(thinkingParts)
              : null,
        );
      },
      onDone: () {
        logDebug('[UI] _askGeneralChat 完成: $uiChunkCount 个 UI chunk');
        _updateMessage(
          aiMsgId,
          fullResponse.isNotEmpty ? fullResponse : l10n.aiMisunderstoodQuestion,
          isLoading: false,
          state: MessageState.complete,
          thinkingChunks: thinkingParts.isNotEmpty
              ? List<String>.from(thinkingParts)
              : null,
        );
      },
      onError: (error) {
        _updateMessage(
          aiMsgId,
          l10n.aiResponseError(error.toString()),
          isLoading: false,
          state: MessageState.error,
        );
      },
    );
  }
}
