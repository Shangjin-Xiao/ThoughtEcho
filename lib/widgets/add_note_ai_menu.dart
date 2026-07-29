import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/ai_assistant_entry.dart';
import '../services/ai_service.dart';
import '../models/quote_model.dart';
import '../widgets/ai_options_menu.dart';
import '../pages/ai_assistant_page.dart';
import '../constants/app_constants.dart';
import '../gen_l10n/app_localizations.dart';

/// AI 菜单按钮，所有功能统一跳转到 Thoughter（AIAssistantPage）。
class AddNoteAIMenu extends StatefulWidget {
  final TextEditingController contentController;
  final TextEditingController authorController;
  final TextEditingController workController;
  final Function(String) onAiAnalysisCompleted;
  final List<String>? tagNames; // 标签名称列表（用于 AI 分析）

  const AddNoteAIMenu({
    super.key,
    required this.contentController,
    required this.authorController,
    required this.workController,
    required this.onAiAnalysisCompleted,
    this.tagNames,
  });

  @override
  State<AddNoteAIMenu> createState() => _AddNoteAIMenuState();
}

class _AddNoteAIMenuState extends State<AddNoteAIMenu> {
  // 显示AI选项菜单
  void _showAIOptions(BuildContext context) {
    AiOptionsMenu.show(
      context: context,
      showAskNote: true,
      onAnalyzeSource: () => _openAiAssistant(
        AppLocalizations.of(context).aiPromptSourceAnalysis,
      ),
      onPolishText: () => _openAiAssistant(
        AppLocalizations.of(context).aiPromptPolish,
      ),
      onContinueText: () => _openAiAssistant(
        AppLocalizations.of(context).aiPromptContinue,
      ),
      onAnalyzeContent: () => _openAiAssistant(
        AppLocalizations.of(context).aiPromptDeepAnalysis,
      ),
      onAskNote: () => _openAiAssistant(null),
    );
  }

  /// 统一入口：跳转到 Thoughter（AIAssistantPage）。
  /// 在 AddNoteDialog 之上 push，用户可以返回继续编辑。
  Future<void> _openAiAssistant(String? initialQuestion) async {
    final l10n = AppLocalizations.of(context);

    if (widget.contentController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pleaseEnterContent),
          duration: AppConstants.snackBarDurationNormal,
        ),
      );
      return;
    }

    // 创建临时Quote对象用于 Agent 上下文
    final tempQuote = Quote(
      id: '',
      content: widget.contentController.text,
      date: DateTime.now().toIso8601String(),
      sourceAuthor: widget.authorController.text.trim().isNotEmpty
          ? widget.authorController.text.trim()
          : null,
      sourceWork: widget.workController.text.trim().isNotEmpty
          ? widget.workController.text.trim()
          : null,
    );

    // 在 AddNoteDialog 之上导航到 Thoughter
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AIAssistantPage(
          entrySource: AIAssistantEntrySource.note,
          quote: tempQuote,
          initialQuestion: initialQuestion,
        ),
      ),
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
