import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ai_service.dart';
import '../models/quote_model.dart';
import '../widgets/ai_assistant_drawer.dart'; // 导入AI助手抽屉组件

class AddNoteAIMenu extends StatefulWidget {
  final TextEditingController contentController;
  final TextEditingController authorController;
  final TextEditingController workController;
  final Function(String) onAiAnalysisCompleted;

  const AddNoteAIMenu({
    super.key,
    required this.contentController,
    required this.authorController,
    required this.workController,
    required this.onAiAnalysisCompleted,
  });

  @override
  State<AddNoteAIMenu> createState() => _AddNoteAIMenuState();
}

class _AddNoteAIMenuState extends State<AddNoteAIMenu> {
    // 显示AI选项菜单
  void _showAIOptions(BuildContext context) {
    // 创建临时Quote对象用于AI操作
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

    AIAssistantDrawer.show(
      context,
      tempQuote,
      onContentUpdated: (Quote updatedQuote) {
        // 处理内容更新
        if (updatedQuote.content != tempQuote.content) {
          // 内容有变化，更新控制器
          widget.contentController.text = updatedQuote.content;
        }

        // 处理作者和作品更新
        if (updatedQuote.sourceAuthor != tempQuote.sourceAuthor) {
          widget.authorController.text = updatedQuote.sourceAuthor ?? '';
        }
        if (updatedQuote.sourceWork != tempQuote.sourceWork) {
          widget.workController.text = updatedQuote.sourceWork ?? '';
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
      tooltip: 'AI助手',
      onPressed: () => _showAIOptions(context),
    );
  }
}
