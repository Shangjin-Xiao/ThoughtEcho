import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/quote_model.dart';
import '../services/ai_service.dart';
import '../utils/app_logger.dart';
import '../utils/chat_theme_helper.dart';
import '../widgets/markdown_message_bubble.dart';
import '../widgets/chat_input_suggestions.dart';

/// 现代化的问笔记聊天界面页面
class NoteQAChatPage extends StatefulWidget {
  final Quote quote;
  final String? initialQuestion;

  const NoteQAChatPage({super.key, required this.quote, this.initialQuestion});

  @override
  State<NoteQAChatPage> createState() => _NoteQAChatPageState();
}

class _NoteQAChatPageState extends State<NoteQAChatPage> {
  final List<types.Message> _messages = [];
  late final types.User _user;
  late final types.User _assistant;
  late AIService _aiService;
  StreamSubscription<String>? _streamSubscription;
  bool _isResponding = false;

  @override
  void initState() {
    super.initState();
    _aiService = Provider.of<AIService>(context, listen: false);

    // 创建用户
    _user = const types.User(id: 'user', firstName: '我');

    // 创建AI助手
    _assistant = const types.User(id: 'assistant', firstName: 'AI助手');

    // 添加欢迎消息
    _addWelcomeMessage();

    // 如果有初始问题，自动发送
    if (widget.initialQuestion != null && widget.initialQuestion!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleSendPressed(types.PartialText(text: widget.initialQuestion!));
      });
    }
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    super.dispose();
  }

  void _addWelcomeMessage() {
    final welcomeMessage = types.TextMessage(
      author: _assistant,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      id: const Uuid().v4(),
      text:
          '你好！我是你的笔记助手。你可以问我关于这篇笔记的任何问题，我会基于笔记内容为你提供深度解答。\n\n📝 笔记内容概览：\n${_getQuotePreview()}\n\n💡 你可以试试这些问题：\n• 这篇笔记的核心思想是什么？\n• 从这篇笔记中能得到什么启发？\n• 如何将这篇笔记的想法应用到实际生活中？\n• 这篇笔记反映了什么样的思维模式？',
    );

    setState(() {
      _messages.insert(0, welcomeMessage);
    });
  }

  String _getQuotePreview() {
    final content = widget.quote.content;
    if (content.length <= 100) {
      return content;
    }
    return '${content.substring(0, 100)}...';
  }

  void _handleSendPressed(types.PartialText message) {
    if (_isResponding) return;

    final textMessage = types.TextMessage(
      author: _user,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      id: const Uuid().v4(),
      text: message.text,
    );

    _addMessage(textMessage);
    _askAI(message.text);
  }

  void _addMessage(types.Message message) {
    setState(() {
      _messages.insert(0, message);
    });
  }

  Future<void> _askAI(String question) async {
    if (question.trim().isEmpty) return;

    setState(() {
      _isResponding = true;
    });

    // 创建一个临时的加载消息
    final loadingMessage = types.TextMessage(
      author: _assistant,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      id: 'loading',
      text: '正在思考中...',
    );

    _addMessage(loadingMessage);

    try {
      String fullResponse = '';
      final stream = _aiService.streamAskQuestion(widget.quote, question);

      _streamSubscription = stream.listen(
        (chunk) {
          fullResponse += chunk;

          // 更新正在回复的消息内容
          setState(() {
            final index = _messages.indexWhere((msg) => msg.id == 'loading');
            if (index != -1) {
              _messages[index] = types.TextMessage(
                author: _assistant,
                createdAt: DateTime.now().millisecondsSinceEpoch,
                id: 'loading',
                text: fullResponse,
              );
            }
          });
        },
        onDone: () {
          // 完成回复，生成最终消息
          setState(() {
            final index = _messages.indexWhere((msg) => msg.id == 'loading');
            if (index != -1) {
              _messages[index] = types.TextMessage(
                author: _assistant,
                createdAt: DateTime.now().millisecondsSinceEpoch,
                id: const Uuid().v4(),
                text: fullResponse.isNotEmpty
                    ? fullResponse
                    : '抱歉，我没能理解这个问题。请尝试换个方式问我。',
              );
            }
            _isResponding = false;
          });
        },
        onError: (error) {
          AppLogger.e('AI回答失败', error: error);
          setState(() {
            final index = _messages.indexWhere((msg) => msg.id == 'loading');
            if (index != -1) {
              _messages[index] = types.TextMessage(
                author: _assistant,
                createdAt: DateTime.now().millisecondsSinceEpoch,
                id: const Uuid().v4(),
                text: '抱歉，回答时出现了错误：${error.toString()}',
              );
            }
            _isResponding = false;
          });
        },
      );
    } catch (e) {
      AppLogger.e('发送问题失败', error: e);
      setState(() {
        final index = _messages.indexWhere((msg) => msg.id == 'loading');
        if (index != -1) {
          _messages[index] = types.TextMessage(
            author: _assistant,
            createdAt: DateTime.now().millisecondsSinceEpoch,
            id: const Uuid().v4(),
            text: '抱歉，发生了错误：${e.toString()}',
          );
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
        messages: _messages,
        onSendPressed: _handleSendPressed,
        user: _user,
        theme: ChatThemeHelper.createChatTheme(theme),
        showUserAvatars: true,
        showUserNames: true,
        textMessageBuilder: _customTextMessageBuilder,
        inputOptions: InputOptions(
          enabled: !_isResponding,
          sendButtonVisibilityMode: SendButtonVisibilityMode.always,
        ),
        messageWidthRatio: 0.8,
        typingIndicatorOptions: const TypingIndicatorOptions(typingUsers: []),
        emptyState: _messages.isEmpty
            ? Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.chat_outlined,
                      size: 64,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '开始对话',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '问我关于这篇笔记的任何问题',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    _buildQuickQuestionButtons(theme),
                  ],
                ),
              )
            : null,
      ),
    );
  }

  /// 自定义文本消息构建器，支持Markdown渲染
  Widget _customTextMessageBuilder(
    types.TextMessage message, {
    required int messageWidth,
    required bool showName,
  }) {
    final isCurrentUser = message.author.id == _user.id;
    return MarkdownMessageBubble(
      message: message,
      isCurrentUser: isCurrentUser,
      theme: Theme.of(context),
    );
  }

  Widget _buildQuickQuestionButtons(ThemeData theme) {
    // 使用智能建议生成问题
    final smartSuggestions = ChatInputSuggestions.generateSuggestions(
      widget.quote.content,
    );

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: smartSuggestions.map((question) {
        return ActionChip(
          label: Text(
            question,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurface,
            ),
          ),
          backgroundColor: theme.colorScheme.surface,
          side: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.3),
          ),
          onPressed: () {
            _handleSendPressed(types.PartialText(text: question));
          },
        );
      }).toList(),
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
