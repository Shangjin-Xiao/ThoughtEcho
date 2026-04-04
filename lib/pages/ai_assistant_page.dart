import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../gen_l10n/app_localizations.dart';
import '../models/chat_message.dart' as app_chat;
import '../models/chat_session.dart';
import '../models/quote_model.dart';
import '../services/agent_service.dart';
import '../services/ai_service.dart';
import '../services/chat_session_service.dart';
import '../utils/app_logger.dart';
import '../utils/string_utils.dart';
import '../widgets/ai/smart_result_card.dart';
import '../widgets/session_history_sheet.dart';

class AIAssistantPage extends StatefulWidget {
  final Quote? quote;
  final String? initialQuestion;
  final ChatSession? session;

  const AIAssistantPage({
    super.key,
    this.quote,
    this.initialQuestion,
    this.session,
  });

  @override
  State<AIAssistantPage> createState() => _AIAssistantPageState();
}

class _AIAssistantPageState extends State<AIAssistantPage> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<app_chat.ChatMessage> _messages = [];
  bool _isLoading = false;
  String? _currentSessionId;
  StreamSubscription<String>? _streamSubscription;
  late ChatSessionService _chatSessionService;
  late AgentService _agentService;
  late AIService _aiService;

  bool get _isNoteMode => widget.quote != null;

  @override
  void initState() {
    super.initState();
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

    if (widget.session != null) {
      await _loadSession(widget.session!.id);
    } else if (_isNoteMode && widget.quote!.id != null) {
      try {
        final session = await _chatSessionService.getLatestSessionForNote(widget.quote!.id!);
        if (session != null) {
          await _loadSession(session.id);
        } else {
          await _createNewSession();
          _addWelcomeMessage();
        }
      } catch (e) {
        AppLogger.e('加载会话失败', error: e);
      }
    } else {
      await _createNewSession();
      _addWelcomeMessage();
    }

    if (widget.initialQuestion?.isNotEmpty == true) {
      _handleSubmitted(widget.initialQuestion!);
    }
  }

  Future<void> _createNewSession() async {
    final session = await _chatSessionService.createSession(
      sessionType: _isNoteMode ? 'note' : 'agent',
      noteId: widget.quote?.id ?? '',
      title: _isNoteMode ? _getQuotePreview() : 'New Chat',
    );
    _currentSessionId = session.id;
  }

  Future<void> _loadSession(String sessionId) async {
    _currentSessionId = sessionId;
    final messages = await _chatSessionService.getMessages(sessionId);
    if (mounted) {
      setState(() {
        _messages.clear();
        _messages.addAll(messages);
      });
      _scrollToBottom();
    }
  }

  String _getQuotePreview() {
    if (!_isNoteMode) return '';
    final content = StringUtils.removeObjectReplacementChar(widget.quote!.content);
    return content.length <= 100 ? content : '${content.substring(0, 100)}...';
  }

  void _addWelcomeMessage() {
    final l10n = AppLocalizations.of(context);
    final String welcomeContent = _isNoteMode
        ? l10n.aiAssistantWelcome(_getQuotePreview())
        : '你好！我是你的 AI 助手。你可以直接向我提问，或者输入 / 查看可用命令。'; // Dynamic greeting placeholder

    final welcomeMsg = app_chat.ChatMessage(
      id: const Uuid().v4(),
      content: welcomeContent,
      isUser: false,
      role: 'system',
      timestamp: DateTime.now(),
      includedInContext: false,
    );

    setState(() {
      _messages.add(welcomeMsg);
    });

    if (_currentSessionId != null) {
      _chatSessionService.addMessage(_currentSessionId!, welcomeMsg);
    }
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
        noteId: widget.quote?.id,
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
    if (text.trim().isEmpty || _isLoading) return;

    _textController.clear();

    final userMsg = app_chat.ChatMessage(
      id: const Uuid().v4(),
      content: text,
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

    if (_isNoteMode && (text == '/润色' || text == '/polish')) {
      await _handlePolishCommand();
      return;
    }
    if (_isNoteMode && (text == '/续写' || text == '/continue')) {
      await _handleContinueCommand();
      return;
    }

    if (_isNoteMode) {
      await _askNote(text);
    } else {
      await _askAgent(text);
    }
  }

  Future<void> _handlePolishCommand() async {
    final l10n = AppLocalizations.of(context);
    final aiMsgId = const Uuid().v4();
    final aiMsg = app_chat.ChatMessage(
      id: aiMsgId,
      content: l10n.polishingText ?? '正在润色...',
      isUser: false,
      role: 'assistant',
      timestamp: DateTime.now(),
      isLoading: true,
    );

    setState(() {
      _messages.add(aiMsg);
    });

    try {
      String fullResponse = '';
      final stream = _aiService.streamPolishText(widget.quote!.content);
      
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
            metaJson: jsonEncode({
              'type': 'smart_result',
              'command': '/润色',
              'title': l10n.polishResult ?? '润色结果',
            }),
          );
        },
        onError: (error) {
          _updateMessage(aiMsgId, 'Error: $error', isLoading: false);
        },
      );
    } catch (e) {
      _updateMessage(aiMsgId, 'Error: $e', isLoading: false);
    }
  }

  Future<void> _handleContinueCommand() async {
    final l10n = AppLocalizations.of(context);
    final aiMsgId = const Uuid().v4();
    final aiMsg = app_chat.ChatMessage(
      id: aiMsgId,
      content: l10n.continuingText ?? '正在续写...',
      isUser: false,
      role: 'assistant',
      timestamp: DateTime.now(),
      isLoading: true,
    );

    setState(() {
      _messages.add(aiMsg);
    });

    try {
      String fullResponse = '';
      final stream = _aiService.streamContinueText(widget.quote!.content);
      
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
            metaJson: jsonEncode({
              'type': 'smart_result',
              'command': '/续写',
              'title': l10n.continueResult ?? '续写结果',
            }),
          );
        },
        onError: (error) {
          _updateMessage(aiMsgId, 'Error: $error', isLoading: false);
        },
      );
    } catch (e) {
      _updateMessage(aiMsgId, 'Error: $e', isLoading: false);
    }
  }

  Future<void> _askNote(String text) async {
    final l10n = AppLocalizations.of(context);
    final aiMsgId = const Uuid().v4();
    final aiMsg = app_chat.ChatMessage(
      id: aiMsgId,
      content: l10n.thinkingInProgress ?? '思考中...',
      isUser: false,
      role: 'assistant',
      timestamp: DateTime.now(),
      isLoading: true,
    );

    setState(() {
      _messages.add(aiMsg);
    });
    _scrollToBottom();

    try {
      String fullResponse = '';
      final history = _messages.where((m) => m.includedInContext && m.id != aiMsgId && !m.isLoading).toList();
      final stream = _aiService.streamAskQuestion(widget.quote!, text, history: history);
      
      _streamSubscription = stream.listen(
        (chunk) {
          fullResponse += chunk;
          _updateMessage(aiMsgId, fullResponse, isLoading: true);
        },
        onDone: () {
          _updateMessage(aiMsgId, fullResponse.isNotEmpty ? fullResponse : l10n.aiMisunderstoodQuestion, isLoading: false);
        },
        onError: (error) {
          _updateMessage(aiMsgId, l10n.aiResponseError(error.toString()), isLoading: false);
        },
      );
    } catch (e) {
      _updateMessage(aiMsgId, l10n.aiResponseError(e.toString()), isLoading: false);
    }
  }

  Future<void> _askAgent(String text) async {
    final l10n = AppLocalizations.of(context);
    final history = _messages.where((m) => m.includedInContext).toList();
    
    try {
      final response = await _agentService.runAgent(
        userMessage: text,
        history: history,
      );

      final aiMsg = app_chat.ChatMessage(
        id: const Uuid().v4(),
        content: response.content,
        isUser: false,
        role: 'assistant',
        timestamp: DateTime.now(),
      );

      setState(() {
        _messages.add(aiMsg);
        _isLoading = false;
      });
      if (_currentSessionId != null) {
        await _chatSessionService.addMessage(_currentSessionId!, aiMsg);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.aiResponseError(e.toString()))),
        );
      }
    }
    _scrollToBottom();
  }

  void _updateMessage(String id, String newContent, {required bool isLoading, String? metaJson}) {
    setState(() {
      final idx = _messages.indexWhere((m) => m.id == id);
      if (idx != -1) {
        final oldMsg = _messages[idx];
        final updatedMsg = app_chat.ChatMessage(
          id: oldMsg.id,
          content: newContent,
          isUser: oldMsg.isUser,
          role: oldMsg.role,
          timestamp: oldMsg.timestamp,
          isLoading: isLoading,
          includedInContext: oldMsg.includedInContext,
          metaJson: metaJson ?? oldMsg.metaJson,
        );
        _messages[idx] = updatedMsg;

        if (!isLoading) {
          _isLoading = false;
          if (_currentSessionId != null) {
             _chatSessionService.addMessage(_currentSessionId!, updatedMsg);
          }
        }
      }
    });
    _scrollToBottom();
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
        title: Text(_isNoteMode ? (l10n.askNoteTitle ?? '问笔记') : (l10n.aiAssistantLabel ?? 'AI 助手')),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment),
            tooltip: '新对话',
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
          if (_isNoteMode)
            Container(
              padding: const EdgeInsets.all(8),
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              child: Row(
                children: [
                  Icon(Icons.description, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '当前笔记上下文：${_getQuotePreview()}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16.0),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return _buildMessageBubble(message, theme);
              },
            ),
          ),
          if (_isLoading && !_isNoteMode) _buildAgentStatusIndicator(theme, l10n),
          _buildInputArea(theme, l10n),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(app_chat.ChatMessage message, ThemeData theme) {
    if (message.metaJson != null) {
      try {
        final meta = jsonDecode(message.metaJson!);
        if (meta['type'] == 'smart_result') {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: SmartResultCard(
              title: meta['title'] ?? '智能结果',
              content: message.content,
              onReplace: () {
                Navigator.pop(context, {'action': 'replace', 'text': message.content});
              },
              onAppend: () {
                Navigator.pop(context, {'action': 'append', 'text': message.content});
              },
            ),
          );
        }
      } catch (e) {
        // ignore JSON parse error, fallback to normal render
      }
    }

    final isUser = message.isUser;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(Icons.smart_toy, color: theme.colorScheme.onPrimaryContainer, size: 18),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isUser ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16).copyWith(
                  bottomRight: isUser ? const Radius.circular(0) : null,
                  bottomLeft: !isUser ? const Radius.circular(0) : null,
                ),
              ),
              child: isUser
                  ? Text(message.content, style: TextStyle(color: theme.colorScheme.onPrimary))
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
              child: Icon(Icons.person, color: theme.colorScheme.onSecondaryContainer, size: 18),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAgentStatusIndicator(ThemeData theme, AppLocalizations l10n) {
    return Consumer<AgentService>(
      builder: (context, agentService, child) {
        if (!agentService.isRunning) return const SizedBox.shrink();
        final statusKey = agentService.currentStatusKey;
        final statusText = switch (statusKey) {
          '' => '...',
          'agentThinking' => l10n.agentThinking ?? 'Thinking...',
          'agentSearchingNotes' => l10n.agentSearchingNotes ?? 'Searching notes...',
          'agentAnalyzingData' => l10n.agentAnalyzingData ?? 'Analyzing data...',
          'agentWebSearching' => l10n.agentWebSearching ?? 'Searching web...',
          _ => statusKey.startsWith(AgentService.agentToolCallPrefix)
              ? (l10n.agentToolCall != null ? l10n.agentToolCall(statusKey.substring(AgentService.agentToolCallPrefix.length)) : 'Calling tool...')
              : (l10n.agentThinking ?? 'Thinking...'),
        };

        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 8),
              Text(
                statusText,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputArea(ThemeData theme, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(8.0).copyWith(
        bottom: MediaQuery.of(context).padding.bottom + 8.0,
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
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              decoration: InputDecoration(
                hintText: _isNoteMode ? (l10n.slashCommandHint ?? '输入 / 查看可用命令，或直接提问') : (l10n.message ?? '发送消息'),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24.0),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              ),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: _handleSubmitted,
            ),
          ),
          const SizedBox(width: 8.0),
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.send),
              color: theme.colorScheme.onPrimary,
              tooltip: l10n.confirm ?? '发送',
              onPressed: () => _handleSubmitted(_textController.text),
            ),
          ),
        ],
      ),
    );
  }
}
