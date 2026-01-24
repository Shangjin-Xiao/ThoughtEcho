import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' show PartialText;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../gen_l10n/app_localizations.dart';
import '../models/quote_model.dart';
import '../services/ai_service.dart';
import '../utils/app_logger.dart';

/// 现代化的问笔记聊天界面页面
class NoteQAChatPage extends StatefulWidget {
  final Quote quote;
  final String? initialQuestion;

  const NoteQAChatPage({super.key, required this.quote, this.initialQuestion});

  @override
  State<NoteQAChatPage> createState() => _NoteQAChatPageState();
}

class _NoteQAChatPageState extends State<NoteQAChatPage> {
  AppLocalizations get l10n => AppLocalizations.of(context);
  late final InMemoryChatController _chatController;
  late final User _user;
  late final User _assistant;
  late AIService _aiService;
  StreamSubscription<String>? _streamSubscription;
  bool _isResponding = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _aiService = Provider.of<AIService>(context, listen: false);
    _user = User(id: 'user', name: l10n.meUser);
    _assistant = User(id: 'assistant', name: l10n.aiAssistantUser);
  }

  @override
  void initState() {
    super.initState();
    _chatController = InMemoryChatController();
    // 添加欢迎消息
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chatController.insertMessage(
        TextMessage(
          authorId: _assistant.id,
          createdAt: DateTime.now(),
          id: const Uuid().v4(),
          text: l10n.aiAssistantWelcome(_getQuotePreview()),
        ),
      );

      // 如果有初始问题，自动发送
      if (widget.initialQuestion != null &&
          widget.initialQuestion!.isNotEmpty) {
        _handleSendPressed(PartialText(text: widget.initialQuestion!));
      }
    });
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _chatController.dispose();
    super.dispose();
  }

  String _getQuotePreview() {
    final content = widget.quote.content;
    if (content.length <= 100) {
      return content;
    }
    return '${content.substring(0, 100)}...';
  }

  void _handleSendPressed(PartialText message) {
    if (_isResponding) return;
    final textMessage = TextMessage(
      authorId: _user.id,
      createdAt: DateTime.now(),
      id: const Uuid().v4(),
      text: message.text,
    );
    _chatController.insertMessage(textMessage);
    _askAI(message.text);
  }

  // 已弃用，直接用 _chatController.insertMessage

  Future<void> _askAI(String question) async {
    if (question.trim().isEmpty) return;

    setState(() {
      _isResponding = true;
    });
    // 创建一个临时的加载消息
    final loadingMessage = TextMessage(
      authorId: _assistant.id,
      createdAt: DateTime.now(),
      id: 'loading',
      text: l10n.thinkingInProgress,
    );
    _chatController.insertMessage(loadingMessage);

    try {
      String fullResponse = '';
      final stream = _aiService.streamAskQuestion(widget.quote, question);

      _streamSubscription = stream.listen(
        (chunk) {
          fullResponse += chunk;

          // 更新正在回复的消息内容
          setState(() {
            // 替换 loading 消息内容
            final messages = _chatController.messages;
            final index = messages.indexWhere((msg) => msg.id == 'loading');
            if (index != -1) {
              final loadingMsg = messages[index];
              final updatedMsg = TextMessage(
                authorId: _assistant.id,
                createdAt: DateTime.now(),
                id: 'loading',
                text: fullResponse,
              );
              _chatController.updateMessage(loadingMsg, updatedMsg);
            }
          });
        },
        onDone: () {
          // 完成回复，生成最终消息
          setState(() {
            final messages = _chatController.messages;
            final index = messages.indexWhere((msg) => msg.id == 'loading');
            if (index != -1) {
              final loadingMsg = messages[index];
              final finalMsg = TextMessage(
                authorId: _assistant.id,
                createdAt: DateTime.now(),
                id: 'loading',
                text: fullResponse.isNotEmpty
                    ? fullResponse
                    : l10n.aiMisunderstoodQuestion,
              );
              _chatController.updateMessage(loadingMsg, finalMsg);
            }
            _isResponding = false;
          });
        },
        onError: (error) {
          AppLogger.e('AI回答失败', error: error);
          setState(() {
            final messages = _chatController.messages;
            final index = messages.indexWhere((msg) => msg.id == 'loading');
            if (index != -1) {
              final loadingMsg = messages[index];
              final errorMsg = TextMessage(
                authorId: _assistant.id,
                createdAt: DateTime.now(),
                id: 'loading',
                text: l10n.aiResponseError(error.toString()),
              );
              _chatController.updateMessage(loadingMsg, errorMsg);
            }
            _isResponding = false;
          });
        },
      );
    } catch (e) {
      AppLogger.e('发送问题失败', error: e);
      setState(() {
        final messages = _chatController.messages;
        final index = messages.indexWhere((msg) => msg.id == 'loading');
        if (index != -1) {
          final loadingMsg = messages[index];
          final errorMsg = TextMessage(
            authorId: _assistant.id,
            createdAt: DateTime.now(),
            id: 'loading',
            text: l10n.aiResponseError(e.toString()),
          );
          _chatController.updateMessage(loadingMsg, errorMsg);
        }
        _isResponding = false;
      });
    }
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
                widget.quote.content,
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
}
