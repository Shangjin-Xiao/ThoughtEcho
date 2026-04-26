import 'package:flutter/material.dart';

import '../../gen_l10n/app_localizations.dart';
import 'thinking_widget.dart';
import 'tool_progress_panel.dart';

class AIAssistantAgentStatusPanel extends StatelessWidget {
  const AIAssistantAgentStatusPanel({
    super.key,
    required this.showPanel,
    required this.lastAgentRunning,
    required this.enableThinking,
    required this.currentModelSupportsThinking,
    required this.thinkingText,
    required this.isThinking,
    required this.toolProgressItems,
    required this.isToolInProgress,
    required this.statusText,
  });

  final bool showPanel;
  final bool lastAgentRunning;
  final bool enableThinking;
  final bool currentModelSupportsThinking;
  final String thinkingText;
  final bool isThinking;
  final List<ToolProgressItem> toolProgressItems;
  final bool isToolInProgress;
  final String statusText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    if (!showPanel && !lastAgentRunning) {
      return const SizedBox.shrink();
    }

    final children = <Widget>[];

    if (enableThinking &&
        currentModelSupportsThinking &&
        thinkingText.isNotEmpty) {
      children.add(
        ThinkingWidget(
          key: const ValueKey('agent_status_thinking_widget'),
          thinkingText: thinkingText,
          inProgress: lastAgentRunning && isThinking,
          accentColor: theme.colorScheme.primary,
        ),
      );
    }

    if (toolProgressItems.isNotEmpty) {
      children.add(
        ToolProgressPanel(
          key: const ValueKey('agent_status_tool_progress_panel'),
          title: l10n.toolExecutionProgress,
          items: List.unmodifiable(toolProgressItems),
          inProgress: isToolInProgress,
          accentColor: theme.colorScheme.primary,
        ),
      );
    }

    if (children.isEmpty && lastAgentRunning && statusText.isNotEmpty) {
      final isDark = theme.brightness == Brightness.dark;
      final agentBubbleColor =
          isDark ? const Color(0xFF1b1c1d) : const Color(0xFFe9eef6);

      children.add(
        Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: agentBubbleColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.zero,
              topRight: Radius.circular(24),
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  statusText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: Padding(
        key: ValueKey<String>(
          'agent-status-$lastAgentRunning-${toolProgressItems.length}-${thinkingText.isNotEmpty}',
        ),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
                child: Text(
                  l10n.aiAssistantUser,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
