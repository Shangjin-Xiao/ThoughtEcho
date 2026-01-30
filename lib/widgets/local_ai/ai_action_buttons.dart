import 'package:flutter/material.dart';
import '../../gen_l10n/app_localizations.dart';

/// AI 操作按钮组件
///
/// 提供 AI 纠错和识别来源功能
class AIActionButtons extends StatelessWidget {
  final String text;
  final Function(String)? onCorrectionResult;
  final Function(String?, String?)? onSourceResult;

  const AIActionButtons({
    super.key,
    required this.text,
    this.onCorrectionResult,
    this.onSourceResult,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _applyCorrection(context),
            icon: const Icon(Icons.auto_fix_high),
            label: Text(l10n.voiceApplyCorrection),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _recognizeSource(context),
            icon: const Icon(Icons.search),
            label: Text(l10n.voiceRecognizeSource),
          ),
        ),
      ],
    );
  }

  /// AI 纠错 - 仅修复识别错误，不润色
  Future<void> _applyCorrection(BuildContext context) async {
    final l10n = AppLocalizations.of(context);

    // TODO: 调用本地 AI 模型进行纠错 - 后端实现后添加
    // 目前返回 mock 数据
    await Future.delayed(const Duration(milliseconds: 500));

    if (!context.mounted) return;

    // Mock: 假设纠错结果
    final correctedText = text; // 实际应该是 AI 纠错后的文本

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.aiCorrectionApplied)),
    );

    onCorrectionResult?.call(correctedText);
  }

  /// 识别来源 - 提取作者和作品名
  Future<void> _recognizeSource(BuildContext context) async {
    final l10n = AppLocalizations.of(context);

    // TODO: 调用本地 AI 模型识别来源 - 后端实现后添加
    // 目前返回 mock 数据
    await Future.delayed(const Duration(milliseconds: 500));

    if (!context.mounted) return;

    // Mock: 假设未识别到来源
    const String? author = null;
    const String? work = null;

    if (author == null && work == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.aiNoSourceFound)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.aiSourceRecognized)),
      );
      onSourceResult?.call(author, work);
    }
  }
}
