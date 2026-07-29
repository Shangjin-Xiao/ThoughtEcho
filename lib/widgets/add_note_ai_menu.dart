import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ai_service.dart';
import '../widgets/ai_options_menu.dart';
import '../gen_l10n/app_localizations.dart';

/// AI 菜单按钮：只负责展示选项并把选中的提示词回传。
///
/// 跳转 Thoughter 的动作交给宿主（AddNoteDialog）执行——宿主才拿得到笔记身份
/// 和未保存状态，与全屏编辑器 `_NoteEditorAIFeatures` 的分工保持一致。
class AddNoteAIMenu extends StatelessWidget {
  /// 选中某个 AI 功能。参数是要发给 Thoughter 的初始提示词，
  /// null 表示不带提示词直接进入对话。
  final Future<void> Function(String? initialQuestion) onOpenAiAssistant;

  const AddNoteAIMenu({
    super.key,
    required this.onOpenAiAssistant,
  });

  void _showAIOptions(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    AiOptionsMenu.show(
      context: context,
      showAskNote: true,
      onAnalyzeSource: () => onOpenAiAssistant(l10n.aiPromptSourceAnalysis),
      onPolishText: () => onOpenAiAssistant(l10n.aiPromptPolish),
      onContinueText: () => onOpenAiAssistant(l10n.aiPromptContinue),
      onAnalyzeContent: () => onOpenAiAssistant(l10n.aiPromptDeepAnalysis),
      onAskNote: () => onOpenAiAssistant(null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    AIService? aiService;
    try {
      aiService = Provider.of<AIService>(context, listen: false);
    } catch (_) {
      aiService = null;
    }

    final bool aiConfigured = aiService != null && aiService.hasValidApiKey();

    if (!aiConfigured) {
      return const SizedBox.shrink();
    }

    return IconButton(
      icon: const Icon(Icons.auto_awesome),
      tooltip: l10n.aiAssistant,
      onPressed: () => _showAIOptions(context),
    );
  }
}
