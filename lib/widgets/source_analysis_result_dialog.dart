import 'dart:convert';

import 'package:flutter/material.dart';
import '../gen_l10n/app_localizations.dart';

/// 来源分析结果对话框
///
/// 用于展示 AI 来源分析的结果（作者、作品、置信度、解释），
/// 并提供应用结果到文本控制器的功能。
class SourceAnalysisResultDialog {
  /// 显示来源分析结果对话框
  ///
  /// [context] - 上下文
  /// [result] - AI 返回的 JSON 字符串
  /// [authorController] - 作者输入框控制器（可选）
  /// [workController] - 作品输入框控制器（可选）
  /// [onError] - 错误回调
  static void show(
    BuildContext context,
    String result, {
    TextEditingController? authorController,
    TextEditingController? workController,
    Function(String)? onError,
  }) {
    final l10n = AppLocalizations.of(context);

    try {
      // 清理 AI 返回的 markdown 代码块包裹
      String cleanedResult = result.trim();
      final codeBlockRegex = RegExp(
        r'^```(?:json)?\s*\n?(.*?)\n?\s*```$',
        dotAll: true,
      );
      final codeBlockMatch = codeBlockRegex.firstMatch(cleanedResult);
      if (codeBlockMatch != null) {
        cleanedResult = codeBlockMatch.group(1)!.trim();
      }

      final Map<String, dynamic> sourceData = json.decode(cleanedResult);
      final String? author = sourceData['author'] as String?;
      final String? work = sourceData['work'] as String?;
      final String confidence =
          sourceData['confidence'] as String? ?? l10n.unknown;
      final String explanation = sourceData['explanation'] as String? ?? '';

      showDialog(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(l10n.analysisResultWithConfidence(confidence)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (author != null && author.isNotEmpty) ...[
                  Text(
                    l10n.possibleAuthor,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(author),
                  const SizedBox(height: 8),
                ],
                if (work != null && work.isNotEmpty) ...[
                  Text(
                    l10n.possibleWork,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(work),
                  const SizedBox(height: 8),
                ],
                if (explanation.isNotEmpty) ...[
                  Text(
                    l10n.analysisExplanation,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(explanation, style: const TextStyle(fontSize: 13)),
                ],
                if ((author == null || author.isEmpty) &&
                    (work == null || work.isEmpty))
                  Text(l10n.noAuthorWorkIdentified),
              ],
            ),
            actions: [
              if ((author != null && author.isNotEmpty) ||
                  (work != null && work.isNotEmpty))
                TextButton(
                  child: Text(l10n.applyAnalysisResult),
                  onPressed: () {
                    if (author != null &&
                        author.isNotEmpty &&
                        authorController != null) {
                      authorController.text = author;
                    }
                    if (work != null &&
                        work.isNotEmpty &&
                        workController != null) {
                      workController.text = work;
                    }
                    Navigator.of(dialogContext).pop();
                  },
                ),
              TextButton(
                child: Text(l10n.close),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (onError != null) {
        onError(e.toString());
      }
    }
  }
}
