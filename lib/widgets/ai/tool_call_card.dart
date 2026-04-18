import 'package:flutter/material.dart';
import '../../gen_l10n/app_localizations.dart';

/// Tool调用状态
enum ToolCallStatus {
  pending,
  executing,
  completed,
  error,
}

/// Tool调用信息
class ToolCallInfo {
  final String id;
  final String name;
  final Map<String, dynamic> parameters;
  final ToolCallStatus status;
  final dynamic result;
  final String? errorMessage;
  final DateTime startTime;
  final DateTime? endTime;
  final bool expanded;

  ToolCallInfo({
    required this.id,
    required this.name,
    required this.parameters,
    required this.status,
    this.result,
    this.errorMessage,
    required this.startTime,
    this.endTime,
    this.expanded = false,
  });

  Duration get duration {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }

  ToolCallInfo copyWith({
    String? id,
    String? name,
    Map<String, dynamic>? parameters,
    ToolCallStatus? status,
    dynamic result,
    String? errorMessage,
    DateTime? startTime,
    DateTime? endTime,
    bool? expanded,
  }) {
    return ToolCallInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      parameters: parameters ?? this.parameters,
      status: status ?? this.status,
      result: result ?? this.result,
      errorMessage: errorMessage ?? this.errorMessage,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      expanded: expanded ?? this.expanded,
    );
  }
}

/// Tool调用进度卡片
class ToolCallProgressCard extends StatefulWidget {
  final ToolCallInfo toolCall;
  final ValueChanged<bool>? onExpandChanged;
  final VoidCallback? onRetry;

  const ToolCallProgressCard({
    super.key,
    required this.toolCall,
    this.onExpandChanged,
    this.onRetry,
  });

  @override
  State<ToolCallProgressCard> createState() => _ToolCallProgressCardState();
}

