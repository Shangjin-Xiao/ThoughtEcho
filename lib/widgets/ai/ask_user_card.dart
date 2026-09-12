import 'package:flutter/material.dart';

import '../../gen_l10n/app_localizations.dart';
import '../../theme/app_semantic_colors.dart';
import '../../theme/theme_style.dart';

/// Agent 向用户提问与选项确认卡片。
///
/// 支持展示 2-4 个候选项（单选/多选），并提供自定义文本回复与取消功能。
/// 样式严格遵循项目 UI 规范：使用 AppShapeTokens 圆角与 AppSemanticColors 语义色，
/// 支持 Material 3 主题动态取色与纸墨/素笺手工风格自适应。
class AskUserCard extends StatefulWidget {
  const AskUserCard({
    super.key,
    required this.question,
    this.header,
    required this.options,
    this.multiSelect = false,
    this.isCompleted = false,
    this.isCancelled = false,
    this.selectedOptions = const [],
    this.customText,
    this.onSubmit,
    this.onCancel,
  });

  final String question;
  final String? header;
  final List<String> options;
  final bool multiSelect;
  final bool isCompleted;
  final bool isCancelled;
  final List<String> selectedOptions;
  final String? customText;

  final void Function({
    required List<String> selectedOptions,
    String? customText,
  })? onSubmit;

  final VoidCallback? onCancel;

  @override
  State<AskUserCard> createState() => _AskUserCardState();
}

class _AskUserCardState extends State<AskUserCard> {
  late final Set<String> _selectedOptions;
  late final TextEditingController _customController;

  @override
  void initState() {
    super.initState();
    _selectedOptions = Set<String>.from(widget.selectedOptions);
    _customController = TextEditingController(text: widget.customText ?? '');
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    return _selectedOptions.isNotEmpty ||
        _customController.text.trim().isNotEmpty;
  }

  void _handleOptionToggle(String option) {
    if (widget.isCompleted) return;
    setState(() {
      if (widget.multiSelect) {
        if (_selectedOptions.contains(option)) {
          _selectedOptions.remove(option);
        } else {
          _selectedOptions.add(option);
        }
      } else {
        if (_selectedOptions.contains(option)) {
          _selectedOptions.clear();
        } else {
          _selectedOptions
            ..clear()
            ..add(option);
        }
      }
    });
  }

  void _handleSubmit() {
    if (!_canSubmit) return;
    final custom = _customController.text.trim();
    widget.onSubmit?.call(
      selectedOptions: _selectedOptions.toList(),
      customText: custom.isNotEmpty ? custom : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final shapeTokens = AppShapeTokens.of(context);
    final semanticColors = AppSemanticColors.of(context);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shapeTokens.cardRadius),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: shapeTokens.borderWidth > 0 ? shapeTokens.borderWidth : 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(theme, l10n),
            const SizedBox(height: 12),
            Text(
              widget.question,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            if (widget.isCompleted)
              _buildCompletedView(theme, l10n, semanticColors, shapeTokens)
            else ...[
              _buildInteractiveOptions(theme, shapeTokens),
              const SizedBox(height: 12),
              _buildCustomInput(theme, l10n, shapeTokens),
              const SizedBox(height: 16),
              _buildActions(theme, l10n, shapeTokens),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, AppLocalizations l10n) {
    final title = widget.header?.trim().isNotEmpty == true
        ? widget.header!.trim()
        : l10n.agentAskUserTitle;

    final hintText = widget.multiSelect
        ? l10n.agentAskUserMultiSelectHint
        : l10n.agentAskUserSingleSelectHint;

    return Row(
      children: [
        Icon(
          Icons.help_outline_rounded,
          size: 18,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (!widget.isCompleted)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(
                AppShapeTokens.of(context).buttonRadius,
              ),
            ),
            child: Text(
              hintText,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInteractiveOptions(ThemeData theme, AppShapeTokens shapeTokens) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: widget.options.map((option) {
        final isSelected = _selectedOptions.contains(option);
        return FilterChip(
          label: Text(option),
          selected: isSelected,
          onSelected: (_) => _handleOptionToggle(option),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(shapeTokens.buttonRadius),
          ),
          showCheckmark: widget.multiSelect,
          selectedColor: theme.colorScheme.primaryContainer,
          backgroundColor:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          labelStyle: theme.textTheme.labelLarge?.copyWith(
            color: isSelected
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurface,
          ),
        );
      }).toList(growable: false),
    );
  }

  Widget _buildCustomInput(
    ThemeData theme,
    AppLocalizations l10n,
    AppShapeTokens shapeTokens,
  ) {
    return TextField(
      controller: _customController,
      onChanged: (_) => setState(() {}),
      style: theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: l10n.agentAskUserCustomHint,
        hintStyle: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(shapeTokens.inputRadius),
          borderSide: BorderSide(
            color: theme.colorScheme.outlineVariant,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(shapeTokens.inputRadius),
          borderSide: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(shapeTokens.inputRadius),
          borderSide: BorderSide(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildActions(
    ThemeData theme,
    AppLocalizations l10n,
    AppShapeTokens shapeTokens,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (widget.onCancel != null) ...[
          OutlinedButton(
            onPressed: widget.onCancel,
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(shapeTokens.buttonRadius),
              ),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: Text(
              l10n.cancel,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        FilledButton(
          onPressed: _canSubmit ? _handleSubmit : null,
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(shapeTokens.buttonRadius),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          ),
          child: Text(
            l10n.confirm,
            style: theme.textTheme.labelLarge?.copyWith(
              color: _canSubmit
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompletedView(
    ThemeData theme,
    AppLocalizations l10n,
    AppSemanticColors semanticColors,
    AppShapeTokens shapeTokens,
  ) {
    if (widget.isCancelled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(shapeTokens.buttonRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.block_outlined,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              l10n.agentAskUserCancelled,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    final custom = widget.customText?.trim();
    final hasCustom = custom != null && custom.isNotEmpty;
    final options = widget.selectedOptions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (options.isNotEmpty) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                size: 16,
                color: semanticColors.success,
              ),
              const SizedBox(width: 6),
              Text(
                l10n.agentAskUserSelectedPrefix,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: options.map((opt) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(shapeTokens.buttonRadius),
                ),
                child: Text(
                  opt,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              );
            }).toList(growable: false),
          ),
        ],
        if (hasCustom) ...[
          if (options.isNotEmpty) const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.comment_outlined,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${l10n.agentAskUserCustomPrefix}$custom',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (options.isEmpty && !hasCustom)
          Row(
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                size: 16,
                color: semanticColors.success,
              ),
              const SizedBox(width: 6),
              Text(
                l10n.confirm,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
