import 'package:flutter/material.dart';
import '../../gen_l10n/app_localizations.dart';

/// OCR 识别结果编辑底部弹出组件
/// 
/// 显示 OCR 识别结果并提供编辑、AI纠错、识别来源等操作
class OCRResultSheet extends StatefulWidget {
  final String recognizedText;
  final Function(String)? onTextChanged;
  final VoidCallback? onApplyCorrection;
  final VoidCallback? onRecognizeSource;
  final VoidCallback? onInsertToEditor;

  const OCRResultSheet({
    super.key,
    required this.recognizedText,
    this.onTextChanged,
    this.onApplyCorrection,
    this.onRecognizeSource,
    this.onInsertToEditor,
  });

  @override
  State<OCRResultSheet> createState() => _OCRResultSheetState();
}

class _OCRResultSheetState extends State<OCRResultSheet> {
  late TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.recognizedText);
    _textController.addListener(() {
      widget.onTextChanged?.call(_textController.text);
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题栏
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: theme.dividerColor,
                ),
              ),
            ),
            child: Row(
              children: [
                Text(
                  l10n.ocrResultTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // 可编辑文本区域
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _textController,
              maxLines: 8,
              decoration: InputDecoration(
                hintText: l10n.voiceEditResult,
                border: const OutlineInputBorder(),
              ),
            ),
          ),

          // 操作按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.onApplyCorrection,
                    icon: const Icon(Icons.auto_fix_high),
                    label: Text(l10n.voiceApplyCorrection),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.onRecognizeSource,
                    icon: const Icon(Icons.search),
                    label: Text(l10n.voiceRecognizeSource),
                  ),
                ),
              ],
            ),
          ),

          // 填入编辑器按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: widget.onInsertToEditor,
                icon: const Icon(Icons.check),
                label: Text(l10n.voiceInsertToEditor),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
