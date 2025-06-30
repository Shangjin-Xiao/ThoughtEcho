import 'package:flutter/material.dart';

/// 聊天输入建议组件
class ChatInputSuggestions extends StatelessWidget {
  final List<String> suggestions;
  final Function(String) onSuggestionTap;
  final ThemeData theme;

  const ChatInputSuggestions({
    super.key,
    required this.suggestions,
    required this.onSuggestionTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 60,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: suggestions.length,
        itemBuilder: (context, index) {
          final suggestion = suggestions[index];
          return Container(
            margin: const EdgeInsets.only(right: 8),
            child: ActionChip(
              label: Text(
                suggestion,
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              backgroundColor: theme.colorScheme.surface,
              side: BorderSide(
                color: theme.colorScheme.outline.withOpacity(0.3),
              ),
              onPressed: () => onSuggestionTap(suggestion),
              elevation: 2,
              shadowColor: theme.shadowColor.withOpacity(0.1),
            ),
          );
        },
      ),
    );
  }

  /// 根据笔记内容生成智能建议
  static List<String> generateSuggestions(String noteContent) {
    final suggestions = <String>[];

    // 基础问题
    suggestions.addAll(['这篇笔记的核心思想是什么？', '从中能得到什么启发？']);

    // 根据内容长度调整建议
    if (noteContent.length > 200) {
      suggestions.add('能否总结一下要点？');
    }

    // 检测关键词并提供相关建议
    final lowerContent = noteContent.toLowerCase();

    if (lowerContent.contains('问题') || lowerContent.contains('困难')) {
      suggestions.add('有什么解决方案吗？');
    }

    if (lowerContent.contains('学习') || lowerContent.contains('知识')) {
      suggestions.add('如何更好地理解这个概念？');
    }

    if (lowerContent.contains('计划') || lowerContent.contains('目标')) {
      suggestions.add('如何制定行动计划？');
    }

    if (lowerContent.contains('感受') || lowerContent.contains('情感')) {
      suggestions.add('这反映了什么心理状态？');
    }

    // 通用建议
    suggestions.addAll(['如何应用到实际生活中？', '反映了什么思维模式？']);

    // 限制建议数量并去重
    return suggestions.toSet().take(6).toList();
  }
}
