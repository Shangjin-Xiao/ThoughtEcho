import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../gen_l10n/app_localizations.dart';
import '../models/ai_assistant_entry.dart';
import '../models/ai_insight_workflow_options.dart';
import '../models/ai_workflow_descriptor.dart';
import '../models/chat_message.dart' as app_chat;
import '../models/chat_session.dart';
import '../models/quote_model.dart';
import '../services/agent_service.dart';
import '../services/ai_service.dart';
import '../services/chat_session_service.dart';
import '../services/database_service.dart';
import '../services/settings_service.dart';
import '../utils/app_logger.dart';
import '../utils/string_utils.dart';
import '../widgets/ai/ai_workflow_cards.dart';
import '../widgets/ai/smart_result_card.dart';
import '../widgets/session_history_sheet.dart';
import '../widgets/source_analysis_result_dialog.dart';

class AIAssistantPage extends StatefulWidget {
  final Quote? quote;
  final String? initialQuestion;
  final ChatSession? session;
  final AIAssistantEntrySource? entrySource;
  final String? exploreGuideSummary;

  const AIAssistantPage({
    super.key,
    this.quote,
    this.initialQuestion,
    this.session,
    this.entrySource,
    this.exploreGuideSummary,
  });

  @override
  State<AIAssistantPage> createState() => _AIAssistantPageState();
}

