import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:thoughtecho/config/release_highlights.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/release_highlight.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/theme/app_theme.dart';
import 'package:thoughtecho/theme/theme_style.dart';
import 'package:thoughtecho/utils/theme_style_labels.dart';
import 'package:thoughtecho/widgets/app_snackbar.dart';
import 'package:thoughtecho/widgets/theme_style_preview.dart';

/// 更新说明页：精致美观的一页式设计，信息清晰、排版通透。
///
/// 升级路径上它取代了两个一次性弹窗（默认外观变更提示、Sentry 隐私披露）。
/// 弹窗只能回答「弹过没有」，装不下内容，也没法在用户跨几个版本升级时把中间
/// 漏掉的内容补上；这一页按版本记账，跨几版就列几版。
class ReleaseNotesPage extends StatelessWidget {
  /// 升级后自动展示：只列出 [lastSeenVersion] 之后新增的内容，底部给一个
  /// 「开始使用」作为出口。
  const ReleaseNotesPage.sinceUpgrade({
    super.key,
    required String lastSeenVersion,
  }) : _lastSeenVersion = lastSeenVersion;

  /// 设置页主动查看：列出当前版本的全部内容，靠 AppBar 的返回键退出。
  ///
  /// 这里**不做**「已经看过就不显示」的过滤——主动点进来的人要看的就是这些。
  const ReleaseNotesPage.currentRelease({super.key}) : _lastSeenVersion = null;

  /// 非空表示这是升级后自动弹出的那一次。
  final String? _lastSeenVersion;

  bool get _isUpgrade => _lastSeenVersion != null;

  /// 冷启动时检查有没有该给用户看的更新内容，有就展示。
  ///
  /// **先记账再展示**：用户按返回键退出也算看过，否则每次冷启动都会再拦一次。
  static Future<void> checkAndShow(BuildContext context) async {
    if (!context.mounted) return;

    final settings = context.read<SettingsService>();
    final lastSeenVersion = settings.lastSeenReleaseVersion;
    final pending = ReleaseHighlights.since(
      AppLocalizations.of(context),
      lastSeenVersion,
    );

    // 没有内容可看时也要记账：老用户的兜底基线（见 lastSeenReleaseVersion）
    // 是每次现推的，不落盘的话下一版还要再推一次。
    await settings.setLastSeenReleaseVersion(ReleaseHighlights.latestVersion);
    if (pending.isEmpty || !context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ReleaseNotesPage.sinceUpgrade(lastSeenVersion: lastSeenVersion),
      ),
    );
  }

  /// 页头那个大号版本号：只取主次版本，`4.0.0` 显示成 `4.0`。
  /// 修订号是修 bug 的，不配占这个位置。
  static String get _headlineVersion {
    final parts = ReleaseHighlights.latestVersion.split('.');
    return parts.length >= 2 ? '${parts[0]}.${parts[1]}' : parts.first;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final shape = AppShapeTokens.of(context);

    final entries = _isUpgrade
        ? ReleaseHighlights.since(l10n, _lastSeenVersion!)
        : ReleaseHighlights.currentRelease(l10n);

    final features = entries.where((entry) => !entry.isFootnote).toList();
    final footnotes = entries.where((entry) => entry.isFootnote).toList();

    // 版本分段只在真的跨了多个版本时才出现：只升了一版还标一个版本号，是在
    // 重复页头已经写着的信息。
    final versions = <String>[];
    for (final entry in features) {
      if (!versions.contains(entry.version)) versions.add(entry.version);
    }
    final showVersionLabels = versions.length > 1;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.releaseNotesTitle),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _HeroHeader(
                    headlineVersion: _headlineVersion,
                    isUpgrade: _isUpgrade,
                  ),
                  const SizedBox(height: 14),
                  for (final version in versions) ...[
                    if (showVersionLabels) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _VersionPill(version: version),
                      ),
                    ],
                    for (final entry
                        in features.where((e) => e.version == version)) ...[
                      _HighlightCard(entry: entry),
                      const SizedBox(height: 14),
                    ],
                  ],
                  for (final footnote in footnotes) ...[
                    _FootnoteCard(footnote: footnote),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 4),
                  const _GitHubReleaseButton(),
                ],
              ),
            ),
            if (_isUpgrade)
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(
                    top: BorderSide(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.4),
                    ),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(shape.buttonRadius),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: Text(
                      l10n.releaseNotesGetStarted,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 优雅大气的页头 Hero 区域：展示版本指示、应用名与导语。
class _HeroHeader extends StatelessWidget {
  const _HeroHeader({
    required this.headlineVersion,
    required this.isUpgrade,
  });

  final String headlineVersion;
  final bool isUpgrade;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final shape = AppShapeTokens.of(context);
    final iconRadius = (shape.buttonRadius - 2).clamp(6.0, 12.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(shape.cardRadius),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(iconRadius),
            ),
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 22,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'ThoughtEcho',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer
                            .withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(
                          (shape.buttonRadius - 4).clamp(4.0, 8.0),
                        ),
                      ),
                      child: Text(
                        'v$headlineVersion',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  isUpgrade
                      ? l10n.releaseNotesUpgradeLede
                      : l10n.releaseNotesCurrentLede,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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

/// 跨版本升级时的版本分段指示标签。
class _VersionPill extends StatelessWidget {
  const _VersionPill({required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = AppShapeTokens.of(context);

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(shape.buttonRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.history_rounded,
                size: 14,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 5),
              Text(
                version,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 一条更新功能卡片：图标、标题、导语、「核心亮点」通透分条，以及可选的行内交互。
class _HighlightCard extends StatelessWidget {
  const _HighlightCard({required this.entry});

  final ReleaseHighlight entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = AppShapeTokens.of(context);
    final title = entry.title;
    final iconRadius = (shape.buttonRadius - 2).clamp(6.0, 10.0);

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shape.cardRadius),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry.icon != null) ...[
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer
                          .withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(iconRadius),
                    ),
                    child: Icon(
                      entry.icon,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (title != null) ...[
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                      ],
                      Text(
                        entry.lede,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (entry.points.isNotEmpty) ...[
              const SizedBox(height: 12),
              Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < entry.points.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _PointTile(point: entry.points[i]),
              ],
            ],
            if (entry.action == ReleaseHighlightAction.themeStyle) ...[
              const SizedBox(height: 14),
              const _ThemeStylePicker(),
            ],
          ],
        ),
      ),
    );
  }
}

