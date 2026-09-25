import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../gen_l10n/app_localizations.dart';
import '../../services/agent_tools/ask_user_tool.dart';
import '../../theme/app_semantic_colors.dart';
import '../../theme/theme_style.dart';

/// Agent 向用户提问与选项确认卡片（对齐 Claude Code `AskUserQuestion`）。
///
/// 单个问题时直接展示整块内容；多个问题时走分步向导：一次只展示一题，
/// 顶部是可点击跳转的分段进度，单选点选后自动进入下一题，多选与自定义
/// 输入点「继续」前进，上一步保留已填答案，末尾是可回跳修改的总览页。
/// 每个问题的选项纵向排列为整宽行（短标题 + 说明），单选用 Radio、
/// 多选用 Checkbox。自定义输入与选项选择互斥：输入自定义文本会清空
/// 选项选择，点选选项会清空自定义文本。
///
/// 样式遵循项目 UI 规范：圆角来自 `AppShapeTokens`，语义色来自
/// `AppSemanticColors` / `ColorScheme`，支持手工风格自适应。
class AskUserCard extends StatefulWidget {
  const AskUserCard({
    super.key,
    required this.questions,
    this.initialAnswers = const [],
    this.isCompleted = false,
    this.isCancelled = false,
    this.completedAnswers = const [],
    this.onSubmit,
    this.onCancel,
  });

  final List<AskUserQuestion> questions;

  /// 待回答时的初始答案（与 questions 等长或为空）。
  final List<AskUserAnswer> initialAnswers;

  final bool isCompleted;
  final bool isCancelled;

  /// 已完成时的各问题答案（与 questions 等长或为空）。
  final List<AskUserAnswer> completedAnswers;

  final void Function({
    required List<AskUserAnswer> answers,
  })? onSubmit;

  final VoidCallback? onCancel;

  @override
  State<AskUserCard> createState() => _AskUserCardState();
}

class _QuestionDraft {
  _QuestionDraft({AskUserAnswer? initial})
      : selected = Set<String>.from(initial?.selectedOptions ?? const []),
        custom = TextEditingController(text: initial?.customText ?? '');

  final Set<String> selected;
  final TextEditingController custom;

  void dispose() => custom.dispose();
}

class _AskUserCardState extends State<AskUserCard> {
  late List<_QuestionDraft> _drafts;

  /// 向导当前步骤：0..questions.length-1 为各问题，
  /// 等于 questions.length 时为总览页。单问题卡片不用向导，恒为 0。
  int _currentStep = 0;

  /// 多问题才启用分步向导；单问题保持原来的整块展示。
  bool get _isWizard => widget.questions.length > 1;

  @override
  void initState() {
    super.initState();
    _drafts = _buildDrafts();
  }

  List<_QuestionDraft> _buildDrafts() {
    return List<_QuestionDraft>.generate(
      widget.questions.length,
      (index) => _QuestionDraft(
        initial: index < widget.initialAnswers.length
            ? widget.initialAnswers[index]
            : null,
      ),
      growable: false,
    );
  }

