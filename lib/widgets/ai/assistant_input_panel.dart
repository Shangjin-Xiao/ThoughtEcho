import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../gen_l10n/app_localizations.dart';
import '../../models/ai_workflow_descriptor.dart';

class AIAssistantInputPanel extends StatelessWidget {
  const AIAssistantInputPanel({
    super.key,
    required this.textController,
    required this.focusNode,
    required this.isLoading,
    required this.isInputFocused,
    required this.showSlashCommands,
    required this.filteredWorkflowDescriptors,
    required this.selectedMediaFiles,
    required this.isAgentMode,
    required this.currentModelSupportsThinking,
    required this.enableThinking,
    required this.onPickAndAttachMedia,
    required this.onToggleMode,
    required this.onToggleThinking,
    required this.onSendOrStop,
    required this.onSubmitText,
    required this.onRemoveMediaFile,
    required this.onSubmitWorkflowCommand,
  });

  final TextEditingController textController;
  final FocusNode focusNode;
  final bool isLoading;
  final bool isInputFocused;
  final bool showSlashCommands;
  final List<AIWorkflowDescriptor> filteredWorkflowDescriptors;
  final List<PlatformFile> selectedMediaFiles;
  final bool isAgentMode;
  final bool currentModelSupportsThinking;
  final bool enableThinking;
  final VoidCallback onPickAndAttachMedia;
  final VoidCallback onToggleMode;
  final VoidCallback onToggleThinking;
  final VoidCallback onSendOrStop;
  final ValueChanged<String> onSubmitText;
  final ValueChanged<int> onRemoveMediaFile;
  final ValueChanged<String> onSubmitWorkflowCommand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final shellBorderColor = isInputFocused
        ? theme.colorScheme.primary.withValues(alpha: 0.6)
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.75);

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: shellBorderColor,
            width: isInputFocused ? 1.4 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: theme.brightness == Brightness.dark ? 0.24 : 0.06,
              ),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: showSlashCommands && filteredWorkflowDescriptors.isNotEmpty
                  ? Padding(
                      key: const ValueKey('slash_commands_visible'),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children:
                              filteredWorkflowDescriptors.map((descriptor) {
                            return ActionChip(
                              label: Text(descriptor.command),
                              onPressed: () {
                                textController.clear();
                                onSubmitWorkflowCommand(descriptor.command);
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(
                      key: ValueKey('slash_commands_hidden'),
                    ),
            ),
            if (selectedMediaFiles.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  height: 60,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: selectedMediaFiles.length,
                    itemBuilder: (context, index) {
                      final file = selectedMediaFiles[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: theme.colorScheme.outline.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      file.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      '${(file.size / 1024).toStringAsFixed(1)} KB',
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              InkWell(
                                onTap: () => onRemoveMediaFile(index),
                                child: Icon(
                                  Icons.close,
                                  size: 16,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    key: const ValueKey('ai_assistant_attach_button'),
                    icon: Icon(
                      Icons.add,
                      color: isLoading
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.primary,
                    ),
                    tooltip: l10n.attachFile,
                    onPressed: isLoading ? null : onPickAndAttachMedia,
                    style: IconButton.styleFrom(
                      shape: const CircleBorder(),
                    ),
                    iconSize: 20,
                  ),
                  Expanded(
                    child: TextField(
                      controller: textController,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        hintText: l10n.aiAssistantInputHint,
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 12,
                        ),
                      ),
                      maxLines: null,
                      minLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: onSubmitText,
                    ),
                  ),
                  GestureDetector(
                    key: const ValueKey('ai_assistant_mode_toggle'),
                    onTap: isLoading ? null : onToggleMode,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color:
                            theme.colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isAgentMode
                                ? Icons.smart_toy_outlined
                                : Icons.chat_outlined,
                            size: 14,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isAgentMode ? l10n.aiModeAgent : l10n.aiModeChat,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (currentModelSupportsThinking)
                    IconButton(
                      key: const ValueKey('ai_assistant_thinking_toggle'),
                      icon: Icon(
                        enableThinking
                            ? Icons.psychology
                            : Icons.psychology_outlined,
                        color: enableThinking
                            ? theme.colorScheme.secondary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      tooltip: l10n.aiThinking,
                      onPressed: onToggleThinking,
                      iconSize: 20,
                    ),
                  IconButton(
                    key: const ValueKey('ai_assistant_send_button'),
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, animation) {
                        return RotationTransition(
                          turns: animation,
                          child: child,
                        );
                      },
                      child: Icon(
                        isLoading ? Icons.stop_circle : Icons.arrow_outward,
                        key: ValueKey<bool>(isLoading),
                        color: isLoading
                            ? theme.colorScheme.onError
                            : theme.colorScheme.onPrimary,
                      ),
                    ),
                    onPressed: onSendOrStop,
                    tooltip: isLoading ? l10n.stopGenerate : l10n.confirm,
                    style: IconButton.styleFrom(
                      backgroundColor: isLoading
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                      shape: const CircleBorder(),
                    ),
                    iconSize: 20,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
