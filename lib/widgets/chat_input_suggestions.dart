import 'package:flutter/material.dart';

import '../gen_l10n/app_localizations.dart';

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
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
              onPressed: () => onSuggestionTap(suggestion),
              elevation: 2,
              shadowColor: theme.shadowColor.withValues(alpha: 0.1),
            ),
          );
        },
      ),
    );
  }

  /// 根据笔记内容生成智能建议
  static List<String> generateSuggestions(
    AppLocalizations l10n,
    String noteContent,
  ) {
    final suggestions = <String>[];

    // 基础问题
    suggestions
        .addAll([l10n.aiSuggestionCoreIdea, l10n.aiSuggestionInspiration]);

    // 根据内容长度调整建议
    if (noteContent.length > 200) {
      suggestions.add(l10n.aiSuggestionSummarize);
    }

    // 检测关键词并提供相关建议
    final lowerContent = noteContent.toLowerCase();
    // 中文笔记匹配中文关键词；其余语言（默认英文回退）匹配英文关键词，
    // 避免英文用户因关键词不匹配而收不到针对性建议。
    final isChinese = l10n.localeName.startsWith('zh');

    if (isChinese
        ? (lowerContent.contains('问题') || lowerContent.contains('困难'))
        : (lowerContent.contains('problem') ||
            lowerContent.contains('difficult') ||
            lowerContent.contains('trouble'))) {
      suggestions.add(l10n.aiSuggestionSolution);
    }

    if (isChinese
        ? (lowerContent.contains('学习') || lowerContent.contains('知识'))
        : (lowerContent.contains('learn') ||
            lowerContent.contains('study') ||
            lowerContent.contains('knowledge'))) {
      suggestions.add(l10n.aiSuggestionUnderstandConcept);
    }

    if (isChinese
        ? (lowerContent.contains('计划') || lowerContent.contains('目标'))
        : (lowerContent.contains('plan') ||
            lowerContent.contains('goal') ||
            lowerContent.contains('objective'))) {
      suggestions.add(l10n.aiSuggestionActionPlan);
    }

    if (isChinese
        ? (lowerContent.contains('感受') || lowerContent.contains('情感'))
        : (lowerContent.contains('feel') ||
            lowerContent.contains('feeling') ||
            lowerContent.contains('emotion'))) {
      suggestions.add(l10n.aiSuggestionPsychology);
    }

    // 通用建议
    suggestions.addAll([
      l10n.aiSuggestionRealLife,
      l10n.aiSuggestionThinkingPattern,
    ]);

    // 限制建议数量并去重
    return suggestions.toSet().take(6).toList();
  }
}