  @override
  void didUpdateWidget(AskUserCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCompleted) return;
    if (!listEquals(oldWidget.questions, widget.questions)) {
      for (final draft in _drafts) {
        draft.dispose();
      }
      _drafts = _buildDrafts();
      _currentStep = 0;
      return;
    }
    if (listEquals(oldWidget.initialAnswers, widget.initialAnswers)) return;
    for (var index = 0; index < _drafts.length; index++) {
      final initial = index < widget.initialAnswers.length
          ? widget.initialAnswers[index]
          : null;
      final draft = _drafts[index];
      if (!setEquals(draft.selected,
          Set<String>.from(initial?.selectedOptions ?? const []))) {
        draft
          ..selected.clear()
          ..selected.addAll(initial?.selectedOptions ?? const []);
      }
      if (draft.custom.text != (initial?.customText ?? '')) {
        draft.custom.text = initial?.customText ?? '';
      }
    }
  }

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  bool _isAnswered(int index) {
    final draft = _drafts[index];
    return draft.selected.isNotEmpty || draft.custom.text.trim().isNotEmpty;
  }

  bool get _canSubmit {
    if (widget.questions.isEmpty) return false;
    for (var index = 0; index < _drafts.length; index++) {
      if (!_isAnswered(index)) return false;
    }
    return true;
  }

  void _handleOptionToggle(int index, String label) {
    if (widget.isCompleted) return;
    final draft = _drafts[index];
    setState(() {
      // 与自定义输入互斥：点选选项即清空手输内容。
      if (draft.custom.text.isNotEmpty) draft.custom.clear();
      final question = widget.questions[index];
      if (question.multiSelect) {
        if (draft.selected.contains(label)) {
          draft.selected.remove(label);
        } else {
          draft.selected.add(label);
        }
      } else {
        if (draft.selected.contains(label)) {
          draft.selected.clear();
        } else {
          draft.selected
            ..clear()
            ..add(label);
        }
      }
    });
    // 向导中单选点选即确认本题：选中后自动进入下一步（或总览页）；
    // 再次点选取消选中时停留在本题。自定义输入与多选走「继续」按钮。
    if (_isWizard &&
        !widget.questions[index].multiSelect &&
        draft.selected.isNotEmpty) {
      _goToStep(index + 1);
    }
  }

  /// 向导步骤跳转（含总览页），顺手收起键盘。
  void _goToStep(int step) {
    final total = widget.questions.length;
    final clamped = step.clamp(0, total);
    if (clamped == _currentStep) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _currentStep = clamped;
    });
  }

  void _handleCustomChanged(int index) {
    if (widget.isCompleted) return;
    final draft = _drafts[index];
    // 与选项选择互斥：开始手输即清空已选选项。
    if (draft.selected.isNotEmpty) {
      setState(draft.selected.clear);
    } else {
      setState(() {});
    }
  }

  void _handleSubmit() {
    if (!_canSubmit) return;
    widget.onSubmit?.call(
      answers: [
        for (final draft in _drafts)
          AskUserAnswer(
            selectedOptions: draft.selected.toList(),
            customText: draft.custom.text.trim().isNotEmpty
                ? draft.custom.text.trim()
                : null,
          ),
      ],
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
            _buildTitle(theme, l10n),
            const SizedBox(height: 12),
            if (widget.isCompleted)
              _buildCompletedView(theme, l10n, semanticColors, shapeTokens)
            else if (_isWizard)
              _buildWizard(theme, l10n, shapeTokens)
            else ...[
              for (var index = 0; index < widget.questions.length; index++) ...[
                if (index > 0) const SizedBox(height: 16),
                _buildQuestionBlock(
                    theme, l10n, shapeTokens, index, widget.questions[index]),
              ],
              const SizedBox(height: 16),
              _buildActions(theme, l10n, shapeTokens),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTitle(ThemeData theme, AppLocalizations l10n) {
    final count = widget.questions.length;
    final title = count > 1
        ? l10n.agentAskUserTitleThoughterMulti(count)
        : l10n.agentAskUserTitleThoughter;
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
            ),
          ),
        ),
      ],
    );
  }

  /// 多问题分步向导：进度条 + 当前一题（或末尾总览页）+ 导航按钮。
  Widget _buildWizard(
    ThemeData theme,
    AppLocalizations l10n,
    AppShapeTokens shapeTokens,
  ) {
    final total = widget.questions.length;
    final isReview = _currentStep >= total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildProgress(theme, l10n, shapeTokens, total, isReview),
        const SizedBox(height: 12),
        if (isReview)
          _buildReview(theme, l10n, shapeTokens)
        else
          _buildQuestionBlock(
            theme,
            l10n,
            shapeTokens,
            _currentStep,
            widget.questions[_currentStep],
          ),
        const SizedBox(height: 16),
        if (isReview)
          _buildReviewActions(theme, l10n, shapeTokens)
        else
          _buildWizardNav(theme, l10n, shapeTokens),
      ],
    );
  }

  /// 分段进度：答过的段填实，点击任意段跳转；旁边标注当前进度。
  Widget _buildProgress(
    ThemeData theme,
    AppLocalizations l10n,
    AppShapeTokens shapeTokens,
    int total,
    bool isReview,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isReview
              ? l10n.agentAskUserReviewTitle
              : l10n.agentAskUserStepOf(_currentStep + 1, total),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var index = 0; index < total; index++) ...[
              if (index > 0) const SizedBox(width: 4),
              Expanded(
                child: Semantics(
                  button: true,
                  label: l10n.agentAskUserStepOf(index + 1, total),
                  child: InkWell(
                    borderRadius:
                        BorderRadius.circular(shapeTokens.buttonRadius),
                    onTap: () => _goToStep(index),
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(shapeTokens.buttonRadius),
                        color: _isAnswered(index)
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant
                                .withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// 向导问题页导航：上一步（首题不占位）+ 取消 + 继续。
  Widget _buildWizardNav(
    ThemeData theme,
    AppLocalizations l10n,
    AppShapeTokens shapeTokens,
  ) {
    final answered = _isAnswered(_currentStep);
    return Row(
      children: [
        if (_currentStep > 0)
          TextButton(
            onPressed: () => _goToStep(_currentStep - 1),
            child: Text(l10n.agentAskUserPrev),
          ),
        const Spacer(),
        if (widget.onCancel != null) ...[
          OutlinedButton(
            onPressed: widget.onCancel,
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(shapeTokens.buttonRadius),
              ),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant,
                width:
                    shapeTokens.borderWidth > 0 ? shapeTokens.borderWidth : 1.0,
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
          onPressed: answered ? () => _goToStep(_currentStep + 1) : null,
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(shapeTokens.buttonRadius),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          ),
          child: Text(
            l10n.agentAskUserNext,
            style: theme.textTheme.labelLarge?.copyWith(
              color: answered
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
    );
  }

  /// 总览页：逐题列出回答，点击回跳修改；提交前最后确认。
  Widget _buildReview(
    ThemeData theme,
    AppLocalizations l10n,
    AppShapeTokens shapeTokens,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < widget.questions.length; index++) ...[
          if (index > 0) const SizedBox(height: 4),
          InkWell(
            borderRadius: BorderRadius.circular(shapeTokens.buttonRadius),
            onTap: () => _goToStep(index),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _isAnswered(index)
                        ? Icons.check_circle_outline_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 18,
                    color: _isAnswered(index)
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.questions[index].question,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _summarizeDraft(index, l10n),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: _isAnswered(index)
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => _goToStep(index),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(l10n.agentAskUserEditAnswer),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _summarizeDraft(int index, AppLocalizations l10n) {
    final draft = _drafts[index];
    final custom = draft.custom.text.trim();
    if (custom.isNotEmpty) return custom;
    if (draft.selected.isNotEmpty) return draft.selected.join('、');
    return l10n.agentAskUserUnanswered;
  }

  /// 总览页操作：取消 + 提交全部（有未答题时禁用并提示）。
  Widget _buildReviewActions(
    ThemeData theme,
    AppLocalizations l10n,
    AppShapeTokens shapeTokens,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_canSubmit)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              l10n.agentAskUserIncompleteHint,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => _goToStep(widget.questions.length - 1),
              child: Text(l10n.agentAskUserPrev),
            ),
            const Spacer(),
            if (widget.onCancel != null) ...[
              OutlinedButton(
                onPressed: widget.onCancel,
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(shapeTokens.buttonRadius),
                  ),
                  side: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                    width: shapeTokens.borderWidth > 0
                        ? shapeTokens.borderWidth
                        : 1.0,
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              ),
              child: Text(
                l10n.agentAskUserSubmitAll,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: _canSubmit
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuestionBlock(
    ThemeData theme,
    AppLocalizations l10n,
    AppShapeTokens shapeTokens,
    int index,
    AskUserQuestion question,
  ) {
    final hintText = question.multiSelect
        ? l10n.agentAskUserMultiSelectHint
        : l10n.agentAskUserSingleSelectHint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (question.header?.trim().isNotEmpty == true)
          _buildHeaderChip(
              theme, shapeTokens, question.header!.trim(), hintText)
        else
          _buildModeHint(theme, shapeTokens, hintText),
        const SizedBox(height: 8),
        Text(
          question.question,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        _buildOptions(theme, shapeTokens, index, question),
        const SizedBox(height: 8),
        _buildCustomInput(theme, l10n, shapeTokens, index),
      ],
    );
  }

  Widget _buildHeaderChip(
    ThemeData theme,
    AppShapeTokens shapeTokens,
    String header, [
    String? hintText,
  ]) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(shapeTokens.buttonRadius),
            border: shapeTokens.borderWidth > 0
                ? Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.4),
                    width: shapeTokens.borderWidth,
                  )
                : null,
          ),
          child: Text(
            header,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (hintText != null)
          Text(
            hintText,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  Widget _buildModeHint(
    ThemeData theme,
    AppShapeTokens shapeTokens,
    String hintText,
  ) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(shapeTokens.buttonRadius),
          border: shapeTokens.borderWidth > 0
              ? Border.all(
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  width: shapeTokens.borderWidth,
                )
              : null,
        ),
        child: Text(
          hintText,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// 选项纵向列表：单选包一层 RadioGroup，多选直接堆 Checkbox 行。
  Widget _buildOptions(
    ThemeData theme,
    AppShapeTokens shapeTokens,
    int index,
    AskUserQuestion question,
  ) {
    final rows = [
      for (final option in question.options)
        _buildOptionRow(theme, shapeTokens, index, question, option),
    ];
    if (question.multiSelect) {
      return Column(children: rows);
    }
    final selected = _drafts[index].selected;
    return RadioGroup<String?>(
      groupValue: selected.length == 1 ? selected.single : null,
      onChanged: (value) {
        if (value != null) _handleOptionToggle(index, value);
      },
      child: Column(children: rows),
    );
  }

  /// 纵向整宽选项行：标题 + 说明，单选 Radio、多选 Checkbox。
  Widget _buildOptionRow(
    ThemeData theme,
    AppShapeTokens shapeTokens,
    int index,
    AskUserQuestion question,
    AskUserOption option,
  ) {
    final isSelected = _drafts[index].selected.contains(option.label);
    final borderColor = isSelected
        ? theme.colorScheme.primary.withValues(alpha: 0.6)
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.5);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isSelected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.6)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(shapeTokens.buttonRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(shapeTokens.buttonRadius),
          onTap: () => _handleOptionToggle(index, option.label),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(shapeTokens.buttonRadius),
              border: Border.all(
                color: borderColor,
                width:
                    shapeTokens.borderWidth > 0 ? shapeTokens.borderWidth : 1.0,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (question.multiSelect)
                  Checkbox(
                    value: isSelected,
                    onChanged: (_) => _handleOptionToggle(index, option.label),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  )
                else
                  Radio<String?>(
                    value: option.label,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isSelected
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                      if (option.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          option.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomInput(
    ThemeData theme,
    AppLocalizations l10n,
    AppShapeTokens shapeTokens,
    int index,
  ) {
    final outlineWidth =
        shapeTokens.borderWidth > 0 ? shapeTokens.borderWidth : 1.0;
    final focusedWidth =
        shapeTokens.borderWidth > 0 ? shapeTokens.borderWidth : 1.5;

    return TextField(
      controller: _drafts[index].custom,
      onChanged: (_) => _handleCustomChanged(index),
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
            width: outlineWidth,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(shapeTokens.inputRadius),
          borderSide: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            width: outlineWidth,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(shapeTokens.inputRadius),
          borderSide: BorderSide(
            color: theme.colorScheme.primary,
            width: focusedWidth,
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
                width:
                    shapeTokens.borderWidth > 0 ? shapeTokens.borderWidth : 1.0,
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
    final answers = [
      for (var index = 0; index < widget.questions.length; index++)
        index < widget.completedAnswers.length
            ? widget.completedAnswers[index]
            : const AskUserAnswer(),
    ];
    final hasAnyAnswer = answers.any((answer) =>
        answer.selectedOptions.isNotEmpty ||
        (answer.effectiveCustomText?.isNotEmpty == true));

    if (widget.isCancelled || !hasAnyAnswer) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < widget.questions.length; index++) ...[
            if (index > 0) const SizedBox(height: 8),
            if (widget.questions[index].header?.trim().isNotEmpty == true) ...[
              _buildHeaderChip(
                  theme, shapeTokens, widget.questions[index].header!.trim()),
              const SizedBox(height: 8),
            ],
            Text(
              widget.questions[index].question,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(shapeTokens.buttonRadius),
              border: shapeTokens.borderWidth > 0
                  ? Border.all(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.5),
                      width: shapeTokens.borderWidth,
                    )
                  : null,
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
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < widget.questions.length; index++) ...[
          if (index > 0) const SizedBox(height: 12),
          _buildCompletedQuestion(
            theme,
            l10n,
            semanticColors,
            shapeTokens,
            widget.questions[index],
            answers[index],
          ),
        ],
      ],
    );
  }

  Widget _buildCompletedQuestion(
    ThemeData theme,
    AppLocalizations l10n,
    AppSemanticColors semanticColors,
    AppShapeTokens shapeTokens,
    AskUserQuestion question,
    AskUserAnswer answer,
  ) {
    final custom = answer.effectiveCustomText;
    final selected = answer.selectedOptions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (question.header?.trim().isNotEmpty == true) ...[
          _buildHeaderChip(theme, shapeTokens, question.header!.trim()),
          const SizedBox(height: 8),
        ],
        Text(
          question.question,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        if (selected.isNotEmpty) ...[
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
            children: selected.map((label) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(shapeTokens.buttonRadius),
                  border: shapeTokens.borderWidth > 0
                      ? Border.all(
                          color:
                              theme.colorScheme.primary.withValues(alpha: 0.4),
                          width: shapeTokens.borderWidth,
                        )
                      : null,
                ),
                child: Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              );
            }).toList(growable: false),
          ),
        ],
        if (custom != null) ...[
          if (selected.isNotEmpty) const SizedBox(height: 8),
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
        if (selected.isEmpty && custom == null)
          Text(
            l10n.agentAskUserUnanswered,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
