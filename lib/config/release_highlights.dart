import 'package:flutter/material.dart';

import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/release_highlight.dart';
import 'package:thoughtecho/utils/version_utils.dart';

/// 更新说明的内容登记处。
///
/// **加新版本 = 往 [_entriesOf] 最前面加条目、把 [latestVersion] 抬到那一版。**
/// 页面、触发时机和「看过没有」的记账都不用动。
///
/// 每条内容只声明自己是哪一版加的（[ReleaseHighlight.version]），显示范围由
/// [since] 按「用户上次看过的版本」算出来。跨几个版本升级就会列出几个版本的
/// 内容，不需要为跨版本单独写逻辑。
class ReleaseHighlights {
  const ReleaseHighlights._();

  /// 登记表里最新的版本号。
  ///
  /// 它同时是三件事的取值：页头显示的版本、用户看完之后记下的版本、以及新装
  /// 用户的记账基线（新装不该看到「更新内容」）。**加条目时必须一起抬**，否则
  /// 新条目永远进不了 [since] 的区间。由 `release_highlights_test.dart` 钉死。
  static const String latestVersion = '4.0.0';

  /// 崩溃诊断说明所属的版本，也就是 Sentry 进项目的那一版。
  ///
  /// 它在这里出现两次用途：登记表里那条脚注的版本号，以及老用户的记账基线
  /// （见 `SettingsService.lastSeenReleaseVersion`）——两处必须是同一个值，
  /// 所以只写这一处。
  static const String sentryDisclosureVersion = '3.7.0';

  /// 记不出上次版本时的最保守基线：当作比任何登记条目都旧，全部显示。
  static const String earliestVersion = '0.0.0';

  /// 全部内容，新版本在前，同版本内按重要性排。
  static List<ReleaseHighlight> _entriesOf(AppLocalizations l10n) => [
        ReleaseHighlight(
          version: '4.0.0',
          title: l10n.releaseThoughterTitle,
          lede: l10n.releaseThoughterLede,
          icon: Icons.psychology_rounded,
          points: [
            ReleaseHighlightPoint(
              title: l10n.releaseThoughterSearchTitle,
              description: l10n.releaseThoughterSearchDesc,
              icon: Icons.saved_search_rounded,
            ),
            ReleaseHighlightPoint(
              title: l10n.releaseThoughterControlTitle,
              description: l10n.releaseThoughterControlDesc,
              icon: Icons.rule_folder_outlined,
            ),
            ReleaseHighlightPoint(
              title: l10n.releaseThoughterSingleNoteTitle,
              description: l10n.releaseThoughterSingleNoteDesc,
              icon: Icons.chat_bubble_outline_rounded,
            ),
            ReleaseHighlightPoint(
              title: l10n.releaseThoughterMemoryTitle,
              description: l10n.releaseThoughterMemoryDesc,
              icon: Icons.psychology_alt_outlined,
            ),
            ReleaseHighlightPoint(
              title: l10n.releaseThoughterInsightTitle,
              description: l10n.releaseThoughterInsightDesc,
              icon: Icons.insights_rounded,
            ),
          ],
        ),
        ReleaseHighlight(
          version: '4.0.0',
          title: l10n.releaseThemeTitle,
          lede: l10n.releaseThemeLede,
          icon: Icons.palette_outlined,
          action: ReleaseHighlightAction.themeStyle,
          points: [
            ReleaseHighlightPoint(
              title: l10n.releaseThemeStylesTitle,
              description: l10n.releaseThemeStylesDesc,
              icon: Icons.auto_stories_outlined,
            ),
            ReleaseHighlightPoint(
              title: l10n.releaseThemeAccentTitle,
              description: l10n.releaseThemeAccentDesc,
              icon: Icons.colorize_outlined,
            ),
            ReleaseHighlightPoint(
              title: l10n.releaseThemeSwitchTitle,
              description: l10n.releaseThemeSwitchDesc,
              icon: Icons.tune_outlined,
            ),
          ],
        ),
        ReleaseHighlight(
          version: sentryDisclosureVersion,
          lede: l10n.releaseDiagnosticsNotice,
          icon: Icons.shield_outlined,
          isFootnote: true,
        ),
      ];

  /// 用户上次看过 [lastSeenVersion] 之后新增的全部内容，顺序同 [_entriesOf]。
  static List<ReleaseHighlight> since(
    AppLocalizations l10n,
    String lastSeenVersion,
  ) =>
      _entriesOf(l10n)
          .where((entry) => compareVersions(entry.version, lastSeenVersion) > 0)
          .toList(growable: false);

  /// 当前版本的全部内容，不做区间过滤。设置页里的「更新内容」入口用它——
  /// 那是主动来看的，不该因为「已经看过」就变成空页。
  static List<ReleaseHighlight> currentRelease(AppLocalizations l10n) =>
      _entriesOf(l10n)
          .where((entry) => compareVersions(entry.version, latestVersion) == 0)
          .toList(growable: false);
}
