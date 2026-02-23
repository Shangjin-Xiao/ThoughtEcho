import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../gen_l10n/app_localizations.dart';
import 'ai_action_buttons.dart'; // 导入 AI 操作按钮组件

/// 语音识别结果编辑底部弹出组件
///
/// 显示识别结果并提供编辑、AI纠错、识别来源等操作
class VoiceResultSheet extends StatefulWidget {
  final String recognizedText;
  final Function(String)? onTextChanged;
  final VoidCallback? onApplyCorrection;
  final VoidCallback? onRecognizeSource;
  final VoidCallback? onInsertToEditor;

  const VoiceResultSheet({
    super.key,
    required this.recognizedText,
    this.onTextChanged,
    this.onApplyCorrection,
    this.onRecognizeSource,
    this.onInsertToEditor,
  });

  @override
  State<VoiceResultSheet> createState() => _VoiceResultSheetState();
}

class _VoiceResultSheetState extends State<VoiceResultSheet> {
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

    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Material(
            color: theme.colorScheme.surface,
            child: Column(
              children: [
                // 拖拽条
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withOpacity(
                        0.35,
                      ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),

                // 标题栏
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: Row(
                    children: [
                      Text(
                        l10n.voiceResultTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded),
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).copyButtonLabel,
                        onPressed: _textController.text.trim().isEmpty
                            ? null
                            : () async {
                                HapticFeedback.selectionClick();
                                await Clipboard.setData(
                                  ClipboardData(text: _textController.text),
                                );
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(l10n.ok),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),

                // 主体内容：可滚动
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: EdgeInsets.fromLTRB(
                      16,
                      8,
                      16,
                      16 + MediaQuery.of(context).viewInsets.bottom,
                    ),
                    children: [
                      TextField(
                        controller: _textController,
                        minLines: 6,
                        maxLines: 14,
                        textInputAction: TextInputAction.newline,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          height: 1.35,
                          letterSpacing: 0.2,
                        ),
                        decoration: InputDecoration(
                          hintText: l10n.voiceEditResult,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      AIActionButtons(
                        text: _textController.text,
                        onCorrectionResult: widget.onTextChanged,
                        onSourceResult: (author, work) {
                          if (author != null || work != null) {
                            widget.onRecognizeSource?.call();
                          }
                        },
                      ),
                    ],
                  ),
                ),

                // 底部主按钮固定
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
        },
      ),
    );
  }
}
