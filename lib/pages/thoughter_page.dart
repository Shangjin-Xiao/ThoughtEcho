import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../gen_l10n/app_localizations.dart';
import '../models/thoughter_entry.dart';
import '../models/ai_insight_workflow_options.dart';
import '../models/chat_message.dart' as app_chat;
import '../models/chat_message.dart' show MessageState;
import '../models/chat_session.dart';
import '../models/note_tag.dart';
import '../models/quote_model.dart';
import '../models/rich_text_edit.dart';
import '../models/weather_data.dart' show WeatherCodeMapper;
import '../services/agent_service.dart'
    show
        AgentErrorEvent,
        AgentEvent,
        AgentNoteContext,
        AgentReasoningDeltaEvent,
        AgentResponseEvent,
        AgentService,
        AgentTextDeltaEvent,
        AgentThinkingEvent,
        AgentToolCallResultEvent,
        AgentToolCallStartEvent;
import '../services/agent_tool.dart'
    show AgentFailureType, AgentRequestException, AgentResponse;
import '../models/note_proposal_artifact.dart';
import '../services/ai_service.dart';
import '../services/agent_tools/propose_note_edit_tool.dart';
import '../services/chat_session_service.dart';
import '../services/database_service.dart';
import '../services/location_service.dart';
import '../services/settings_service.dart';
import '../services/weather_service.dart';
import '../utils/ai_smart_result_utils.dart';
import '../utils/agent_history_builder.dart';
import '../utils/app_logger.dart';
import '../utils/note_proposal_applier.dart';
import '../utils/quill_delta_builder.dart';
import '../utils/quill_structured_edit.dart';
import '../utils/string_utils.dart';
import '../utils/time_utils.dart';
import '../widgets/ai/agent_memory_notice.dart';
import '../widgets/ai/ai_workflow_cards.dart';
import '../widgets/ai/experimental_badge.dart';
import '../widgets/ai/note_proposal_card.dart';
import '../widgets/ai/thinking_widget.dart';
import '../widgets/ai/tool_progress_panel.dart';
import 'thoughter/session_history_page.dart';
import '../widgets/add_note_dialog.dart';
import '../widgets/add_note_dialog_parts.dart' show TagSelectionSection;
import 'note_full_editor_page.dart';
import '../theme/theme_style.dart';

part 'thoughter/thoughter_session.dart';
part 'thoughter/thoughter_workflow.dart';
part 'thoughter/thoughter_agent.dart';
part 'thoughter/thoughter_quick_edit.dart';
part 'thoughter/thoughter_ui.dart';

class ThoughterPage extends StatefulWidget {
  final Quote? quote;
  final String? initialQuestion;
  final ChatSession? session;
  final ThoughterEntrySource? entrySource;
  final String? exploreGuideSummary;

  /// 开场白：作为 Thoughter 的第一句显示，并且**进入模型上下文**。
  ///
  /// 和 [exploreGuideSummary] 的区别：后者是 `includedInContext: false` 的
  /// 系统提示，只给用户看，模型收不到。当调用方手上已经有一段现成的正文
  /// （每日提示、周期洞察）想让对话从它开始时，用这个参数——既不用再花一次
  /// 生成，模型也确实知道开场说了什么。
  final String? openingMessage;

  const ThoughterPage({
    super.key,
    this.quote,
    this.initialQuestion,
    this.session,
    this.entrySource,
    this.exploreGuideSummary,
    this.openingMessage,
  });

  @override
  State<ThoughterPage> createState() => _ThoughterPageState();
}

