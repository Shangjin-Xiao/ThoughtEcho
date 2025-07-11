import 'package:flutter/material.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';

/// 聊天主题工具类
class ChatThemeHelper {
  /// 基于应用主题创建聊天主题
  static ChatTheme createChatTheme(ThemeData appTheme) {
    final colorScheme = appTheme.colorScheme;

    return DefaultChatTheme(
      backgroundColor: colorScheme.surface,
      primaryColor: colorScheme.primary,
      secondaryColor: colorScheme.surface,

      // 接收的消息样式（AI回复）
      receivedMessageBodyTextStyle: TextStyle(
        color: colorScheme.onSurface,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.5,
      ),

      // 发送的消息样式（用户消息）
      sentMessageBodyTextStyle: TextStyle(
        color: colorScheme.onPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.5,
      ),

      // 消息时间戳样式
      receivedMessageCaptionTextStyle: TextStyle(
        color: colorScheme.outline,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      sentMessageCaptionTextStyle: TextStyle(
        color: colorScheme.onPrimary.withValues(alpha: 0.7),
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),

      // 输入框样式
      inputBackgroundColor: colorScheme.surface,
      inputTextColor: colorScheme.onSurface,
      inputBorderRadius: const BorderRadius.all(Radius.circular(24)),
      inputMargin: const EdgeInsets.all(16),
      inputPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      inputTextDecoration: InputDecoration(
        hintText: '输入你的问题...',
        hintStyle: TextStyle(color: colorScheme.outline),
        border: InputBorder.none,
      ),

      // 消息气泡样式
      messageBorderRadius: 20,
      messageInsetsHorizontal: 16,
      messageInsetsVertical: 8,

      // 用户头像颜色
      userAvatarNameColors: [colorScheme.primary],

      // 日期分割线样式
      dateDividerTextStyle: TextStyle(
        color: colorScheme.outline,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),

      // 空聊天占位符样式
      emptyChatPlaceholderTextStyle: TextStyle(
        color: colorScheme.outline,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),

      // 用户名样式
      userNameTextStyle: TextStyle(
        color: colorScheme.outline,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),

      // 错误颜色
      errorColor: colorScheme.error,

      // 发送按钮样式
      sendButtonIcon: Icon(Icons.send, color: colorScheme.primary),
    );
  }

  /// 创建聊天输入选项
  static InputOptions createInputOptions({
    bool enabled = true,
    String? hintText,
  }) {
    return InputOptions(
      enabled: enabled,
      sendButtonVisibilityMode: SendButtonVisibilityMode.always,
      textEditingController: null, // 让Chat组件自己管理
    );
  }
}
