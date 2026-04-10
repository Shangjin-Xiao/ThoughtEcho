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
import '../widgets/ai/thinking_widget.dart';
import '../widgets/ai/tool_progress_panel.dart';
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
  final FocusNode _inputFocusNode = FocusNode();
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
  bool _settingsReady = false;
  late AIAssistantPageMode _currentMode;
  String _selectedInsightType = 'comprehensive';
  String _selectedInsightStyle = 'professional';
  bool _showSlashCommands = false; // Only show when user types /
  bool _enableThinking = true; // 是否启用思考模式（仅支持的模型显示）

  String _thinkingText = '';
  bool _isThinking = false;
  final List<ToolProgressItem> _toolProgressItems = [];
  bool _isToolInProgress = false;
  bool _showAgentStatusPanel = false;
  bool _isInputFocused = false;
  bool _agentListenerAttached = false;
  String _lastAgentStatusKey = '';
  bool _lastAgentRunning = false;
  bool _showScrollToBottom = false;
  Timer? _agentStatusDismissTimer;
  static const Duration _agentStatusDismissDuration =
      Duration(milliseconds: 1400);
  static final RegExp _agentCodeBlockPattern = RegExp(
    r'```([a-zA-Z0-9_-]+)\s*([\s\S]*?)```',
  );

  AIAssistantEntrySource get _entrySource =>
      widget.entrySource ??
      (widget.quote != null
          ? AIAssistantEntrySource.note
          : AIAssistantEntrySource.explore);

  AIAssistantEntryConfig get _entryConfig =>
      AIAssistantEntryConfig(source: _entrySource);

  bool get _hasBoundNote => widget.quote != null;
  String? get _boundNoteId {
    final id = widget.quote?.id?.trim();
    if (id == null || id.isEmpty) {
      return null;
    }
    return id;
  }

  bool get _isAgentMode => _currentMode == AIAssistantPageMode.agent;

  /// 当前模型显示名称（用于 AppBar 副标题）
  String? get _currentModelDisplayName {
    if (!_settingsReady) return null;
    final provider = _settingsService.multiAISettings.currentProvider;
    if (provider == null) return null;
    final model = provider.model.trim();
    return model.isNotEmpty ? model : provider.name;
  }

  /// 检查当前模型是否支持思考/推理模式
  bool get _currentModelSupportsThinking {
    if (!_settingsReady) return false;
    final provider = _settingsService.multiAISettings.currentProvider;
    return provider?.supportsThinking ?? false;
  }

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

  /// 判断消息内容是否为加载占位文本（此时显示动态点动画）
  bool _isLoadingPlaceholderContent(String content, AppLocalizations l10n) {
    return content.isEmpty ||
        content == l10n.thinkingInProgress ||
        content == l10n.analyzingNote ||
        content == l10n.analyzingSource ||
        content == l10n.polishingText ||
        content == l10n.continuingText;
  }

  @override
  void initState() {
    super.initState();
    _currentMode = _entryConfig.defaultMode;
    _textController.addListener(_onTextChanged);
    _inputFocusNode.addListener(_onInputFocusChanged);
    _scrollController.addListener(_onScrollPositionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initServicesAndLoad());
  }

  void _onScrollPositionChanged() {
    if (!_scrollController.hasClients) return;
    final maxExtent = _scrollController.position.maxScrollExtent;
    final current = _scrollController.position.pixels;
    final shouldShow = (maxExtent - current) > 150;
    if (shouldShow != _showScrollToBottom) {
      setState(() {
        _showScrollToBottom = shouldShow;
      });
    }
  }

  void _onTextChanged() {
    final text = _textController.text.trimLeft();
    final shouldShow = text.startsWith('/');
    if (shouldShow != _showSlashCommands) {
      setState(() {
        _showSlashCommands = shouldShow;
      });
    }
  }

  void _onInputFocusChanged() {
    if (!mounted || _isInputFocused == _inputFocusNode.hasFocus) {
      return;
    }
    setState(() {
      _isInputFocused = _inputFocusNode.hasFocus;
    });
  }

  @override
  void dispose() {
    _agentStatusDismissTimer?.cancel();
    if (_agentListenerAttached) {
      _agentService.removeListener(_onAgentServiceChanged);
    }
    _streamSubscription?.cancel();
    _inputFocusNode.removeListener(_onInputFocusChanged);
    _textController.removeListener(_onTextChanged);
    _scrollController.removeListener(_onScrollPositionChanged);
    _inputFocusNode.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initServicesAndLoad() async {
    _chatSessionService = context.read<ChatSessionService>();
    _agentService = context.read<AgentService>();
    _aiService = context.read<AIService>();
    _settingsService = context.read<SettingsService>();
    if (!_agentListenerAttached) {
      _agentService.addListener(_onAgentServiceChanged);
      _agentListenerAttached = true;
    }
    _settingsReady = true;
    final restoredMode = _restoreModeFromSettings();
    if (restoredMode != _currentMode && mounted) {
      setState(() {
        _currentMode = restoredMode;
      });
    } else {
      _currentMode = restoredMode;
    }

    // Initialize _enableThinking based on whether the current model supports thinking.
    // This is done after _settingsService is guaranteed to be initialized.
    _enableThinking = _currentModelSupportsThinking;

    if (widget.session != null) {
      await _loadSession(widget.session!.id);
    } else if (_hasBoundNote &&
        !_isAgentMode &&
        _boundNoteId != null &&
        _entrySource == AIAssistantEntrySource.note) {
      final session = await _chatSessionService.getLatestSessionForNote(
        _boundNoteId!,
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

    _onAgentServiceChanged();
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
      noteId: _boundNoteId,
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
    // Cancel any ongoing stream before starting new chat
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    _isLoading = false;
    _agentStatusDismissTimer?.cancel();

    setState(() {
      _messages.clear();
      _thinkingText = '';
      _isThinking = false;
      _toolProgressItems.clear();
      _isToolInProgress = false;
      _showAgentStatusPanel = false;
      _lastAgentStatusKey = '';
      _lastAgentRunning = false;
    });
    await _createNewSession();
    _addWelcomeMessage();
  }

  void _showSessionHistory() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SessionHistorySheet(
        noteId: _boundNoteId ?? '',
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
      _agentStatusDismissTimer?.cancel();
      setState(() {
        _thinkingText = '';
        _isThinking = false;
        _toolProgressItems.clear();
        _isToolInProgress = false;
        _showAgentStatusPanel = false;
        _lastAgentStatusKey = '';
        _lastAgentRunning = false;
      });
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

      final parsed = _parseAgentSmartResult(response.content, l10n);

      if (parsed.displayText.isNotEmpty) {
        _appendMessage(
          app_chat.ChatMessage(
            id: _uuid.v4(),
            content: parsed.displayText,
            isUser: false,
            role: 'assistant',
            timestamp: DateTime.now(),
          ),
          persist: true,
        );
      }

      if (parsed.smartResult != null) {
        if (_hasBoundNote) {
          _appendMessage(
            app_chat.ChatMessage(
              id: _uuid.v4(),
              content: parsed.smartResult!.content,
              isUser: false,
              role: 'assistant',
              timestamp: DateTime.now(),
              metaJson: jsonEncode(<String, dynamic>{
                'type': 'smart_result',
                'title': parsed.smartResult!.title,
                'replaceButtonText': l10n.replaceOriginalNote,
                'appendButtonText': l10n.appendToEnd,
              }),
            ),
            persist: true,
          );
        } else {
          _appendMessage(
            app_chat.ChatMessage(
              id: _uuid.v4(),
              content: parsed.smartResult!.content,
              isUser: false,
              role: 'assistant',
              timestamp: DateTime.now(),
            ),
            persist: true,
          );
        }
      }

      if (parsed.displayText.isEmpty && parsed.smartResult == null) {
        _appendMessage(
          app_chat.ChatMessage(
            id: _uuid.v4(),
            content: l10n.aiMisunderstoodQuestion,
            isUser: false,
            role: 'assistant',
            timestamp: DateTime.now(),
          ),
          persist: true,
        );
      }
      _finishLoading();
    } catch (e) {
      _finishLoading();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.aiResponseError(e.toString()))),
      );
    }
  }

  _AgentSmartResultParseResult _parseAgentSmartResult(
    String rawContent,
    AppLocalizations l10n,
  ) {
    final trimmed = rawContent.trim();
    if (trimmed.isEmpty) {
      return const _AgentSmartResultParseResult(displayText: '');
    }

    for (final match in _agentCodeBlockPattern.allMatches(trimmed)) {
      final language = (match.group(1) ?? '').trim().toLowerCase();
      final payloadText = (match.group(2) ?? '').trim();
      if (payloadText.isEmpty) {
        continue;
      }

      final decoded = _tryDecodeJsonMap(payloadText);
      if (decoded == null) {
        continue;
      }

      final isSmartResultFence =
          language == 'smart_result' || language == 'smart-result';
      final type = decoded['type']?.toString().trim().toLowerCase();
      if (!isSmartResultFence && type != 'smart_result') {
        continue;
      }

      final smartContent =
          (decoded['content'] ?? decoded['text'])?.toString().trim();
      if (smartContent == null || smartContent.isEmpty) {
        continue;
      }

      final titleText = decoded['title']?.toString().trim();
      final title = titleText != null && titleText.isNotEmpty
          ? titleText
          : l10n.analysisResult;
      final displayText = trimmed.replaceFirst(match.group(0) ?? '', '').trim();

      return _AgentSmartResultParseResult(
        displayText: displayText,
        smartResult: _AgentSmartResultPayload(
          title: title,
          content: smartContent,
        ),
      );
    }

    return _AgentSmartResultParseResult(displayText: trimmed);
  }

  Map<String, dynamic>? _tryDecodeJsonMap(String payloadText) {
    try {
      final decoded = jsonDecode(payloadText);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } catch (_) {
      return null;
    }
    return null;
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

  /// Stop the current generation - cancels the stream subscription
  void _stopGenerating() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _agentStatusDismissTimer?.cancel();
    _finishLoading();
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
    final modelName = _currentModelDisplayName;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              _hasBoundNote ? l10n.askNoteTitle : l10n.aiAssistantLabel,
            ),
            if (modelName != null)
              Text(
                modelName,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.75),
                  fontWeight: FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
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
            child: Stack(
              children: [
                ListView.builder(
                  controller: _scrollController,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    return _buildMessageBubble(_messages[index], theme, l10n);
                  },
                ),
                // Scroll-to-bottom button
                if (_showScrollToBottom)
                  Positioned(
                    bottom: 12,
                    right: 16,
                    child: AnimatedOpacity(
                      opacity: _showScrollToBottom ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: FloatingActionButton.small(
                        heroTag: 'scroll_to_bottom_fab',
                        onPressed: _scrollToBottom,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHigh,
                        foregroundColor: theme.colorScheme.onSurface,
                        elevation: 3,
                        child: const Icon(Icons.keyboard_arrow_down),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_isAgentMode) _buildAgentStatusIndicator(theme, l10n),
          _buildInputArea(theme, l10n),
        ],
      ),
    );
  }

  Widget _buildExploreGuideBanner(ThemeData theme, AppLocalizations l10n) {
    // Just show the stats summary as context, not the full welcome message
    // The welcome message is already shown in chat messages
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
      child: Row(
        children: [
          Icon(Icons.analytics_outlined,
              size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.dataOverview,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteContextBanner(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.45),
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color:
                  theme.colorScheme.secondaryContainer.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.description_outlined,
              size: 14,
              color: theme.colorScheme.secondary,
            ),
          ),
          const SizedBox(width: 10),
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
                // 使用默认图标以支持 icon tree shaking
                // meta['icon'] 是运行时动态值，无法编译时确定为常量
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
    final isDark = theme.brightness == Brightness.dark;

    if (isUser) {
      // ── User message ── right-aligned pill, Gallery-style primary color, no border
      final bubbleBg = isDark
          ? Color.alphaBlend(
              theme.colorScheme.primary.withValues(alpha: 0.32),
              theme.colorScheme.surfaceContainerHigh,
            )
          : theme.colorScheme.primary;
      final textColor =
          isDark ? theme.colorScheme.onSurface : theme.colorScheme.onPrimary;

      return Padding(
        padding: const EdgeInsets.fromLTRB(56, 3, 12, 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 3, right: 2),
              child: Text(
                l10n.chatYouLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.7),
                ),
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: bubbleBg,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(4),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
              ),
              child: Text(
                message.content,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: textColor,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      // ── AI message ── left-aligned, light blue-gray bubble, no border
      final bubbleBg = isDark
          ? theme.colorScheme.surfaceContainerHigh
          : const Color(0xFFe9eef6);
      final senderName = _settingsReady
          ? (_settingsService.multiAISettings.currentProvider?.name ??
              l10n.aiAssistantLabel)
          : l10n.aiAssistantLabel;
      final isInitialLoading =
          message.isLoading && _isLoadingPlaceholderContent(message.content, l10n);

      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 3, 56, 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 3, left: 2),
              child: Text(
                senderName,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.7),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: bubbleBg,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
              ),
              child: isInitialLoading
                  ? const _TypingIndicator()
                  : MarkdownBody(
                      data: message.content,
                      selectable: true,
                      styleSheet:
                          MarkdownStyleSheet.fromTheme(theme).copyWith(
                        p: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                          height: 1.5,
                        ),
                        listBullet: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                        code: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontFamily: 'monospace',
                          backgroundColor: theme
                              .colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.65),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      );
    }
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
    final l10n = AppLocalizations.of(context);
    _syncAgentProgressState(
      isRunning: _agentService.isRunning,
      statusKey: _agentService.currentStatusKey,
      l10n: l10n,
    );
  }

  void _scheduleAgentStatusDismiss() {
    _agentStatusDismissTimer?.cancel();
    _agentStatusDismissTimer = Timer(_agentStatusDismissDuration, () {
      if (!mounted || _lastAgentRunning) {
        return;
      }
      setState(() {
        _showAgentStatusPanel = false;
        _thinkingText = '';
        _isThinking = false;
        _toolProgressItems.clear();
        _isToolInProgress = false;
      });
    });
  }

  String _resolveAgentStatusText(String statusKey, AppLocalizations l10n) {
    return switch (statusKey) {
      '' => '',
      'agentThinking' => l10n.agentThinking,
      'agentSearchingNotes' => l10n.agentSearchingNotes,
      'agentAnalyzingData' => l10n.agentAnalyzingData,
      'agentWebSearching' => l10n.agentWebSearching,
      _ => statusKey.startsWith(AgentService.agentToolCallPrefix)
          ? l10n.agentToolCall(
              statusKey.substring(AgentService.agentToolCallPrefix.length),
            )
          : l10n.agentThinking,
    };
  }

  void _syncAgentProgressState({
    required bool isRunning,
    required String statusKey,
    required AppLocalizations l10n,
  }) {
    if (_lastAgentStatusKey == statusKey && _lastAgentRunning == isRunning) {
      return;
    }
    if (isRunning) {
      _agentStatusDismissTimer?.cancel();
    }

    final nextTools = List<ToolProgressItem>.from(_toolProgressItems);
    var nextThinking = _isThinking;
    var nextThinkingText = _thinkingText;
    var nextToolRunning = _isToolInProgress;
    var nextShowPanel = _showAgentStatusPanel;

    if (!isRunning) {
      for (var i = 0; i < nextTools.length; i++) {
        if (nextTools[i].status == ToolProgressStatus.running) {
          nextTools[i] = nextTools[i].copyWith(
            status: ToolProgressStatus.completed,
            result: l10n.toolExecutionCompleted,
          );
        }
      }
      nextThinking = false;
      nextThinkingText = '';
      nextToolRunning = false;
      nextShowPanel = nextTools.isNotEmpty;
    } else {
      nextShowPanel = true;
      nextThinking = statusKey == 'agentThinking';
      nextThinkingText = nextThinking ? l10n.agentThinking : '';

      if (statusKey.startsWith(AgentService.agentToolCallPrefix)) {
        final toolName =
            statusKey.substring(AgentService.agentToolCallPrefix.length).trim();
        if (toolName.isNotEmpty) {
          if (nextTools.isNotEmpty) {
            final last = nextTools.last;
            if (last.status == ToolProgressStatus.running &&
                last.toolName != toolName) {
              nextTools[nextTools.length - 1] = last.copyWith(
                status: ToolProgressStatus.completed,
                result: l10n.toolExecutionCompleted,
              );
            }
          }

          final hasSameRunning = nextTools.isNotEmpty &&
              nextTools.last.toolName == toolName &&
              nextTools.last.status == ToolProgressStatus.running;
          if (!hasSameRunning) {
            nextTools.add(
              ToolProgressItem(
                toolName: toolName,
                description: l10n.toolExecutionProgress,
                status: ToolProgressStatus.running,
              ),
            );
          }
        }
      }

      nextToolRunning =
          nextTools.any((item) => item.status == ToolProgressStatus.running);
    }

    final currentSig = _toolProgressItems
        .map((item) => '${item.toolName}|${item.status.name}|${item.result}')
        .join('||');
    final nextSig = nextTools
        .map((item) => '${item.toolName}|${item.status.name}|${item.result}')
        .join('||');

    final uiChanged = currentSig != nextSig ||
        nextThinking != _isThinking ||
        nextThinkingText != _thinkingText ||
        nextToolRunning != _isToolInProgress ||
        nextShowPanel != _showAgentStatusPanel;

    if (uiChanged && mounted) {
      setState(() {
        _toolProgressItems
          ..clear()
          ..addAll(nextTools);
        _isThinking = nextThinking;
        _thinkingText = nextThinkingText;
        _isToolInProgress = nextToolRunning;
        _showAgentStatusPanel = nextShowPanel;
        _lastAgentStatusKey = statusKey;
        _lastAgentRunning = isRunning;
      });
    } else {
      _showAgentStatusPanel = nextShowPanel;
      _lastAgentStatusKey = statusKey;
      _lastAgentRunning = isRunning;
    }

    if (!isRunning && nextTools.isNotEmpty) {
      _scheduleAgentStatusDismiss();
    }
  }

  Widget _buildAgentStatusIndicator(ThemeData theme, AppLocalizations l10n) {
    if (!_showAgentStatusPanel && !_lastAgentRunning) {
      return const SizedBox.shrink();
    }

    final statusText = _resolveAgentStatusText(_lastAgentStatusKey, l10n);
    final children = <Widget>[];
    if (_enableThinking &&
        _currentModelSupportsThinking &&
        _thinkingText.isNotEmpty) {
      children.add(
        ThinkingWidget(
          key: const ValueKey('agent_status_thinking_widget'),
          thinkingText: _thinkingText,
          inProgress: _lastAgentRunning && _isThinking,
          accentColor: theme.colorScheme.primary,
        ),
      );
    }
    if (_toolProgressItems.isNotEmpty) {
      children.add(
        ToolProgressPanel(
          key: const ValueKey('agent_status_tool_progress_panel'),
          title: l10n.toolExecutionProgress,
          items: List.unmodifiable(_toolProgressItems),
          inProgress: _isToolInProgress,
          accentColor: theme.colorScheme.primary,
        ),
      );
    }

    if (children.isEmpty && _lastAgentRunning && statusText.isNotEmpty) {
      children.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
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
              Expanded(
                child: Text(
                  statusText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: Padding(
        key: ValueKey<String>(
          'agent-status-$_lastAgentRunning-${_toolProgressItems.length}-${_thinkingText.isNotEmpty}',
        ),
        padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
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
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
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
            BoxShadow(
              color: theme.colorScheme.primary.withValues(
                alpha: _isInputFocused ? 0.1 : 0.03,
              ),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildModeSwitch(theme, l10n),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child:
                  _showSlashCommands && filteredWorkflowDescriptors.isNotEmpty
                      ? Padding(
                          key: const ValueKey('slash_commands_visible'),
                          padding: const EdgeInsets.only(top: 8, bottom: 8),
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
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    focusNode: _inputFocusNode,
                    decoration: InputDecoration(
                      hintText: l10n.aiAssistantInputHint,
                      hintStyle: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.55),
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                    ),
                    maxLines: null,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _handleSubmitted,
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  decoration: BoxDecoration(
                    color: _isLoading
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: Icon(_isLoading ? Icons.stop_rounded : Icons.send_rounded),
                    color: _isLoading
                        ? theme.colorScheme.onError
                        : theme.colorScheme.onPrimary,
                    tooltip: _isLoading ? l10n.stopGenerate : l10n.confirm,
                    onPressed: _isLoading
                        ? _stopGenerating
                        : () => _handleSubmitted(_textController.text),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeSwitch(ThemeData theme, AppLocalizations l10n) {
    final chips = <Widget>[
      ChoiceChip(
        key: const ValueKey('ai_mode_chat_button'),
        label: Text(l10n.aiModeChat),
        selected: _currentMode != AIAssistantPageMode.agent,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => _setMode(_entryConfig.defaultMode),
      ),
      ChoiceChip(
        key: const ValueKey('ai_mode_agent_button'),
        label: Text(l10n.aiModeAgent),
        selected: _currentMode == AIAssistantPageMode.agent,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => _setMode(AIAssistantPageMode.agent),
      ),
      if (_currentModelSupportsThinking)
        FilterChip(
          key: const ValueKey('ai_thinking_toggle'),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _enableThinking ? Icons.psychology : Icons.psychology_outlined,
                size: 16,
                color: _enableThinking
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(l10n.aiThinking),
            ],
          ),
          selected: _enableThinking,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          onSelected: (value) {
            setState(() {
              _enableThinking = value;
            });
          },
          showCheckmark: false,
        ),
    ];

    return Align(
      alignment: Alignment.centerLeft,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 360) {
            return SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: chips.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) => Center(child: chips[index]),
              ),
            );
          }
          return Wrap(
            spacing: 8,
            runSpacing: 6,
            children: chips,
          );
        },
      ),
    );
  }
}