/// 单个核心亮点条目：轻量图标、标题与简明说明。
class _PointTile extends StatelessWidget {
  const _PointTile({required this.point});

  final ReleaseHighlightPoint point;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = AppShapeTokens.of(context);
    final iconRadius = (shape.buttonRadius - 4).clamp(4.0, 8.0);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (point.icon != null) ...[
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(iconRadius),
            ),
            child: Icon(
              point.icon,
              size: 15,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                point.title,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                point.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 行内的主题风格交互演示器：打横排列的紧凑选择器，点击即刻换装。
class _ThemeStylePicker extends StatelessWidget {
  const _ThemeStylePicker();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final appTheme = context.watch<AppTheme>();
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Row(
      children: [
        for (final style in ThemeStyle.values) ...[
          if (style != ThemeStyle.values.first) const SizedBox(width: 8),
          Expanded(
            child: _ThemeStyleOptionTile(
              style: style,
              selected: appTheme.themeStyle == style,
              onSelected: () => appTheme.setThemeStyle(style),
              brightness: brightness,
              l10n: l10n,
            ),
          ),
        ],
      ],
    );
  }
}

/// 风格选择单项（打横紧凑卡片）：顶部迷你笔记缩略图，底部名称与勾选状态。
class _ThemeStyleOptionTile extends StatelessWidget {
  const _ThemeStyleOptionTile({
    required this.style,
    required this.selected,
    required this.onSelected,
    required this.brightness,
    required this.l10n,
  });

  final ThemeStyle style;
  final bool selected;
  final VoidCallback onSelected;
  final Brightness brightness;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = AppShapeTokens.of(context);
    final (name, _) = themeStyleLabel(l10n, style);
    final appTheme = context.read<AppTheme>();
    final targetScheme = appTheme.colorSchemeFor(style, brightness);
    final tileRadius = (shape.cardRadius - 2).clamp(4.0, 14.0);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onSelected,
        borderRadius: BorderRadius.circular(tileRadius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                : theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(tileRadius),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
              width: selected ? 1.8 : 0.8,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: ThemeStylePreview(
                  style: style,
                  brightness: brightness,
                  colorScheme: targetScheme,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      name,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.w500,
                        color: selected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.check_circle_rounded,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 脚注型说明卡片（如 Sentry 崩溃诊断隐私披露）。
class _FootnoteCard extends StatelessWidget {
  const _FootnoteCard({required this.footnote});

  final ReleaseHighlight footnote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = AppShapeTokens.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(shape.cardRadius),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            footnote.icon ?? Icons.shield_outlined,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              footnote.lede,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 跳转 GitHub Release 查看详细更新内容的行动卡片。
class _GitHubReleaseButton extends StatelessWidget {
  const _GitHubReleaseButton();

  static const String _latestReleaseUrl =
      'https://github.com/Shangjin-Xiao/ThoughtEcho/releases/latest';

  Future<void> _openGitHub(BuildContext context) async {
    final uri = Uri.parse(_latestReleaseUrl);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        AppSnackBar.error(context, AppLocalizations.of(context).openLinkFailed);
      }
    } catch (_) {
      if (context.mounted) {
        AppSnackBar.error(context, AppLocalizations.of(context).openLinkFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final shape = AppShapeTokens.of(context);
    final iconRadius = (shape.buttonRadius - 2).clamp(4.0, 10.0);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openGitHub(context),
        borderRadius: BorderRadius.circular(shape.cardRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(shape.cardRadius),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: 0.8,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer
                      .withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(iconRadius),
                ),
                child: Icon(
                  Icons.description_outlined,
                  size: 18,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.releaseNotesViewDetailedChangelog,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'github.com/Shangjin-Xiao/ThoughtEcho',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.open_in_new_rounded,
                size: 16,
                color: theme.colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
