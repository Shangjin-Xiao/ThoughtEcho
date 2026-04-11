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
    final backgroundColor = theme.colorScheme.surfaceContainerHigh;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.zero,
          topRight: Radius.circular(24),
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          InkWell(
            onTap: _toggleExpanded,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.zero,
              topRight: Radius.circular(24),
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Progress indicator or done icon
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Center(
                      child: widget.inProgress
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.0,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : Icon(
                              widget.doneIcon ?? Icons.check_circle_outline,
                              size: 24,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Title
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        _getDisplayTitle(context),
                        key: ValueKey(widget.inProgress),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  // Expand/Collapse Icon
                  Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          // Collapsable Content
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
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
    final itemBackgroundColor = theme.colorScheme.surfaceContainerLow;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: itemBackgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dot
          Container(
            margin: const EdgeInsets.only(top: 4, right: 12),
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.secondaryContainer,
            ),
          ),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  item.toolName,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                // Description
                if (item.description != null && item.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      item.description!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                // Result
                if (item.result != null && item.result!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      item.result!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
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