class _ToolCallProgressCardState extends State<ToolCallProgressCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _expandController;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
      value: widget.toolCall.expanded ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(ToolCallProgressCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.toolCall.expanded != oldWidget.toolCall.expanded) {
      if (widget.toolCall.expanded) {
        _expandController.forward();
      } else {
        _expandController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _expandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final toolCall = widget.toolCall;

    final statusColor = switch (toolCall.status) {
      ToolCallStatus.pending => theme.colorScheme.outline,
      ToolCallStatus.executing => theme.colorScheme.primary,
      ToolCallStatus.completed => Colors.green,
      ToolCallStatus.error => theme.colorScheme.error,
    };

    final statusIcon = switch (toolCall.status) {
      ToolCallStatus.pending => Icons.schedule,
      ToolCallStatus.executing => Icons.hourglass_bottom,
      ToolCallStatus.completed => Icons.check_circle,
      ToolCallStatus.error => Icons.error,
    };

    final statusText = switch (toolCall.status) {
      ToolCallStatus.pending => '待执行',
      ToolCallStatus.executing => '执行中',
      ToolCallStatus.completed => '完成',
      ToolCallStatus.error => '错误',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(
          color: statusColor.withValues(alpha: 0.3),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 工具调用头部
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  _expandController.forward();
                  widget.onExpandChanged?.call(!toolCall.expanded);
                });
              },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // 状态图标
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        statusIcon,
                        color: statusColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),

                    // 工具名称和状态
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  toolCall.name,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  statusText,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: statusColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (toolCall.status == ToolCallStatus.executing)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: SizedBox(
                                height: 3,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(1.5),
                                  child: LinearProgressIndicator(
                                    backgroundColor: theme.colorScheme.primary
                                        .withValues(alpha: 0.2),
                                    valueColor: AlwaysStoppedAnimation(
                                      theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (toolCall.status != ToolCallStatus.executing)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                _formatDuration(toolCall.duration),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // 展开按钮
                    if (toolCall.result != null ||
                        toolCall.errorMessage != null)
                      RotationTransition(
                        turns: Tween<double>(begin: 0, end: 0.5).animate(
                          _expandController,
                        ),
                        child: Icon(
                          Icons.expand_more,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // 工具调用详情（展开时显示）
          SizeTransition(
            sizeFactor: _expandController,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 1,
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),

                // 参数
                if (toolCall.parameters.isNotEmpty)
                  _ToolCallDetailSection(
                    title: '参数',
                    content: _formatParameters(toolCall.parameters),
                    theme: theme,
                  ),

                // 结果
                if (toolCall.result != null &&
                    toolCall.status == ToolCallStatus.completed)
                  _ToolCallDetailSection(
                    title: '结果',
                    content: _formatResult(toolCall.result),
                    theme: theme,
                    isError: false,
                  ),

                // 错误信息
                if (toolCall.errorMessage != null)
                  _ToolCallDetailSection(
                    title: '错误',
                    content: toolCall.errorMessage!,
                    theme: theme,
                    isError: true,
                  ),

                // 操作按钮
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (toolCall.status == ToolCallStatus.error)
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: widget.onRetry,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('重试'),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inSeconds < 1) {
      return '${duration.inMilliseconds}ms';
    } else if (duration.inSeconds < 60) {
      return '${duration.inSeconds}s';
    } else {
      final minutes = duration.inMinutes;
      final seconds = duration.inSeconds % 60;
      return '${minutes}m ${seconds}s';
    }
  }

  String _formatParameters(Map<String, dynamic> params) {
    final entries = params.entries.map((e) {
      final value = e.value is String ? '"${e.value}"' : e.value;
      return '${e.key}: $value';
    }).toList();
    return entries.join('\n');
  }

  String _formatResult(dynamic result) {
    if (result is String) {
      return result;
    } else if (result is Map || result is List) {
      return result.toString();
    }
    return result.toString();
  }
}

class _ToolCallDetailSection extends StatelessWidget {
  final String title;
  final String content;
  final ThemeData theme;
  final bool isError;

  const _ToolCallDetailSection({
    required this.title,
    required this.content,
    required this.theme,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: isError ? theme.colorScheme.error : null,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isError
                  ? theme.colorScheme.error.withValues(alpha: 0.1)
                  : theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isError
                    ? theme.colorScheme.error.withValues(alpha: 0.3)
                    : theme.colorScheme.primary.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Text(
              content,
              style: theme.textTheme.labelSmall?.copyWith(
                fontFamily: 'monospace',
                color: isError
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurface,
              ),
              maxLines: 10,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tool调用进度面板（展示多个Tool调用）
class ToolCallProgressPanel extends StatefulWidget {
  final List<ToolCallInfo> toolCalls;
  final ValueChanged<String>? onToolCallExpandChanged;
  final Map<String, VoidCallback>? onRetryCallbacks;

  const ToolCallProgressPanel({
    super.key,
    required this.toolCalls,
    this.onToolCallExpandChanged,
    this.onRetryCallbacks,
  });

  @override
  State<ToolCallProgressPanel> createState() => _ToolCallProgressPanelState();
}

class _ToolCallProgressPanelState extends State<ToolCallProgressPanel> {
  final Set<String> _expandedToolCalls = {};

  @override
  Widget build(BuildContext context) {
    if (widget.toolCalls.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: widget.toolCalls.map((toolCall) {
        final isExpanded = _expandedToolCalls.contains(toolCall.id);
        final updatedToolCall = toolCall.copyWith(expanded: isExpanded);

        return ToolCallProgressCard(
          toolCall: updatedToolCall,
          onExpandChanged: (expanded) {
            setState(() {
              if (expanded) {
                _expandedToolCalls.add(toolCall.id);
              } else {
                _expandedToolCalls.remove(toolCall.id);
              }
            });
            widget.onToolCallExpandChanged?.call(toolCall.id);
          },
          onRetry: widget.onRetryCallbacks?[toolCall.id],
        );
      }).toList(),
    );
  }
}
