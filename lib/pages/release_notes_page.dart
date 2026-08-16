import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:thoughtecho/config/release_highlights.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/release_highlight.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/theme/app_theme.dart';
import 'package:thoughtecho/theme/theme_style.dart';
import 'package:thoughtecho/utils/app_logger.dart';
import 'package:thoughtecho/utils/theme_style_labels.dart';

/// 更新说明页：一页滚到底，没有「下一步」。
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
      appBar: AppBar(title: Text(l10n.releaseNotesTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Text(_headlineVersion, style: theme.textTheme.displaySmall),
                  const SizedBox(height: 8),
                  Text(
                    _isUpgrade
                        ? l10n.releaseNotesUpgradeLede
                        : l10n.releaseNotesCurrentLede,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  for (final version in versions) ...[
                    if (showVersionLabels) ...[
                      Text(
                        version,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    for (final entry
                        in features.where((e) => e.version == version)) ...[
                      _HighlightCard(entry: entry),
                      const SizedBox(height: 16),
                    ],
                  ],
                  for (final footnote in footnotes) ...[
                    const SizedBox(height: 8),
                    Text(
                      footnote.lede,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_isUpgrade)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.releaseNotesGetStarted),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 一条更新内容：标题、导语、「核心亮点」分条，以及可选的行内操作。
class _HighlightCard extends StatelessWidget {
  const _HighlightCard({required this.entry});

  final ReleaseHighlight entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final title = entry.title;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
            ],
            Text(
              entry.lede,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (entry.points.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                l10n.releaseNotesHighlights,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < entry.points.length; i++) ...[
                if (i > 0) const SizedBox(height: 16),
                _PointTile(point: entry.points[i]),
              ],
            ],
            if (entry.action == ReleaseHighlightAction.themeStyle) ...[
              const SizedBox(height: 20),
              const _ThemeStylePicker(),
            ],
          ],
        ),
      ),
    );
  }
}

class _PointTile extends StatelessWidget {
  const _PointTile({required this.point});

  final ReleaseHighlightPoint point;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(point.title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          point.description,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 行内的风格切换器：点一下当场换，整页立刻变成新风格——这比任何截图都直观。
///
/// 用 [Wrap] 而不是 `SegmentedButton`：风格名是中文短词加一个 `Material`，
/// 窄屏上分段按钮会挤到截断，而 [Wrap] 会自己换行。
class _ThemeStylePicker extends StatelessWidget {
  const _ThemeStylePicker();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final appTheme = context.watch<AppTheme>();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final style in ThemeStyle.values)
          ChoiceChip(
            label: Text(themeStyleLabel(l10n, style).$1),
            selected: appTheme.themeStyle == style,
            onSelected: (selected) {
              if (!selected) return;
              appTheme.setThemeStyle(style).catchError(
                    (Object error) => logError(
                      '更新说明页切换主题风格失败: $error',
                      error: error,
                      source: 'ReleaseNotesPage',
                    ),
                  );
            },
          ),
      ],
    );
  }
}