class _AgentSmartResultParseResult {
  const _AgentSmartResultParseResult({
    required this.displayText,
    this.smartResult,
  });

  final String displayText;
  final _AgentSmartResultPayload? smartResult;
}

class _AgentSmartResultPayload {
  const _AgentSmartResultPayload({
    required this.title,
    required this.content,
  });

  final String title;
  final String content;
}

/// 三点弹跳动画，用于 AI 消息加载占位状态
/// 参考 Google AI Edge Gallery 的 MessageBodyLoading 设计
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (_) {
      return AnimationController(
        duration: const Duration(milliseconds: 500),
        vsync: this,
      );
    });
    _animations = _controllers
        .map(
          (c) => Tween<double>(begin: 0.0, end: 1.0).animate(
            CurvedAnimation(parent: c, curve: Curves.easeInOut),
          ),
        )
        .toList();
    _startStaggered();
  }

  Future<void> _startStaggered() async {
    for (var i = 0; i < _controllers.length; i++) {
      await Future.delayed(Duration(milliseconds: i * 160));
      if (mounted) _controllers[i].repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          return AnimatedBuilder(
            animation: _animations[i],
            builder: (context, _) {
              final v = _animations[i].value;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Transform.translate(
                  offset: Offset(0, -5 * v),
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: baseColor.withValues(alpha: 0.35 + 0.55 * v),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
