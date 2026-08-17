import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/config/release_highlights.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/release_highlight.dart';
import 'package:thoughtecho/utils/version_utils.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  group('登记表本身', () {
    test('latestVersion 不小于任何一条内容的版本', () {
      // 忘了抬 latestVersion，新加的条目永远进不了 since() 的区间，
      // 也永远不会展示给任何人——这个用例就是为了让那次遗漏在这里失败。
      //
      // **必须遍历全表**（since + earliestVersion），不能遍历 currentRelease：
      // 后者本身就按 `version == latestVersion` 过滤，遍历到的每一条都恰好等于
      // latestVersion，断言恒真；真漏抬的那一条压根不在集合里。
      final entries =
          ReleaseHighlights.since(l10n, ReleaseHighlights.earliestVersion);

      expect(entries, isNotEmpty);
      for (final entry in entries) {
        expect(
          compareVersions(entry.version, ReleaseHighlights.latestVersion),
          lessThanOrEqualTo(0),
          reason: '${entry.title} 的版本高于 latestVersion',
        );
      }
    });

    test('每条内容都有导语，非脚注条目都有标题', () {
      for (final entry
          in ReleaseHighlights.since(l10n, ReleaseHighlights.earliestVersion)) {
        expect(entry.lede, isNotEmpty);
        if (!entry.isFootnote) {
          expect(entry.title, isNotNull);
          expect(entry.title, isNotEmpty);
        }
      }
    });

    test('崩溃诊断说明挂在 3.7.0 上，并且是脚注', () {
      final entries =
          ReleaseHighlights.since(l10n, ReleaseHighlights.earliestVersion);
      final footnotes = entries.where((e) => e.isFootnote).toList();

      expect(footnotes, hasLength(1));
      expect(
          footnotes.single.version, ReleaseHighlights.sentryDisclosureVersion);
      expect(ReleaseHighlights.sentryDisclosureVersion, '3.7.0');
    });

    test('主题那条带一个行内切换器，且全表只有一个', () {
      final entries =
          ReleaseHighlights.since(l10n, ReleaseHighlights.earliestVersion);
      final withAction = entries
          .where((e) => e.action == ReleaseHighlightAction.themeStyle)
          .toList();

      expect(withAction, hasLength(1));
    });
  });

  group('since 的区间', () {
    test('3.7.0 之前的用户看到全部，含崩溃诊断说明', () {
      final entries = ReleaseHighlights.since(l10n, '3.6.5');

      expect(entries.any((e) => e.isFootnote), isTrue);
      expect(entries.any((e) => e.version == '4.0.0'), isTrue);
    });

    test('3.7.0 及之后升上来的用户不再看到崩溃诊断说明', () {
      // 弹窗时代那条披露已经给他看过了，不该借着这一版再来一次。
      for (final lastSeen in ['3.7.0', '3.8.0', '3.9.9']) {
        final entries = ReleaseHighlights.since(l10n, lastSeen);
        expect(
          entries.any((e) => e.isFootnote),
          isFalse,
          reason: '上次看过 $lastSeen 的用户不该再看到脚注',
        );
        expect(entries.any((e) => e.version == '4.0.0'), isTrue);
      }
    });

    test('已经看过最新版的用户什么都看不到', () {
      expect(
        ReleaseHighlights.since(l10n, ReleaseHighlights.latestVersion),
        isEmpty,
      );
    });

    test('版本号按数字比较：3.10 比 3.7 新', () {
      // 按字符串比会把 3.10 当成旧版，于是给一个已经看过的用户重放全部内容。
      final entries = ReleaseHighlights.since(l10n, '3.10.0');
      expect(entries.any((e) => e.isFootnote), isFalse);
    });

    test('currentRelease 不做区间过滤，看过也照样列出来', () {
      final current = ReleaseHighlights.currentRelease(l10n);

      expect(current, isNotEmpty);
      expect(
        current.every((e) => e.version == ReleaseHighlights.latestVersion),
        isTrue,
      );
    });
  });
}
