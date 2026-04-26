import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import '../models/weather_data.dart' show WeatherCodeMapper;
import '../services/agent_service.dart'
    show
        AgentErrorEvent,
        AgentEvent,
        AgentResponseEvent,
        AgentService,
        AgentTextDeltaEvent,
        AgentThinkingEvent,
        AgentToolCallResultEvent,
        AgentToolCallStartEvent;
import '../services/agent_tool.dart' show AgentResponse;
import '../services/ai_service.dart';
import '../services/chat_session_service.dart';
import '../services/database_service.dart';
import '../services/location_service.dart';
import '../services/settings_service.dart';
import '../services/weather_service.dart';
import '../utils/ai_command_helpers.dart';
import '../utils/app_logger.dart';
import '../utils/string_utils.dart';
import '../utils/time_utils.dart';
import '../widgets/ai/ai_workflow_cards.dart';
import '../widgets/ai/smart_result_card.dart';
import '../widgets/ai/thinking_widget.dart';
import '../widgets/ai/tool_progress_panel.dart';
import '../widgets/session_history_sheet.dart';
import '../widgets/source_analysis_result_dialog.dart';
import '../widgets/add_note_dialog.dart';
import 'note_full_editor_page.dart';

part 'ai_assistant/ai_assistant_page_session.dart';
part 'ai_assistant/ai_assistant_page_workflow.dart';
part 'ai_assistant/ai_assistant_page_agent.dart';
part 'ai_assistant/ai_assistant_page_ui.dart';

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

  bool _isInputFocused = false;
  bool _agentListenerAttached = false;
  Timer? _agentStatusDismissTimer;
  final List<PlatformFile> _selectedMediaFiles = [];
  StreamSubscription<AgentEvent>? _agentEventSubscription;

  // ==================== 性能优化：流式 UI 更新节流 ====================
  /// 限制流式文本 UI 刷新频率（每 50ms 最多一次），避免逐字符 setState 导致全页重建
  Timer? _streamThrottleTimer;
  String? _pendingUpdateId;
  String _pendingContent = '';
  bool _pendingIsLoading = false;
  String? _pendingMetaJson;
  app_chat.MessageState? _pendingState;
  List<String>? _pendingThinkingChunks;

  void _scheduleStreamUpdate(
    String id,
    String content, {
    required bool isLoading,
    String? metaJson,
    app_chat.MessageState? state,
    List<String>? thinkingChunks,
  }) {
    _pendingUpdateId = id;
    _pendingContent = content;
    _pendingIsLoading = isLoading;
    _pendingMetaJson = metaJson;
    _pendingState = state;
    _pendingThinkingChunks = thinkingChunks;

    if (_streamThrottleTimer?.isActive ?? false) return;

    _streamThrottleTimer = Timer(const Duration(milliseconds: 50), () {
      _flushStreamUpdate();
    });
  }

  void _flushStreamUpdate() {
    final id = _pendingUpdateId;
    if (id == null) return;
    _updateMessage(
      id,
      _pendingContent,
      isLoading: _pendingIsLoading,
      metaJson: _pendingMetaJson,
      state: _pendingState,
      thinkingChunks: _pendingThinkingChunks,
    );
    _streamThrottleTimer = null;
  }

  void _cancelStreamUpdate() {
    _streamThrottleTimer?.cancel();
    _streamThrottleTimer = null;
    _pendingUpdateId = null;
  }
  // ==================== 性能优化结束 ====================

  // ==================== 性能优化：Agent 工具进度更新节流 ====================
  Timer? _toolProgressThrottleTimer;
  String? _pendingToolProgressMsgId;
  List<ToolProgressItem>? _pendingToolItems;
  bool _pendingToolProgressInProgress = false;
  String? _pendingToolProgressThinkingText;

  void _scheduleToolProgressUpdate(
    String msgId,
    List<ToolProgressItem> items, {
    required bool inProgress,
    String? thinkingText,
  }) {
    _pendingToolProgressMsgId = msgId;
    _pendingToolItems = items;
    _pendingToolProgressInProgress = inProgress;
    _pendingToolProgressThinkingText = thinkingText;

    if (_toolProgressThrottleTimer?.isActive ?? false) return;

    _toolProgressThrottleTimer = Timer(const Duration(milliseconds: 50), () {
      _flushToolProgressUpdate();
    });
  }

  void _flushToolProgressUpdate() {
    final msgId = _pendingToolProgressMsgId;
    if (msgId == null || _pendingToolItems == null) return;
    _updateToolProgressMessage(
      msgId,
      _pendingToolItems!,
      inProgress: _pendingToolProgressInProgress,
      thinkingText: _pendingToolProgressThinkingText,
    );
    _toolProgressThrottleTimer = null;
  }

  void _cancelToolProgressUpdate() {
    _toolProgressThrottleTimer?.cancel();
    _toolProgressThrottleTimer = null;
    _pendingToolProgressMsgId = null;
  }
  // ==================== 性能优化结束 ====================

  // ==================== 性能优化：_scrollToBottom 节流 ====================
  Timer? _scrollThrottleTimer;
  // ==================== 性能优化结束 ====================

  // ==================== 性能优化：MarkdownStyleSheet 缓存 ====================
  MarkdownStyleSheet? _cachedMarkdownStyleSheet;
  ThemeData? _cachedMarkdownTheme;
  // ==================== 性能优化结束 ====================

  // ==================== 性能优化：WorkflowDescriptors 缓存 ====================
  List<AIWorkflowDescriptor>? _cachedWorkflowDescriptors;
  // ==================== 性能优化结束 ====================

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
    return _cachedWorkflowDescriptors ??= [
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
    _initStateImpl();
  }

  @override
  void dispose() {
    _disposeImpl();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _buildPage(context);
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
    _setState(() {
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
    List<String>? thinkingChunks,
  }) {
    _setState(() {
      final idx = _messages.indexWhere((m) => m.id == id);
      if (idx == -1) return;
      final oldMsg = _messages[idx];
      final updatedMsg = oldMsg.copyWith(
        content: newContent,
        isLoading: isLoading,
        metaJson: metaJson,
        state: state ?? oldMsg.state,
        thinkingChunks: thinkingChunks,
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
    _setState(() {
      _isLoading = false;
    });
  }

  void _setState(VoidCallback fn) {
    setState(fn);
  }

  /// 性能优化：缓存 MarkdownStyleSheet，避免每帧重建
  MarkdownStyleSheet _getMarkdownStyleSheet(
    ThemeData theme,
    Color bubbleTextColor,
  ) {
    if (_cachedMarkdownStyleSheet != null && _cachedMarkdownTheme == theme) {
      return _cachedMarkdownStyleSheet!;
    }
    _cachedMarkdownTheme = theme;
    _cachedMarkdownStyleSheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
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
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
      ),
      codeblockDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
    );
    return _cachedMarkdownStyleSheet!;
  }

  /// Stop the current generation - cancels the stream subscription
  void _stopGenerating() {
    _agentService.requestStop();
    _agentEventSubscription?.cancel();
    _agentEventSubscription = null;
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _agentStatusDismissTimer?.cancel();
    _finishLoading();
  }

  void _scrollToBottom() {
    if (_scrollThrottleTimer?.isActive ?? false) return;
    _scrollThrottleTimer = Timer(const Duration(milliseconds: 200), () {});

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
}