class _AIAssistantPageState extends State<AIAssistantPage> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<app_chat.ChatMessage> _messages = [];
  final Uuid _uuid = const Uuid();

  bool _isLoading = false;
  String? _currentSessionId;
  StreamSubscription<String>? _streamSubscription;
  late ChatSessionService _chatSessionService;
  late AgentService _agentService;
  late AIService _aiService;
  late SettingsService _settingsService;
  late AIAssistantPageMode _currentMode;
  String _selectedInsightType = 'comprehensive';
  String _selectedInsightStyle = 'professional';

  AIAssistantEntrySource get _entrySource =>
      widget.entrySource ??
      (widget.quote != null
          ? AIAssistantEntrySource.note
          : AIAssistantEntrySource.explore);

  AIAssistantEntryConfig get _entryConfig =>
      AIAssistantEntryConfig(source: _entrySource);

  bool get _hasBoundNote => widget.quote != null;
  bool get _isAgentMode => _currentMode == AIAssistantPageMode.agent;

  List<AIWorkflowDescriptor> _buildWorkflowDescriptors(
    AppLocalizations l10n,
  ) {
    return [
      AIWorkflowDescriptor(
        id: AIWorkflowId.polish,
        command: '/润色',
        displayName: l10n.commandPolish,
        requiresBoundNote: true,
        allowedInStandardMode: true,
        allowAgentNaturalLanguageTrigger: true,
        producesEditableResult: true,
      ),
      AIWorkflowDescriptor(
        id: AIWorkflowId.continueWriting,
        command: '/续写',
        displayName: l10n.commandContinue,
        requiresBoundNote: true,
        allowedInStandardMode: true,
        allowAgentNaturalLanguageTrigger: true,
        producesEditableResult: true,
      ),
      AIWorkflowDescriptor(
        id: AIWorkflowId.deepAnalysis,
        command: '/深度分析',
        displayName: l10n.commandDeepAnalysis,
        requiresBoundNote: true,
        allowedInStandardMode: true,
        allowAgentNaturalLanguageTrigger: true,
        producesEditableResult: false,
      ),
      AIWorkflowDescriptor(
        id: AIWorkflowId.sourceAnalysis,
        command: '/分析来源',
        displayName: l10n.smartAnalyzeSource,
        requiresBoundNote: true,
        allowedInStandardMode: true,
        allowAgentNaturalLanguageTrigger: true,
        producesEditableResult: false,
      ),
      AIWorkflowDescriptor(
        id: AIWorkflowId.insights,
        command: '/智能洞察',
        displayName: l10n.commandInsight,
        requiresBoundNote: false,
        allowedInStandardMode: true,
        allowAgentNaturalLanguageTrigger: true,
        producesEditableResult: false,
      ),
    ];
  }

  AIWorkflowDescriptor? _matchWorkflowCommand(
      String text, AppLocalizations l10n) {
    final matchedId = AIWorkflowCommandRegistry.match(text);
    if (matchedId == null) return null;
    for (final descriptor in _buildWorkflowDescriptors(l10n)) {
      if (descriptor.id == matchedId) {
        return descriptor;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _currentMode = _entryConfig.defaultMode;
    WidgetsBinding.instance.addPostFrameCallback((_) => _initServicesAndLoad());
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initServicesAndLoad() async {
    _chatSessionService = context.read<ChatSessionService>();
    _agentService = context.read<AgentService>();
    _aiService = context.read<AIService>();
    _settingsService = context.read<SettingsService>();
    final restoredMode = _restoreModeFromSettings();
    if (restoredMode != _currentMode && mounted) {
      setState(() {
        _currentMode = restoredMode;
      });
    } else {
      _currentMode = restoredMode;
    }

    if (widget.session != null) {
      await _loadSession(widget.session!.id);
    } else if (_hasBoundNote &&
        !_isAgentMode &&
        widget.quote!.id != null &&
        _entrySource == AIAssistantEntrySource.note) {
      final session = await _chatSessionService.getLatestSessionForNote(
        widget.quote!.id!,
      );
      if (session != null) {
        await _loadSession(session.id);
      } else {
        await _createNewSession();
      }
    } else {
      await _createNewSession();
    }

    if (!mounted) return;
    if (_messages.isEmpty) {
      _addWelcomeMessage();
    }

    if (widget.initialQuestion?.trim().isNotEmpty == true) {
      unawaited(_handleSubmitted(widget.initialQuestion!.trim()));
    }
  }

  AIAssistantPageMode _restoreModeFromSettings() {
    final restored = switch (_entrySource) {
      AIAssistantEntrySource.explore => _settingsService.exploreAiAssistantMode,
      AIAssistantEntrySource.note => _settingsService.noteAiAssistantMode,
    };
    return _entryConfig.resolveRestoredMode(restored);
  }

  Future<void> _persistMode(AIAssistantPageMode mode) async {
    if (_entrySource == AIAssistantEntrySource.explore) {
      await _settingsService.setExploreAiAssistantMode(mode);
    } else {
      await _settingsService.setNoteAiAssistantMode(mode);
    }
  }

  Future<void> _setMode(AIAssistantPageMode mode) async {
    if (!_entryConfig.allowsMode(mode) || _currentMode == mode) {
      return;
    }
    setState(() {
      _currentMode = mode;
    });
    await _persistMode(mode);
  }

  Future<void> _createNewSession() async {
    final session = await _chatSessionService.createSession(
      sessionType: _sessionTypeForMode(_currentMode),
      noteId: widget.quote?.id ?? '',
      title: _hasBoundNote ? _getQuotePreview() : 'AI Chat',
    );
    _currentSessionId = session.id;
  }

  String _sessionTypeForMode(AIAssistantPageMode mode) {
    return switch (mode) {
      AIAssistantPageMode.chat => 'chat',
      AIAssistantPageMode.noteChat => 'note',
      AIAssistantPageMode.agent => 'agent',
    };
  }

  Future<void> _loadSession(String sessionId) async {
    _currentSessionId = sessionId;
    final messages = await _chatSessionService.getMessages(sessionId);
    if (!mounted) return;
    setState(() {
      _messages
        ..clear()
        ..addAll(messages);
    });
    _scrollToBottom();
  }

  String _getQuotePreview() {
    if (!_hasBoundNote) return '';
    final content =
        StringUtils.removeObjectReplacementChar(widget.quote!.content);
    return content.length <= 100 ? content : '${content.substring(0, 100)}...';
  }

  void _addWelcomeMessage() {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final String welcomeContent = _hasBoundNote
        ? l10n.aiAssistantWelcome(_getQuotePreview())
        : widget.exploreGuideSummary?.trim().isNotEmpty == true
            ? l10n.aiAssistantExploreWelcome(widget.exploreGuideSummary!.trim())
            : l10n.aiAssistantInputHint;

    final welcomeMsg = app_chat.ChatMessage(
      id: _uuid.v4(),
      content: welcomeContent,
      isUser: false,
      role: 'system',
      timestamp: DateTime.now(),
      includedInContext: false,
    );
    _appendMessage(welcomeMsg, persist: true);
  }

  Future<void> _startNewChat() async {
    setState(() {
      _messages.clear();
    });
    await _createNewSession();
    _addWelcomeMessage();
  }

  void _showSessionHistory() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SessionHistorySheet(
        noteId: widget.quote?.id ?? '',
        currentSessionId: _currentSessionId,
        chatSessionService: _chatSessionService,
        onSelect: (id) {
          Navigator.of(ctx).pop();
          _loadSession(id);
        },
        onDelete: (id) async {
          await _chatSessionService.deleteSession(id);
          if (!mounted || !ctx.mounted) return;
          if (id == _currentSessionId) {
            Navigator.of(ctx).pop();
            await _startNewChat();
          }
        },
        onNewChat: () {
          Navigator.of(ctx).pop();
          _startNewChat();
        },
      ),
    );
  }

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

    setState(() {
      _messages.add(userMsg);
      _isLoading = true;
    });
    _scrollToBottom();

    if (_currentSessionId == null) {
      await _createNewSession();
    }
    await _chatSessionService.addMessage(_currentSessionId!, userMsg);

    final descriptor = _matchWorkflowCommand(trimmed, l10n);
    if (descriptor != null) {
      await _runExplicitWorkflow(descriptor);
      return;
    }

    if (_isAgentMode) {
      await _askAgent(trimmed);
      return;
    }

    if (_currentMode == AIAssistantPageMode.noteChat) {
      await _askBoundNote(trimmed);
      return;
    }

    await _askGeneralChat(trimmed);
  }

  Future<void> _runExplicitWorkflow(AIWorkflowDescriptor descriptor) async {
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

  DatabaseService? _tryGetDatabaseService() {
    try {
      return context.read<DatabaseService>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  Future<void> _askBoundNote(String text) async {
    final l10n = AppLocalizations.of(context);
    final aiMsgId = _uuid.v4();
    _appendMessage(
      app_chat.ChatMessage(
        id: aiMsgId,
        content: l10n.thinkingInProgress,
        isUser: false,
        role: 'assistant',
        timestamp: DateTime.now(),
        isLoading: true,
      ),
    );

    String fullResponse = '';
    final history = _messages
        .where((m) => m.includedInContext && m.id != aiMsgId && !m.isLoading)
        .toList();
    _streamSubscription?.cancel();
    _streamSubscription = _aiService
        .streamAskQuestion(widget.quote!, text, history: history)
        .listen(
      (chunk) {
        fullResponse += chunk;
        _updateMessage(aiMsgId, fullResponse, isLoading: true);
      },
      onDone: () {
        _updateMessage(
          aiMsgId,
          fullResponse.isNotEmpty ? fullResponse : l10n.aiMisunderstoodQuestion,
          isLoading: false,
        );
      },
      onError: (error) {
        _updateMessage(aiMsgId, l10n.aiResponseError(error.toString()),
            isLoading: false);
      },
    );
  }

  Future<void> _askGeneralChat(String text) async {
    final l10n = AppLocalizations.of(context);
    final aiMsgId = _uuid.v4();
    _appendMessage(
      app_chat.ChatMessage(
        id: aiMsgId,
        content: l10n.thinkingInProgress,
        isUser: false,
        role: 'assistant',
        timestamp: DateTime.now(),
        isLoading: true,
      ),
    );

    String fullResponse = '';
    final history = _messages
        .where((m) => m.includedInContext && m.id != aiMsgId && !m.isLoading)
        .toList();
    _streamSubscription?.cancel();
    _streamSubscription = _aiService
        .streamGeneralConversation(
      text,
      history: history,
      systemContext: widget.exploreGuideSummary,
    )
        .listen(
      (chunk) {
        fullResponse += chunk;
        _updateMessage(aiMsgId, fullResponse, isLoading: true);
      },
      onDone: () {
        _updateMessage(
          aiMsgId,
          fullResponse.isNotEmpty ? fullResponse : l10n.aiMisunderstoodQuestion,
          isLoading: false,
        );
      },
      onError: (error) {
        _updateMessage(aiMsgId, l10n.aiResponseError(error.toString()),
            isLoading: false);
      },
    );
  }

  Future<void> _askAgent(String text) async {
    final l10n = AppLocalizations.of(context);
    final history = _messages.where((m) => m.includedInContext).toList();

    try {
      final response = await _agentService.runAgent(
        userMessage: text,
        history: history,
        noteContext: _hasBoundNote ? widget.quote!.content : null,
      );

      final aiMsg = app_chat.ChatMessage(
        id: _uuid.v4(),
        content: response.content,
        isUser: false,
        role: 'assistant',
        timestamp: DateTime.now(),
      );

      _appendMessage(aiMsg, persist: true);
      _finishLoading();
    } catch (e) {
      _finishLoading();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.aiResponseError(e.toString()))),
      );
    }
  }

  void _appendCardMessage({
    required String type,
    required String content,
    required Map<String, dynamic> meta,
  }) {
    final message = app_chat.ChatMessage(
      id: _uuid.v4(),
      content: content,
      isUser: false,
      role: 'assistant',
      timestamp: DateTime.now(),
      includedInContext: false,
      metaJson: jsonEncode(<String, dynamic>{'type': type, ...meta}),
    );
    _appendMessage(message, persist: true);
  }

  void _appendMessage(app_chat.ChatMessage message, {bool persist = false}) {
    setState(() {
      _messages.add(message);
    });
    if (persist && _currentSessionId != null) {
      unawaited(_chatSessionService.addMessage(_currentSessionId!, message));
    }
    _scrollToBottom();
  }

  void _updateMessage(
    String id,
    String newContent, {
    required bool isLoading,
    String? metaJson,
  }) {
    setState(() {
      final idx = _messages.indexWhere((m) => m.id == id);
      if (idx == -1) return;
      final oldMsg = _messages[idx];
      final updatedMsg = oldMsg.copyWith(
        content: newContent,
        isLoading: isLoading,
        metaJson: metaJson,
      );
      _messages[idx] = updatedMsg;
      if (!isLoading && _currentSessionId != null) {
        unawaited(
            _chatSessionService.addMessage(_currentSessionId!, updatedMsg));
      }
      if (!isLoading) {
        _isLoading = false;
      }
    });
    _scrollToBottom();
  }

  void _finishLoading() {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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
            onPressed: _showSessionHistory,
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
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return _buildMessageBubble(_messages[index], theme, l10n);
              },
            ),
          ),
          if (_isLoading && _isAgentMode)
            _buildAgentStatusIndicator(theme, l10n),
          _buildInputArea(theme, l10n),
        ],
      ),
    );
  }

  Widget _buildExploreGuideBanner(ThemeData theme, AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
      child: Text(
        l10n.aiAssistantExploreWelcome(widget.exploreGuideSummary!.trim()),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
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
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SmartResultCard(
                key: const ValueKey('ai_workflow_result_smart_result'),
                title: meta['title'] as String? ?? l10n.analysisResult,
                content: message.content,
                replaceButtonText:
                    meta['replaceButtonText'] as String? ?? l10n.applyChanges,
                appendButtonText:
                    meta['appendButtonText'] as String? ?? l10n.appendToNote,
                onReplace: () {
                  Navigator.pop(context, {
                    'action': 'replace',
                    'text': message.content,
                  });
                },
                onAppend: () {
                  Navigator.pop(context, {
                    'action': 'append',
                    'text': message.content,
                  });
                },
              ),
            );
          case 'notice':
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: AIWorkflowNoticeCard(
                title: meta['title'] as String? ?? l10n.workflowUnavailable,
                message: message.content,
                icon: IconData(
                  meta['icon'] as int? ?? Icons.info_outline.codePoint,
                  fontFamily: 'MaterialIcons',
                ),
              ),
            );
          case 'markdown_result':
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: AIWorkflowMarkdownCard(
                title: meta['title'] as String? ?? l10n.analysisResult,
                content: message.content,
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
                explanation: meta['explanation'] as String? ?? '',
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
                  setState(() {
                    _selectedInsightType = value;
                  });
                },
                onSelectStyle: (value) {
                  setState(() {
                    _selectedInsightStyle = value;
                  });
                },
                onRun: () {
                  _runInsightsWorkflow();
                },
                runLabel: l10n.startAnalysis,
              ),
            );
        }
      } catch (e) {
        AppLogger.e('Failed to render AI workflow message', error: e);
      }
    }

    final isUser = message.isUser;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(
                Icons.smart_toy,
                color: theme.colorScheme.onPrimaryContainer,
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isUser
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16).copyWith(
                  bottomRight: isUser ? const Radius.circular(0) : null,
                  bottomLeft: !isUser ? const Radius.circular(0) : null,
                ),
              ),
              child: isUser
                  ? Text(
                      message.content,
                      style: TextStyle(color: theme.colorScheme.onPrimary),
                    )
                  : MarkdownBody(
                      data: message.content,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: theme.colorScheme.secondaryContainer,
              child: Icon(
                Icons.person,
                color: theme.colorScheme.onSecondaryContainer,
                size: 18,
              ),
            ),
          ],
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

  Widget _buildAgentStatusIndicator(ThemeData theme, AppLocalizations l10n) {
    return Consumer<AgentService>(
      builder: (context, agentService, child) {
        if (!agentService.isRunning) return const SizedBox.shrink();
        final statusKey = agentService.currentStatusKey;
        final statusText = switch (statusKey) {
          '' => '...',
          'agentThinking' => l10n.agentThinking,
          'agentSearchingNotes' => l10n.agentSearchingNotes,
          'agentAnalyzingData' => l10n.agentAnalyzingData,
          'agentWebSearching' => l10n.agentWebSearching,
          _ => statusKey.startsWith(AgentService.agentToolCallPrefix)
              ? l10n.agentToolCall(
                  statusKey.substring(
                    AgentService.agentToolCallPrefix.length,
                  ),
                )
              : l10n.agentThinking,
        };

        return Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                statusText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputArea(ThemeData theme, AppLocalizations l10n) {
    final workflowDescriptors = _buildWorkflowDescriptors(l10n);

    return Container(
      padding: const EdgeInsets.all(8).copyWith(
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, -1),
            blurRadius: 5,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeSwitch(theme, l10n),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: workflowDescriptors.map((descriptor) {
                return ActionChip(
                  label: Text(descriptor.command),
                  onPressed: () {
                    _handleSubmitted(descriptor.command);
                  },
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _textController,
                  decoration: InputDecoration(
                    hintText: l10n.aiAssistantInputHint,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _handleSubmitted,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.send),
                  color: theme.colorScheme.onPrimary,
                  tooltip: l10n.confirm,
                  onPressed: () => _handleSubmitted(_textController.text),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeSwitch(ThemeData theme, AppLocalizations l10n) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            key: const ValueKey('ai_mode_chat_button'),
            label: Text(l10n.aiModeChat),
            selected: _currentMode != AIAssistantPageMode.agent,
            onSelected: (_) => _setMode(_entryConfig.defaultMode),
          ),
          ChoiceChip(
            key: const ValueKey('ai_mode_agent_button'),
            label: Text(l10n.aiModeAgent),
            selected: _currentMode == AIAssistantPageMode.agent,
            onSelected: (_) => _setMode(AIAssistantPageMode.agent),
          ),
        ],
      ),
    );
  }
}
