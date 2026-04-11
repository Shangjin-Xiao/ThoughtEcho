import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../gen_l10n/app_localizations.dart';
import '../models/ai_assistant_entry.dart';
import '../models/ai_insight_workflow_options.dart';
import '../models/ai_workflow_descriptor.dart';
import '../models/chat_message.dart' as app_chat;
import '../models/chat_message.dart' show MessageState;
import '../models/chat_session.dart';
import '../models/quote_model.dart';
import '../services/agent_service.dart';
import '../services/ai_service.dart';
import '../services/chat_session_service.dart';
import '../services/database_service.dart';
import '../services/settings_service.dart';
import '../utils/ai_command_helpers.dart';
import '../utils/app_logger.dart';
import '../utils/string_utils.dart';
import '../widgets/ai/ai_workflow_cards.dart';
import '../widgets/ai/assistant_agent_status_panel.dart';
import '../widgets/ai/assistant_input_panel.dart';
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
  StreamSubscription<dynamic>? _agentEventsSubscription;
  late ChatSessionService _chatSessionService;
  late AgentService _agentService;
  late AIService _aiService;
  late SettingsService _settingsService;
  bool _settingsReady = false;
  late AIAssistantPageMode _currentMode;
  String _selectedInsightType = 'comprehensive';
  String _selectedInsightStyle = 'professional';
  bool _showSlashCommands = false; // Only show when user types /

  // 防止流式传输时UI过度频繁更新（流式防抖）
  Timer? _streamUpdateDebounce;
  String? _pendingStreamingMessageId;
  String _accumulatedStreamContent = '';
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
  Timer? _agentStatusDismissTimer;
  final List<PlatformFile> _selectedMediaFiles = [];
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
      AIWorkflowDescriptor(
        id: AIWorkflowId.webFetch,
        command: '/web',
        displayName: 'Web Fetch',
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
    _textController.addListener(_onTextChanged);
    _inputFocusNode.addListener(_onInputFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initServicesAndLoad());
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

  /// 流式传输防抖更新：防止每个chunk都触发setState()导致UI线程过载
  /// 采用150ms防抖延迟，确保流畅的实时显示效果同时减轻UI压力
  void _debouncedStreamUpdate({
    required String messageId,
    required String content,
    bool isLoading = true,
    MessageState state = MessageState.responding,
  }) {
    _pendingStreamingMessageId = messageId;
    _accumulatedStreamContent = content;

    _streamUpdateDebounce?.cancel();
    _streamUpdateDebounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) {
        _updateMessage(
          messageId,
          _accumulatedStreamContent,
          isLoading: isLoading,
          state: state,
        );
      }
      _streamUpdateDebounce = null;
    });
  }

  /// 立即执行任何待处理的流更新（用于流完成时）
  void _flushPendingStreamUpdate() {
    if (_streamUpdateDebounce != null && _pendingStreamingMessageId != null) {
      _streamUpdateDebounce?.cancel();
      if (mounted) {
        _updateMessage(
          _pendingStreamingMessageId!,
          _accumulatedStreamContent,
          isLoading: false,
          state: MessageState.complete,
        );
      }
      _streamUpdateDebounce = null;
      _pendingStreamingMessageId = null;
      _accumulatedStreamContent = '';
    }
  }

  @override
  void dispose() {
    _agentStatusDismissTimer?.cancel();
    _streamUpdateDebounce?.cancel();
    if (_agentListenerAttached) {
      _agentService.removeListener(_onAgentServiceChanged);
    }
    _streamSubscription?.cancel();
    _agentEventsSubscription?.cancel();
    _inputFocusNode.removeListener(_onInputFocusChanged);
    _textController.removeListener(_onTextChanged);
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

    // 订阅 Agent 事件流，用于显示工具调用进度
    _agentEventsSubscription?.cancel();
    _agentEventsSubscription = _agentService.events.listen(_onAgentEvent);

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

    if (_hasBoundNote) {
      final String welcomeContent = l10n.aiAssistantWelcome(_getQuotePreview());
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

    if (!_hasBoundNote &&
        widget.exploreGuideSummary?.trim().isNotEmpty == true) {
      final exploreWelcome = app_chat.ChatMessage(
        id: _uuid.v4(),
        content:
            l10n.aiAssistantExploreWelcome(widget.exploreGuideSummary!.trim()),
        isUser: false,
        role: 'system',
        timestamp: DateTime.now(),
        includedInContext: false,
      );
      _appendMessage(exploreWelcome, persist: true);
      return;
    }

    // Generate dynamic insight if in explore mode without explicit guide
    if (!_hasBoundNote &&
        (widget.exploreGuideSummary?.trim().isEmpty ?? true) &&
        _entrySource == AIAssistantEntrySource.explore) {
      _generateAndShowDynamicInsight();
    }
  }

  /// Generate and display a dynamic insight based on current data
  Future<void> _generateAndShowDynamicInsight() async {
    final l10n = AppLocalizations.of(context);
    final databaseService = _tryGetDatabaseService();
    if (databaseService == null) return;

    try {
      final quotes = await databaseService.getUserQuotes();
      if (quotes.isEmpty) return;

      // Calculate simple stats
      final count = quotes.length;
      final recentCount = quotes.where((q) {
        try {
          final qDate = DateTime.parse(q.date);
          return DateTime.now().difference(qDate).inDays <= 7;
        } catch (e) {
          return false;
        }
      }).length;

      final insightSummary = '$count · ${l10n.thisWeek}: $recentCount';
      final insightText = l10n.aiAssistantExploreWelcome(insightSummary);

      if (!mounted) return;

      final insightMsg = app_chat.ChatMessage(
        id: _uuid.v4(),
        content: insightText,
        isUser: false,
        role: 'system',
        timestamp: DateTime.now(),
        includedInContext: false,
      );
      _appendMessage(insightMsg, persist: false);
    } catch (e) {
      AppLogger.d('Failed to generate dynamic insight: $e');
    }
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
      _selectedMediaFiles.clear();
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
    final history = _messages
        .where((m) => m.includedInContext && m.id != aiMsgId && !m.isLoading)
        .toList();

    _streamSubscription?.cancel();

    // 使用流式订阅，支持实时更新 — 每个字符立即显示
    _streamSubscription = _aiService
        .streamAskQuestion(widget.quote!, text, history: history)
        .listen(
      (chunk) {
        // 累积内容
        fullResponse += chunk;

        // 使用防抖更新，而不是直接setState()
        _debouncedStreamUpdate(
          messageId: aiMsgId,
          content: fullResponse,
          isLoading: true,
          state: MessageState.responding,
        );
      },
      onDone: () {
        // 刷新任何待处理的更新并标记为完成
        _flushPendingStreamUpdate();
        _updateMessage(
          aiMsgId,
          fullResponse.isNotEmpty ? fullResponse : l10n.aiMisunderstoodQuestion,
          isLoading: false,
          state: MessageState.complete,
        );
      },
      onError: (error) {
        // 错误处理：更新状态为error
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
    final history = _messages
        .where((m) => m.includedInContext && m.id != aiMsgId && !m.isLoading)
        .toList();

    _streamSubscription?.cancel();

    // 使用流式订阅，支持实时更新 — 每个字符立即显示
    _streamSubscription = _aiService
        .streamGeneralConversation(
      text,
      history: history,
      systemContext: widget.exploreGuideSummary,
    )
        .listen(
      (chunk) {
        // 累积内容
        fullResponse += chunk;

        // 使用防抖更新，而不是直接setState()
        _debouncedStreamUpdate(
          messageId: aiMsgId,
          content: fullResponse,
          isLoading: true,
          state: MessageState.responding,
        );
      },
      onDone: () {
        // 刷新任何待处理的更新并标记为完成
        _flushPendingStreamUpdate();
        _updateMessage(
          aiMsgId,
          fullResponse.isNotEmpty ? fullResponse : l10n.aiMisunderstoodQuestion,
          isLoading: false,
          state: MessageState.complete,
        );
      },
      onError: (error) {
        // 错误处理：更新状态为error
        _updateMessage(
          aiMsgId,
          l10n.aiResponseError(error.toString()),
          isLoading: false,
          state: MessageState.error,
        );
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
    app_chat.MessageState? state,
  }) {
    setState(() {
      final idx = _messages.indexWhere((m) => m.id == id);
      if (idx == -1) return;
      final oldMsg = _messages[idx];
      final updatedMsg = oldMsg.copyWith(
        content: newContent,
        isLoading: isLoading,
        metaJson: metaJson,
        state: state ?? oldMsg.state,
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
        setState(() {
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
    setState(() {
      _selectedMediaFiles.removeAt(index);
    });
  }

  void _toggleModeFromInput() {
    final allowedModes = [
      if (_entryConfig.allowsMode(_entryConfig.defaultMode))
        _entryConfig.defaultMode,
      if (_entryConfig.allowsMode(AIAssistantPageMode.agent))
        AIAssistantPageMode.agent,
    ];
    if (allowedModes.length < 2) {
      return;
    }
    final nextMode =
        _isAgentMode ? _entryConfig.defaultMode : AIAssistantPageMode.agent;
    if (_entryConfig.allowsMode(nextMode)) {
      unawaited(_setMode(nextMode));
    }
  }

  void _toggleThinkingFromInput() {
    setState(() {
      _enableThinking = !_enableThinking;
    });
  }

  void _sendOrStopFromInput() {
    if (_isLoading) {
      _stopGenerating();
      return;
    }
    if (_textController.text.trim().isNotEmpty) {
      unawaited(_handleSubmitted(_textController.text));
    }
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
            onPressed: _isLoading ? null : _showSessionHistory,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_hasBoundNote) _buildNoteContextBanner(theme),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return _buildMessageBubble(_messages[index], theme, l10n);
              },
            ),
          ),
          if (_isAgentMode) _buildAgentStatusIndicator(l10n),
          _buildInputArea(l10n),
        ],
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
    // Material 3颜色优化：使用主题colorScheme替代硬编码色值
    // 用户气泡：使用primary color
    // Agent气泡：使用surfaceContainerHigh
    final userBubbleColor = theme.colorScheme.primary;
    final agentBubbleColor = theme.colorScheme.surfaceContainerHigh;
    final bubbleColor = isUser ? userBubbleColor : agentBubbleColor;

    final bubbleTextColor = isUser ? Colors.white : theme.colorScheme.onSurface;

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
                  _formatTime(message.timestamp),
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

  /// 格式化时间显示
  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (messageDay == today) {
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else if (messageDay == today.subtract(const Duration(days: 1))) {
      return '昨天 ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else {
      return '${messageDay.month.toString().padLeft(2, '0')}-${messageDay.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
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

  /// 处理 Agent 事件流中的工具调用事件
  void _onAgentEvent(dynamic event) {
    if (!mounted) return;

    // 处理工具调用开始事件
    if (event is AgentToolCallStartEvent) {
      setState(() {
        // 检查是否已存在相同的工具条目
        final existingIndex = _toolProgressItems
            .indexWhere((item) => item.toolName == event.toolName);

        if (existingIndex >= 0) {
          // 如果存在且已完成，则创建新条目
          if (_toolProgressItems[existingIndex].status ==
              ToolProgressStatus.completed) {
            _toolProgressItems.add(
              ToolProgressItem(
                toolName: event.toolName,
                status: ToolProgressStatus.running,
              ),
            );
          }
          // 否则保持原样（已在运行中）
        } else {
          // 新工具条目
          _toolProgressItems.add(
            ToolProgressItem(
              toolName: event.toolName,
              status: ToolProgressStatus.running,
            ),
          );
        }
      });
      return;
    }

    // 处理工具调用完成事件
    if (event is AgentToolCallResultEvent) {
      setState(() {
        final index = _toolProgressItems.indexWhere((item) =>
            item.toolName == event.toolName &&
            item.status == ToolProgressStatus.running);

        if (index >= 0) {
          _toolProgressItems[index] = _toolProgressItems[index].copyWith(
            status: event.isError
                ? ToolProgressStatus.failed
                : ToolProgressStatus.completed,
            result: event.result,
          );
        }
      });
      return;
    }
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
      // Intentionally not dismissing the status panel automatically so users can
      // see the tool calling process (Agent execution path) after generation completes.
      // _scheduleAgentStatusDismiss();
    }
  }

  Widget _buildAgentStatusIndicator(AppLocalizations l10n) {
    final statusText = _resolveAgentStatusText(_lastAgentStatusKey, l10n);
    return AIAssistantAgentStatusPanel(
      showPanel: _showAgentStatusPanel,
      lastAgentRunning: _lastAgentRunning,
      enableThinking: _enableThinking,
      currentModelSupportsThinking: _currentModelSupportsThinking,
      thinkingText: _thinkingText,
      isThinking: _isThinking,
      toolProgressItems: _toolProgressItems,
      isToolInProgress: _isToolInProgress,
      statusText: statusText,
    );
  }

  Widget _buildInputArea(AppLocalizations l10n) {
    final workflowDescriptors = _buildWorkflowDescriptors(l10n);
    final inputText = _textController.text.toLowerCase();
    final filteredWorkflowDescriptors = workflowDescriptors
        .where(
          (descriptor) =>
              inputText.isEmpty ||
              descriptor.command.toLowerCase().startsWith(inputText),
        )
        .toList(growable: false);
    return AIAssistantInputPanel(
      textController: _textController,
      focusNode: _inputFocusNode,
      isLoading: _isLoading,
      isInputFocused: _isInputFocused,
      showSlashCommands: _showSlashCommands,
      filteredWorkflowDescriptors: filteredWorkflowDescriptors,
      selectedMediaFiles: _selectedMediaFiles,
      isAgentMode: _isAgentMode,
      currentModelSupportsThinking: _currentModelSupportsThinking,
      enableThinking: _enableThinking,
      onPickAndAttachMedia: _pickAndAttachMedia,
      onToggleMode: _toggleModeFromInput,
      onToggleThinking: _toggleThinkingFromInput,
      onSendOrStop: _sendOrStopFromInput,
      onSubmitText: (text) => unawaited(_handleSubmitted(text)),
      onRemoveMediaFile: _removeMediaFile,
      onSubmitWorkflowCommand: (command) =>
          unawaited(_handleSubmitted(command)),
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
