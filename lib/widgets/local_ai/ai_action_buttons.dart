import 'package:flutter/material.dart';
import '../../gen_l10n/app_localizations.dart';
import '../../services/local_ai/local_ai_service.dart';
import '../../utils/app_logger.dart';

/// AI 操作按钮组件
/// 
/// 提供 AI 纠错和识别来源功能
class AIActionButtons extends StatefulWidget {
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
  State<AIActionButtons> createState() => _AIActionButtonsState();
}

class _AIActionButtonsState extends State<AIActionButtons> {
  bool _isCorrectingLoading = false;
  bool _isSourceLoading = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _isCorrectingLoading ? null : () => _applyCorrection(context),
            icon: _isCorrectingLoading 
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_fix_high),
            label: Text(l10n.voiceApplyCorrection),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _isSourceLoading ? null : () => _recognizeSource(context),
            icon: _isSourceLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
            label: Text(l10n.voiceRecognizeSource),
          ),
        ),
      ],
    );
  }

  /// AI 纠错 - 仅修复识别错误，不润色
  Future<void> _applyCorrection(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final localAI = LocalAIService.instance;

    setState(() {
      _isCorrectingLoading = true;
    });

    try {
      // 检查功能是否启用
      if (!localAI.isFeatureEnabled(LocalAIFeature.aiCorrection)) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.localAiNotEnabled)),
        );
        return;
      }

      // 调用本地 AI 服务进行纠错
      final result = await localAI.correctText(widget.text);

      if (!context.mounted) return;

      if (result.hasChanges) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.aiCorrectionApplied)),
        );
        widget.onCorrectionResult?.call(result.correctedText);
      } else {
        // 无需修改
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.aiCorrectionApplied)),
        );
        widget.onCorrectionResult?.call(widget.text);
      }
    } catch (e) {
      logError('AI 纠错失败: $e', source: 'AIActionButtons');
      if (!context.mounted) return;
      
      // 如果服务不可用，直接返回原文
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.aiCorrectionApplied)),
      );
      widget.onCorrectionResult?.call(widget.text);
    } finally {
      if (mounted) {
        setState(() {
          _isCorrectingLoading = false;
        });
      }
    }
  }

  /// 识别来源 - 提取作者和作品名
  Future<void> _recognizeSource(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final localAI = LocalAIService.instance;

    setState(() {
      _isSourceLoading = true;
    });

    try {
      // 检查功能是否启用
      if (!localAI.isFeatureEnabled(LocalAIFeature.sourceRecognition)) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.localAiNotEnabled)),
        );
        return;
      }

      // 调用本地 AI 服务识别来源
      final result = await localAI.recognizeSource(widget.text);

      if (!context.mounted) return;

      if (result.hasSource) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.aiSourceRecognized)),
        );
        widget.onSourceResult?.call(result.author, result.work);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.aiNoSourceFound)),
        );
      }
    } catch (e) {
      logError('来源识别失败: $e', source: 'AIActionButtons');
      if (!context.mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.aiNoSourceFound)),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSourceLoading = false;
        });
      }
    }
  }
}

