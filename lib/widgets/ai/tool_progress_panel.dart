import 'package:flutter/material.dart';

import '../../gen_l10n/app_localizations.dart';

/// 工具调用进度状态
enum ToolProgressStatus {
  /// 等待执行
  pending,

  /// 正在执行
  running,

  /// 已完成
  completed,

  /// 执行失败
  failed,
}

/// 工具调用进度项
class ToolProgressItem {
  /// 工具名称
  final String toolName;

  /// 工具描述或参数摘要
  final String? description;

  /// 执行状态
  final ToolProgressStatus status;

  /// 执行结果摘要
  final String? result;

  const ToolProgressItem({
    required this.toolName,
    this.description,
    required this.status,
    this.result,
  });

  ToolProgressItem copyWith({
    String? toolName,
    String? description,
    ToolProgressStatus? status,
    String? result,
  }) {
    return ToolProgressItem(
      toolName: toolName ?? this.toolName,
      description: description ?? this.description,
      status: status ?? this.status,
      result: result ?? this.result,
    );
  }
}

/// 工具调用折叠进度面板组件
///
/// 参考 Google AI Gallery MessageBodyCollapsableProgressPanel 设计：
/// - 显示 Agent 执行的工具调用列表
/// - 可折叠展开查看详情
/// - 进行中时显示进度指示器
/// - 完成后显示执行摘要
class ToolProgressPanel extends StatefulWidget {
  /// 面板标题
  final String title;

  /// 工具调用列表
  final List<ToolProgressItem> items;

  /// 是否正在执行中
  final bool inProgress;

  /// 完成时的图标（默认 Icons.check_circle）
  final IconData? doneIcon;

  /// 可选的强调色（用于图标和指示器）
  final Color? accentColor;

  const ToolProgressPanel({
    super.key,
    required this.title,
    required this.items,
    this.inProgress = false,
    this.doneIcon,
    this.accentColor,
  });

  @override
  State<ToolProgressPanel> createState() => _ToolProgressPanelState();
}

class _ToolProgressPanelState extends State<ToolProgressPanel>
    with SingleTickerProviderStateMixin {
  late bool _isExpanded;
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    // 进行中时默认展开，完成后默认折叠
    _isExpanded = widget.inProgress;
    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    if (_isExpanded) {
      _rotationController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(ToolProgressPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果从进行中变为完成，自动折叠
    if (oldWidget.inProgress && !widget.inProgress) {
      setState(() {
        _isExpanded = false;
        _rotationController.reverse();
      });
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _rotationController.forward();
      } else {
        _rotationController.reverse();
      }
    });
  }

  String _getDisplayTitle(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (widget.inProgress) {
      return widget.title;
    } else {
      // 完成后显示"已执行 N 个操作"
      return l10n.executedNOperations(widget.items.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = widget.accentColor ?? theme.colorScheme.primary;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 可点击的头部
          InkWell(
            onTap: _toggleExpanded,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // 进度指示器或完成图标
                  if (widget.inProgress)
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                      ),
                    )
                  else
                    Icon(
                      widget.doneIcon ?? Icons.check_circle,
                      size: 20,
                      color: iconColor,
                    ),
                  const SizedBox(width: 12),
                  // 标题（动画切换）
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: child,
                        );
                      },
                      child: Text(
                        _getDisplayTitle(context),
                        key: ValueKey(widget.inProgress),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: iconColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  // 展开/折叠图标
                  RotationTransition(
                    turns: Tween(begin: 0.0, end: 0.5)
                        .animate(_rotationController),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      size: 20,
                      color: iconColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 工具调用列表（可展开/折叠）
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _isExpanded
                ? Padding(
                    padding: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                      bottom: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: widget.items.map((item) {
                        return _buildToolItem(context, item);
                      }).toList(),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildToolItem(BuildContext context, ToolProgressItem item) {
    final theme = Theme.of(context);
    final iconColor = widget.accentColor ?? theme.colorScheme.primary;

    // 根据状态选择图标和颜色
    IconData statusIcon;
    Color statusColor;
    switch (item.status) {
      case ToolProgressStatus.pending:
        statusIcon = Icons.schedule;
        statusColor = theme.colorScheme.outline;
        break;
      case ToolProgressStatus.running:
        statusIcon = Icons.sync;
        statusColor = iconColor;
        break;
      case ToolProgressStatus.completed:
        statusIcon = Icons.check_circle_outline;
        statusColor = theme.colorScheme.tertiary;
        break;
      case ToolProgressStatus.failed:
        statusIcon = Icons.error_outline;
        statusColor = theme.colorScheme.error;
        break;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 状态指示器
          Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(right: 12),
            child: item.status == ToolProgressStatus.running
                ? CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                  )
                : Icon(
                    statusIcon,
                    size: 18,
                    color: statusColor,
                  ),
          ),
          // 工具信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 工具名称
                Text(
                  item.toolName,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                // 描述或参数摘要
                if (item.description != null && item.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      item.description!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                // 结果摘要
                if (item.result != null && item.result!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.result!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontFamily: 'monospace',
                          height: 1.3,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
