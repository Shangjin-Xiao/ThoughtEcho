import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/onboarding_config.dart';
import '../../gen_l10n/app_localizations.dart';
import '../../models/onboarding_models.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_style.dart';
import '../../utils/theme_style_labels.dart';
import 'onboarding_section.dart';

/// 第 2 屏：外观风格 + 每日一言来源。
///
/// 放在一起是因为这两项都是「看得见的结果」——选完立刻能在屏幕上看到变化，
/// 适合放在用户还没进应用、没有判断依据的时候问。
class AppearancePageView extends StatelessWidget {
  const AppearancePageView({
    super.key,
    required this.pageData,
    required this.state,
    required this.onPreferenceChanged,
  });

  final OnboardingPageData pageData;
  final OnboardingState state;
  final void Function(String key, dynamic value) onPreferenceChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return OnboardingPageScaffold(
      title: pageData.title,
      subtitle: pageData.subtitle,
      children: [
        OnboardingSection(
          icon: Icons.palette_outlined,
          title: l10n.themeStyle,
          description: l10n.onboardingThemeStyleDesc,
          child: const _ThemeStylePicker(),
        ),
        _DailyQuoteSection(
          state: state,
          onPreferenceChanged: onPreferenceChanged,
        ),
      ],
    );
  }
}

