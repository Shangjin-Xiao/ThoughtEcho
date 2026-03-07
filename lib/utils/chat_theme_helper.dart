import 'package:flutter/material.dart';

/// 聊天主题工具类（新版 flutter_chat_ui 2.x 推荐 builder 方式）
class ChatThemeHelper {
  /// 返回 textMessageBuilder 函数，应用自定义文本样式
  static Widget Function(
    BuildContext context,
    dynamic message,
    int index, {
    required bool isSentByMe,
  }) createTextMessageBuilder(ThemeData appTheme) {
    final colorScheme = appTheme.colorScheme;
    return (context, message, index, {required bool isSentByMe}) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: isSentByMe ? colorScheme.primary : colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: isSentByMe ? colorScheme.onPrimary : colorScheme.onSurface,
            fontSize: 16,
            fontWeight: FontWeight.w400,
            height: 1.5,
          ),
        ),
      );
    };
  }
}
