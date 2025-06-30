import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:url_launcher/url_launcher.dart';
import '../utils/chat_markdown_styles.dart';

/// 支持Markdown的聊天消息气泡组件
class MarkdownMessageBubble extends StatelessWidget {
  final types.TextMessage message;
  final bool isCurrentUser;
  final ThemeData theme;

  const MarkdownMessageBubble({
    super.key,
    required this.message,
    required this.isCurrentUser,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(
        left: isCurrentUser ? 60 : 16,
        right: isCurrentUser ? 16 : 60,
        top: 4,
        bottom: 4,
      ),
      child: Align(
        alignment: isCurrentUser ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          onLongPress: () => _showMessageOptions(context),
          child: Container(
            decoration: BoxDecoration(
              color:
                  isCurrentUser
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: theme.shadowColor.withOpacity(0.1),
                  offset: const Offset(0, 2),
                  blurRadius: 4,
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 用户名（仅对AI消息显示）
                if (!isCurrentUser && message.author.firstName != null) ...[
                  Text(
                    message.author.firstName!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],

                // Markdown内容
                if (isCurrentUser)
                  // 用户消息使用简单文本显示
                  Text(
                    message.text,
                    style: TextStyle(
                      color: theme.colorScheme.onPrimary,
                      fontSize: 16,
                      height: 1.4,
                    ),
                  )
                else
                  // AI消息使用Markdown渲染
                  MarkdownBody(
                    data: message.text,
                    selectable: true,
                    styleSheet: ChatMarkdownStyleSheet.create(
                      theme,
                      isDarkMode: theme.brightness == Brightness.dark,
                    ),
                    onTapLink: _handleLinkTap,
                  ),

                // 时间戳
                const SizedBox(height: 6),
                Text(
                  _formatTime(
                    message.createdAt ?? DateTime.now().millisecondsSinceEpoch,
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    color:
                        isCurrentUser
                            ? theme.colorScheme.onPrimary.withOpacity(0.7)
                            : theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(int timestamp) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${dateTime.month}/${dateTime.day} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}小时前';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}分钟前';
    } else {
      return '刚刚';
    }
  }

  void _handleLinkTap(String text, String? href, String title) {
    if (href != null) {
      launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
    }
  }

  void _showMessageOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (context) => SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.copy),
                  title: const Text('复制消息'),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: message.text));
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('消息已复制到剪贴板'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
                if (!isCurrentUser) ...[
                  ListTile(
                    leading: const Icon(Icons.share),
                    title: const Text('分享消息'),
                    onTap: () {
                      Navigator.pop(context);
                      // 这里可以添加分享功能
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('分享功能开发中'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
    );
  }
}
