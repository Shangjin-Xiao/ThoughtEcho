import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' show PartialText;
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../gen_l10n/app_localizations.dart';
import '../models/chat_message.dart' as app_chat;
import '../models/quote_model.dart';
import '../services/ai_service.dart';
import '../services/chat_session_service.dart';
import '../utils/app_logger.dart';
import '../utils/string_utils.dart';
import '../widgets/session_history_sheet.dart';

/// 问笔记聊天界面 — 支持多轮对话持久化
class NoteQAChatPage extends StatefulWidget {
  final Quote quote;
  final String? initialQuestion;
  const NoteQAChatPage({
    super.key,
    required this.quote,
    this.initialQuestion,
  });

  @override
  State<NoteQAChatPage> createState() => _NoteQAChatPageState();
}

class _NoteQAChatPageState extends State<NoteQAChatPage> {
  AppLocalizations get l10n => AppLocalizations.of(context);
  late final InMemoryChatController _chatController;
  late final User _user;
  late final User _assistant;
  late AIService _aiService;
  late ChatSessionService _chatSessionService;
  StreamSubscription<String>? _streamSubscription;
  bool _isResponding = false;
  String? _currentLoadingId;
  String? _currentSessionId;
  List<app_chat.ChatMessage> _chatHistory = [];
  bool _canPersist = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _aiService = Provider.of<AIService>(context, listen: false);
    _chatSessionService =
        Provider.of<ChatSessionService>(context, listen: false);
    _user = User(id: 'user', name: l10n.meUser);
    _assistant = User(id: 'assistant', name: l10n.aiAssistantUser);
  }

  @override
  void initState() {
    super.initState();
    _chatController = InMemoryChatController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOrCreateSession());
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _chatController.dispose();
    super.dispose();
  }

  Future<void> _loadOrCreateSession() async {
    final noteId = widget.quote.id;
    _canPersist = noteId != null && noteId.isNotEmpty;
    if (_canPersist) {
      try {
        final session =
            await _chatSessionService.getLatestSessionForNote(noteId!);
        if (session != null) {
          await _loadSession(session.id);
        } else {
          await _createNewSession();
        }
      } catch (e) {
        AppLogger.e('加载会话失败', error: e);
        _canPersist = false;
      }
    }
    _addWelcomeMessage();
    if (widget.initialQuestion?.isNotEmpty == true) {
      _handleSendPressed(PartialText(text: widget.initialQuestion!));
    }
  }

  Future<void> _createNewSession() async {
    final noteId = widget.quote.id;
    if (noteId == null || noteId.isEmpty) return;
    final session = await _chatSessionService.createSession(
      sessionType: 'note',
      noteId: noteId,
      title: _getQuotePreview(),
    );
    _currentSessionId = session.id;
  }

  Future<void> _loadSession(String sessionId) async {
    _currentSessionId = sessionId;
    final messages = await _chatSessionService.getMessages(sessionId);
    _chatHistory = messages.where((m) => m.includedInContext).toList();
    for (final msg in messages) {
      _chatController.insertMessage(TextMessage(
        authorId: msg.role == 'user' ? _user.id : _assistant.id,
        createdAt: msg.timestamp,
        id: msg.id,
        text: msg.content,
      ));
    }
  }

  void _addWelcomeMessage() {
    final welcomeMsg = app_chat.ChatMessage(
      id: const Uuid().v4(),
      content: l10n.aiAssistantWelcome(_getQuotePreview()),
      isUser: false,
      role: 'system',
      timestamp: DateTime.now(),
      includedInContext: false,
    );
    _chatController.insertMessage(TextMessage(
      authorId: _assistant.id,
      createdAt: welcomeMsg.timestamp,
      id: welcomeMsg.id,
      text: welcomeMsg.content,
    ));
    if (_canPersist && _currentSessionId != null) {
      _chatSessionService.addMessage(_currentSessionId!, welcomeMsg);
    }
  }

  void _handleSendPressed(PartialText message) {
    if (_isResponding) return;
    final now = DateTime.now();
    final msgId = const Uuid().v4();
    _chatController.insertMessage(TextMessage(
      authorId: _user.id,
      createdAt: now,
      id: msgId,
      text: message.text,
    ));
    final chatMsg = app_chat.ChatMessage(
      id: msgId,
      content: message.text,
      isUser: true,
      role: 'user',
      timestamp: now,
    );
    _chatHistory.add(chatMsg);
    if (_canPersist && _currentSessionId != null) {
      _chatSessionService.addMessage(_currentSessionId!, chatMsg);
    }
    _askAI(message.text);
  }

  Future<void> _askAI(String question) async {
    if (question.trim().isEmpty) return;
    setState(() => _isResponding = true);
    _currentLoadingId = const Uuid().v4();
    _chatController.insertMessage(TextMessage(
      authorId: _assistant.id,
      createdAt: DateTime.now(),
      id: _currentLoadingId!,
      text: l10n.thinkingInProgress,
    ));
    try {
      String fullResponse = '';
      final stream = _aiService.streamAskQuestion(
        widget.quote,
        question,
        history: _chatHistory,
      );
      _streamSubscription = stream.listen(
        (chunk) {
          fullResponse += chunk;
          _updateLoadingMessage(fullResponse);
        },
        onDone: () => _finalizeAssistantMessage(
          fullResponse.isNotEmpty ? fullResponse : l10n.aiMisunderstoodQuestion,
        ),
        onError: (error) {
          AppLogger.e('AI回答失败', error: error);
          _finalizeAssistantMessage(
            l10n.aiResponseError(error.toString()),
          );
        },
      );
    } catch (e) {
      AppLogger.e('发送问题失败', error: e);
      _finalizeAssistantMessage(l10n.aiResponseError(e.toString()));
    }
  }

  void _updateLoadingMessage(String text) {
    setState(() {
      final msgs = _chatController.messages;
      final idx = msgs.indexWhere((m) => m.id == _currentLoadingId);
      if (idx != -1) {
        _chatController.updateMessage(
          msgs[idx],
          TextMessage(
            authorId: _assistant.id,
            createdAt: DateTime.now(),
            id: _currentLoadingId!,
            text: text,
          ),
        );
      }
    });
  }

  void _finalizeAssistantMessage(String text) {
    final now = DateTime.now();
    final finalId = const Uuid().v4();
    setState(() {
      final msgs = _chatController.messages;
      final idx = msgs.indexWhere((m) => m.id == _currentLoadingId);
      if (idx != -1) {
        _chatController.updateMessage(
          msgs[idx],
          TextMessage(
            authorId: _assistant.id,
            createdAt: now,
            id: finalId,
            text: text,
          ),
        );
      }
      _isResponding = false;
    });
    final chatMsg = app_chat.ChatMessage(
      id: finalId,
      content: text,
      isUser: false,
      role: 'assistant',
      timestamp: now,
    );
    _chatHistory.add(chatMsg);
    if (_canPersist && _currentSessionId != null) {
      _chatSessionService.addMessage(_currentSessionId!, chatMsg);
    }
  }

  Future<void> _switchToSession(String sessionId) async {
    for (final msg in List.of(_chatController.messages)) {
      _chatController.removeMessage(msg);
    }
    _chatHistory.clear();
    await _loadSession(sessionId);
    _addWelcomeMessage();
    if (mounted) setState(() {});
  }

  Future<void> _startNewChat() async {
    for (final msg in List.of(_chatController.messages)) {
      _chatController.removeMessage(msg);
    }
    _chatHistory.clear();
    _currentSessionId = null;
    if (_canPersist) await _createNewSession();
    _addWelcomeMessage();
    if (mounted) setState(() {});
  }

  void _showSessionHistory() {
    final noteId = widget.quote.id;
    if (noteId == null || noteId.isEmpty) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SessionHistorySheet(
        noteId: noteId,
        currentSessionId: _currentSessionId,
        chatSessionService: _chatSessionService,
        onSelect: (id) {
          Navigator.of(ctx).pop();
          _switchToSession(id);
        },
        onDelete: (id) async {
          await _chatSessionService.deleteSession(id);
          if (id == _currentSessionId) {
            Navigator.of(ctx).pop();
            _startNewChat();
          }
        },
        onNewChat: () {
          Navigator.of(ctx).pop();
          _startNewChat();
        },
      ),
    );
  }

  String _getQuotePreview() {
    final content =
        StringUtils.removeObjectReplacementChar(widget.quote.content);
    return content.length <= 100 ? content : '${content.substring(0, 100)}...';
  }

  void _showNoteInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.noteInfoTitle),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.quote.source != null) ...[
                Text(l10n.source,
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                Text(widget.quote.source!),
                const SizedBox(height: 16),
              ],
              Text(l10n.createdAt,
                  style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(DateTime.parse(widget.quote.date).toString()),
              const SizedBox(height: 16),
              Text(l10n.content,
                  style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(
                StringUtils.removeObjectReplacementChar(
                  widget.quote.content,
                ),
                maxLines: 10,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.askNoteTitle),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          if (_canPersist)
            IconButton(
              icon: const Icon(Icons.history),
              onPressed: _showSessionHistory,
              tooltip: l10n.chatHistory,
            ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showNoteInfo,
            tooltip: l10n.viewNoteInfo,
          ),
        ],
      ),
      body: Chat(
        chatController: _chatController,
        currentUserId: _user.id,
        onMessageSend: (text) {
          _handleSendPressed(PartialText(text: text));
        },
        resolveUser: (id) async {
          if (id == _user.id) return _user;
          if (id == _assistant.id) return _assistant;
          return User(id: id, name: l10n.unknown);
        },
      ),
    );
  }
}