/// 风格选择：三张缩略预览横排。
///
/// 预览不是三条色带，而是一张缩小的「纸」——底色、卡片、几行墨、一点强调色，
/// 并且圆角、描边、投影都取自**该风格自己**的 [ThemeStyleForm]。
/// 这三样比颜色更能表达风格差异，只换颜色的预览三张看起来会一模一样。
class _ThemeStylePicker extends StatelessWidget {
  const _ThemeStylePicker();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final appTheme = context.watch<AppTheme>();
    final current = appTheme.themeStyle;
    final (_, currentDescription) = themeStyleLabel(l10n, current);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final style in ThemeStyle.values) ...[
              if (style != ThemeStyle.values.first) const SizedBox(width: 12),
              Expanded(
                child: _ThemeStyleOption(
                  style: style,
                  selected: style == current,
                  onTap: () => appTheme.setThemeStyle(style),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        // 说明只显示当前选中那一项：三张卡各带一段说明会把这块挤成文字墙。
        Text(
          currentDescription,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ThemeStyleOption extends StatelessWidget {
  const _ThemeStyleOption({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final ThemeStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final (name, _) = themeStyleLabel(l10n, style);

    return Semantics(
      selected: selected,
      button: true,
      // 跨三张卡是同一组互斥单选，不声明的话读屏会读成三个独立按钮。
      inMutuallyExclusiveGroup: true,
      label: name,
      child: InkWell(
        borderRadius: BorderRadius.circular(
          AppShapeTokens.of(context).cardRadius,
        ),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              _ThemeStylePreview(style: style, selected: selected),
              const SizedBox(height: 8),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: selected ? theme.colorScheme.primary : null,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一张风格缩略图。所有取值都来自 [style]，不读当前主题——
/// 否则三张预览会全部长成当前生效风格的样子。
class _ThemeStylePreview extends StatelessWidget {
  const _ThemeStylePreview({required this.style, required this.selected});

  final ThemeStyle style;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final tokens = AppShapeTokens.fromForm(style.form, brightness);
    final colors = style.palette?.forBrightness(brightness);

    // material 没有固定色板（色值由取色算法生成），拿当前生效的 ColorScheme 代表它。
    final scheme = theme.colorScheme;
    final background = colors?.background ?? scheme.surface;
    final card = colors?.card ?? scheme.surfaceContainerLowest;
    final ink = colors?.ink ?? scheme.onSurface;
    final inkMuted = colors?.inkMuted ?? scheme.onSurfaceVariant;
    // 引导页只介绍风格，不介绍墨色，所以取这套风格的默认那支墨。
    final accent = colors == null
        ? scheme.primary
        : ThemeAccentColors.resolve(style.defaultAccent, colors, brightness)
            .accent;
    final outline = colors?.outline ?? scheme.outlineVariant;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 76,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(tokens.cardRadius),
        border: Border.all(
          color: selected ? scheme.primary : outline,
          width: selected ? 2 : (tokens.borderWidth > 0 ? 1 : 0.5),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(tokens.buttonRadius),
          boxShadow: tokens.lowShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _InkLine(color: ink, widthFactor: 0.85, height: 4),
            const SizedBox(height: 6),
            _InkLine(color: inkMuted, widthFactor: 0.65, height: 3),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  width: 14,
                  height: 5,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius:
                        BorderRadius.circular(tokens.buttonRadius / 2),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _InkLine(color: inkMuted, widthFactor: 0.7, height: 3),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 预览里代表一行字的墨条。
class _InkLine extends StatelessWidget {
  const _InkLine({
    required this.color,
    required this.widthFactor,
    required this.height,
  });

  final Color color;
  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(height / 2),
        ),
      ),
    );
  }
}

/// 每日一言：服务方单选，以及只对 Hitokoto 有效的类型细分。
class _DailyQuoteSection extends StatefulWidget {
  const _DailyQuoteSection({
    required this.state,
    required this.onPreferenceChanged,
  });

  final OnboardingState state;
  final void Function(String key, dynamic value) onPreferenceChanged;

  @override
  State<_DailyQuoteSection> createState() => _DailyQuoteSectionState();
}

class _DailyQuoteSectionState extends State<_DailyQuoteSection> {
  bool _typesExpanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final providerPreference =
        OnboardingConfig.preferenceByKey(context, 'dailyQuoteProvider');
    if (providerPreference == null) return const SizedBox.shrink();

    final selectedProvider =
        widget.state.getPreference<String>('dailyQuoteProvider') ??
            providerPreference.defaultValue as String;
    // 语言变化时控制器会顺带改写 provider，这里的「推荐」标记要跟着当前语言走，
    // 否则用户切成日语后仍会看到中文源被标成推荐。
    final recommended = ApiService.recommendedDailyQuoteProviderForLanguage(
      Localizations.localeOf(context).toLanguageTag(),
    );

    return OnboardingSection(
      icon: Icons.format_quote_rounded,
      title: providerPreference.title,
      description: providerPreference.description,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RadioGroup<String>(
            groupValue: selectedProvider,
            onChanged: (value) {
              if (value != null) {
                widget.onPreferenceChanged('dailyQuoteProvider', value);
              }
            },
            child: Column(
              children: [
                for (final option in providerPreference.options ?? [])
                  RadioListTile<String>(
                    value: option.value as String,
                    title: Row(
                      children: [
                        Flexible(child: Text(option.label)),
                        if (option.value == recommended) ...[
                          const SizedBox(width: 8),
                          _RecommendedBadge(
                              label: l10n.onboardingProviderRecommended),
                        ],
                      ],
                    ),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
          if (ApiService.supportsHitokotoTypeSelection(selectedProvider))
            _HitokotoTypes(
              state: widget.state,
              expanded: _typesExpanded,
              onToggleExpanded: () =>
                  setState(() => _typesExpanded = !_typesExpanded),
              onPreferenceChanged: widget.onPreferenceChanged,
            ),
        ],
      ),
    );
  }
}

/// 「按你选的语言推荐」小标。
class _RecommendedBadge extends StatelessWidget {
  const _RecommendedBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = AppShapeTokens.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(shape.buttonRadius),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

/// 一言类型细分。默认全选并折叠：11 个类型摊开是这一屏最重的一块，
/// 而新用户对「动画 / 文学 / 网络」这些分类没有判断依据，先给最丰富的内容更合理。
class _HitokotoTypes extends StatelessWidget {
  const _HitokotoTypes({
    required this.state,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onPreferenceChanged,
  });

  final OnboardingState state;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final void Function(String key, dynamic value) onPreferenceChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final preference =
        OnboardingConfig.preferenceByKey(context, 'hitokotoTypes');
    if (preference == null) return const SizedBox.shrink();

    final options = preference.options ?? [];
    final value = state.getPreference<String>('hitokotoTypes') ??
        preference.defaultValue as String;
    final selected = value.split(',').where((v) => v.isNotEmpty).toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        InkWell(
          onTap: onToggleExpanded,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.onboardingCustomizeTypes,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Text(
                  l10n.selectedCount(selected.length),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    Icons.expand_more_rounded,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        // 用 AnimatedSize + 条件构建，而不是 AnimatedCrossFade：后者两棵子树都会
        // 一直留在树里，「折叠」状态下这 11 个 chip 照样构建和参与语义树，
        // 等于没收起来。
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: expanded
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final option in options)
                        _TypeChip(
                          label: option.label,
                          selected: selected.contains(option.value as String),
                          onSelected: (isSelected) {
                            final next = Set<String>.from(selected);
                            if (isSelected) {
                              next.add(option.value as String);
                            } else {
                              next.remove(option.value as String);
                              // 一个都不选会让每日一言取不到内容，至少留一个。
                              if (next.isEmpty && options.isNotEmpty) {
                                next.add(options.first.value as String);
                              }
                            }
                            onPreferenceChanged(
                              'hitokotoTypes',
                              next.join(','),
                            );
                          },
                        ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = AppShapeTokens.of(context);

    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
      // 引导页里这些 chip 有 11 个，投影会让它们看起来像一片浮起的按钮群，
      // 所以统一压平，只靠底色和描边区分选中态。
      elevation: 0,
      pressElevation: 0,
      backgroundColor: Colors.transparent,
      selectedColor: theme.colorScheme.primaryContainer,
      side: BorderSide(
        color: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.outlineVariant,
        width: selected ? 1.5 : 1,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shape.buttonRadius),
      ),
      labelStyle: theme.textTheme.labelLarge?.copyWith(
        color: selected
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurfaceVariant,
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}