class _ThoughterPageState extends State<ThoughterPage> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final List<app_chat.ChatMessage> _messages = [];
  final Uuid _uuid = const Uuid();

  bool _isLoading = false;
  String? _currentSessionId;

  /// 会话建立前就已产生、但需要落库的消息（开场白、卡片消息）。
  final List<app_chat.ChatMessage> _pendingPersistMessages = [];
  StreamSubscription<String>? _streamSubscription;
  late ChatSessionService _chatSessionService;
  late AgentService _agentService;
  late AIService _aiService;
  late SettingsService _settingsService;
  bool _settingsReady = false;
  late ThoughterPageMode _currentMode;
  String _selectedInsightType = 'comprehensive';
  String _selectedInsightStyle = 'professional';

  bool _enableThinking = true; // 是否启用思考模式（仅支持的模型显示）

  bool _isInputFocused = false;

  /// 标签表的 id → NoteTag 映射。提案卡里的 artifact 只带 id 和名字，
  /// 图标要从这里取——和笔记卡片用的是同一份数据（见 quote_item_widget 的 tagMap）。
  Map<String, NoteTag> _tagMap = const <String, NoteTag>{};
  StreamSubscription<List<NoteTag>>? _tagSubscription;

  /// 上一次布局时消息区的可用高度，用于识别键盘/输入框正在挤压列表
  /// （见 _onMessageViewportHeightChanged）。
  double _lastMessageViewportHeight = 0;
  bool _agentListenerAttached = false;
  int _agentRequestGeneration = 0;
  Timer? _agentStatusDismissTimer;
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
    if (id == null) {
      _cancelStreamUpdate();
      return;
    }
    final content = _pendingContent;
    final isLoading = _pendingIsLoading;
    final metaJson = _pendingMetaJson;
    final state = _pendingState;
    final thinkingChunks = _pendingThinkingChunks;
    // 先清空待写内容再落盘：_updateMessage 会把还没落地的节流写作废，
    // 而这次 flush 正是在落地它，不能被自己清掉又当成"还没写"。
    _cancelStreamUpdate();
    _updateMessage(
      id,
      content,
      isLoading: isLoading,
      metaJson: metaJson,
      state: state,
      thinkingChunks: thinkingChunks,
    );
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
    final items = _pendingToolItems;
    if (msgId == null || items == null) {
      _cancelToolProgressUpdate();
      return;
    }
    final inProgress = _pendingToolProgressInProgress;
    final thinkingText = _pendingToolProgressThinkingText;
    // 同 _flushStreamUpdate：落地前先摘掉待写状态。
    _cancelToolProgressUpdate();
    _updateToolProgressMessage(
      msgId,
      items,
      inProgress: inProgress,
      thinkingText: thinkingText,
    );
  }

  void _cancelToolProgressUpdate() {
    _toolProgressThrottleTimer?.cancel();
    _toolProgressThrottleTimer = null;
    _pendingToolProgressMsgId = null;
  }
  // ==================== 性能优化结束 ====================

  // ==================== 性能优化：_scrollToBottom 节流 ====================
  Timer? _scrollThrottleTimer;
  bool _autoScrollEnabled = true;
  bool _showScrollToBottom = false;
  // ==================== 性能优化结束 ====================

  // ==================== 性能优化：MarkdownStyleSheet 缓存 ====================
  MarkdownStyleSheet? _cachedMarkdownStyleSheet;
  ThemeData? _cachedMarkdownTheme;
  // ==================== 性能优化结束 ====================

  ThoughterEntrySource get _entrySource =>
      widget.entrySource ??
      (widget.quote != null
          ? ThoughterEntrySource.note
          : ThoughterEntrySource.explore);

  ThoughterEntryConfig get _entryConfig =>
      ThoughterEntryConfig(source: _entrySource);

  bool get _hasBoundNote => widget.quote != null;
  String? get _boundNoteId {
    final id = widget.quote?.id?.trim();
    if (id == null || id.isEmpty) {
      return null;
    }
    return id;
  }

  bool get _isAgentMode => _currentMode == ThoughterPageMode.agent;

  /// 检查当前模型是否支持思考/推理模式
  bool get _currentModelSupportsThinking {
    if (!_settingsReady) return false;
    final provider = _settingsService.multiAISettings.currentProvider;
    return provider?.supportsThinking ?? false;
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

  /// 仅供测试：读取当前消息列表，用于断言开场白是否进入了上下文。
  @visibleForTesting
  List<app_chat.ChatMessage> get debugMessagesForTest =>
      List.unmodifiable(_messages);

  void _appendMessage(app_chat.ChatMessage message, {bool persist = false}) {
    _setState(() {
      _messages.add(message);
    });
    if (persist) {
      if (_currentSessionId != null) {
        unawaited(_chatSessionService.addMessage(_currentSessionId!, message));
      } else {
        // 会话要到首条用户消息才建。挂起等 _ensureSessionCreated 补写，
        // 否则开场白这类先于会话出现的消息会被静默丢掉。
        _pendingPersistMessages.add(message);
      }
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
    // 直接写覆盖节流队列里还没落地的那次更新。否则一次「定稿」写完 isLoading=false
    // 之后，50ms 内攒下的旧快照会晚一步落地，把 isLoading 又推回 true——正文末尾
    // 的流式光标从此不灭，操作行也不出现。
    _cancelStreamUpdate();
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
      // 这里不碰 _isLoading：单条消息定稿 ≠ 这一轮结束。Agent 一轮里可能定稿
      // 多条消息（旁白、工具面板、最终回答），任何一条把整页判成「不在生成」，
      // 等待光标就会灭掉、停止键变回发送，而后面还有内容要等。一轮的开关归
      // 发起方管：_finishLoading。
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
    // 正文按 bodyLarge 排，长回复才读得下去。标题跟着往上抬一档但收窄跨度：
    // fromTheme 的 h1/h2 是 headline 系列，配 14 号正文时大得像海报标题，
    // 而 h3 只有 16，和正文几乎分不开。
    final body = theme.textTheme.bodyLarge?.copyWith(
      color: bubbleTextColor,
      height: 1.65,
    );
    TextStyle heading(double size) =>
        (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
          color: bubbleTextColor,
          fontSize: size,
          fontWeight: FontWeight.w600,
          height: 1.35,
        );
    _cachedMarkdownStyleSheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: body,
      h1: heading(22),
      h2: heading(20),
      h3: heading(18),
      h4: heading(17),
      h5: heading(16),
      h6: heading(16),
      blockquote: body?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      listBullet: body,
      strong: body?.copyWith(fontWeight: FontWeight.w600),
      code: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontFamily: 'monospace',
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
      ),
      codeblockDecoration: BoxDecoration(
        // 回复正文已经直接铺在 surface 上，代码块要用更高一级的容器色
        // 才分得出层次；surfaceContainerLow 在浅色下几乎和背景同色。
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
    );
    return _cachedMarkdownStyleSheet!;
  }

  /// Stop the current generation - cancels the stream subscription
  void _stopGenerating() {
    _agentRequestGeneration++;
    _agentService.requestStop();
    _agentEventSubscription?.cancel();
    _agentEventSubscription = null;
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _cancelStreamUpdate();
    _cancelToolProgressUpdate();
    _agentStatusDismissTimer?.cancel();
    _finishLoading();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).agentErrorCancelled),
        ),
      );
    }
  }

  void _onScrollPositionChanged() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final distanceFromBottom = position.maxScrollExtent - position.pixels;
    if (distanceFromBottom <= 80) {
      _setAutoScrollEnabled(true);
    } else if (!_autoScrollEnabled && !_showScrollToBottom) {
      _setState(() {
        _showScrollToBottom = true;
      });
    }
  }

  void _setAutoScrollEnabled(bool enabled) {
    if (_autoScrollEnabled == enabled &&
        _showScrollToBottom == (!enabled && _isLoading)) {
      return;
    }
    _setState(() {
      _autoScrollEnabled = enabled;
      _showScrollToBottom = !enabled && _isLoading;
    });
  }

  void _resumeAutoScroll() {
    _setAutoScrollEnabled(true);
    _scrollToBottom(force: true);
  }

  void _scrollToBottom({bool force = false, bool bypassThrottle = false}) {
    if (!_autoScrollEnabled && !force) {
      if (_isLoading && !_showScrollToBottom) {
        _setState(() {
          _showScrollToBottom = true;
        });
      }
      return;
    }
    if (!force &&
        !bypassThrottle &&
        (_scrollThrottleTimer?.isActive ?? false)) {
      return;
    }
    if (force || bypassThrottle) {
      _scrollThrottleTimer?.cancel();
    } else {
      _scrollThrottleTimer = Timer(const Duration(milliseconds: 200), () {});
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      void animateToCurrentBottom({int remainingPasses = 1}) {
        if (!_scrollController.hasClients) return;
        unawaited(
          _scrollController
              .animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          )
              .then((_) {
            if (!mounted || !_autoScrollEnabled || remainingPasses <= 1) {
              return;
            }
            // A lazily built result card can increase maxScrollExtent only
            // after the first animation exposes it. Follow the moving bottom
            // until the newly appended card has participated in layout.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              animateToCurrentBottom(remainingPasses: remainingPasses - 1);
            });
          }),
        );
      }

      if (force) {
        _setState(() {
          _autoScrollEnabled = true;
          _showScrollToBottom = false;
        });
        // Hiding the bottom button and retaining the keyboard can change the
        // viewport. Read maxScrollExtent after that layout has settled.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent,
            );
          }
        });
      } else {
        animateToCurrentBottom(remainingPasses: bypassThrottle ? 3 : 1);
      }
    });
  }
}
