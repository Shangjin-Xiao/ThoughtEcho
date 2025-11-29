import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' show PartialText;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

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
  late final InMemoryChatController _chatController;
  late final User _user;
  late final User _assistant;
  late AIService _aiService;
  StreamSubscription<String>? _streamSubscription;
  bool _isResponding = false;

  @override
  void initState() {
    super.initState();
    _aiService = Provider.of<AIService>(context, listen: false);
    _user = const User(id: 'user', name: '我');
    _assistant = const User(id: 'assistant', name: 'AI助手');
    _chatController = InMemoryChatController();
    // 添加欢迎消息
    _chatController.insertMessage(
      TextMessage(
        authorId: _assistant.id,
        createdAt: DateTime.now(),
        id: const Uuid().v4(),
        text:
            '你好！我是你的笔记助手。你可以问我关于这篇笔记的任何问题，我会基于笔记内容为你提供深度解答。\n\n📝 笔记内容概览：\n${_getQuotePreview()}\n\n💡 你可以试试这些问题：\n• 这篇笔记的核心思想是什么？\n• 从这篇笔记中能得到什么启发？\n• 如何将这篇笔记的想法应用到实际生活中？\n• 这篇笔记反映了什么样的思维模式？',
      ),
    );
    // 如果有初始问题，自动发送
    if (widget.initialQuestion != null && widget.initialQuestion!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleSendPressed(PartialText(text: widget.initialQuestion!));
      });
    }
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
      text: '正在思考中...',
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
                    : '抱歉，我没能理解这个问题。请尝试换个方式问我。',
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
                text: '抱歉，回答时出现了错误：${error.toString()}',
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
            text: '抱歉，发生了错误：${e.toString()}',
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
        title: const Text('问笔记'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showNoteInfo,
            tooltip: '查看笔记信息',
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
          return User(id: id, name: '未知');
        },
      ),
    );
  }

  void _showNoteInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('笔记信息'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.quote.source != null) ...[
                Text('来源', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                Text(widget.quote.source!),
                const SizedBox(height: 16),
              ],
              Text('创建时间', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(DateTime.parse(widget.quote.date).toString()),
              const SizedBox(height: 16),
              Text('内容', style: Theme.of(context).textTheme.labelMedium),
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
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
