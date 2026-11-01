import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Native manifest and metadata i18n consistency', () {
    test('Android Manifest decouples app_name via @string/app_name', () {
      final manifestContent =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

      expect(
        manifestContent,
        contains('android:label="@string/app_name"'),
        reason: 'Application label must reference @string/app_name',
      );
      expect(
        manifestContent,
        isNot(contains('android:label="心迹"')),
        reason: 'Hardcoded Chinese app name should be removed from manifest',
      );
      expect(
        manifestContent,
        contains('android:label="@string/excerpt_intent_label"'),
        reason:
            'Excerpt activity-alias must reference @string/excerpt_intent_label',
      );
    });

    test(
        'Android strings resources provide English fallback and Chinese variants',
        () {
      final defaultStrings = File('android/app/src/main/res/values/strings.xml')
          .readAsStringSync();
      expect(defaultStrings,
          contains('<string name="app_name">ThoughtEcho</string>'));
      expect(
          defaultStrings,
          contains(
              '<string name="excerpt_intent_label">Excerpt to ThoughtEcho</string>'));

      final zhStrings = File('android/app/src/main/res/values-zh/strings.xml')
          .readAsStringSync();
      expect(zhStrings, contains('<string name="app_name">心迹</string>'));
      expect(zhStrings,
          contains('<string name="excerpt_intent_label">摘录到心迹</string>'));

      final zhCnStrings =
          File('android/app/src/main/res/values-zh-rCN/strings.xml')
              .readAsStringSync();
      expect(zhCnStrings, contains('<string name="app_name">心迹</string>'));
      expect(zhCnStrings,
          contains('<string name="excerpt_intent_label">摘录到心迹</string>'));

      final zhTwStrings =
          File('android/app/src/main/res/values-zh-rTW/strings.xml')
              .readAsStringSync();
      expect(zhTwStrings, contains('<string name="app_name">心跡</string>'));
      expect(zhTwStrings,
          contains('<string name="excerpt_intent_label">摘錄到心跡</string>'));
    });

    test('Native strings align with Flutter ARB language definitions', () {
      final enArb = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
          as Map<String, dynamic>;
      final zhArb = jsonDecode(File('lib/l10n/app_zh.arb').readAsStringSync())
          as Map<String, dynamic>;
      final zhHantArb =
          jsonDecode(File('lib/l10n/app_zh_Hant.arb').readAsStringSync())
              as Map<String, dynamic>;

      expect(enArb['appTitle'], 'ThoughtEcho');
      expect(zhArb['appTitle'], '心迹');
      expect(zhHantArb['appTitle'], '心跡');
    });

    test('Windows Runner.rc supports multilingual resource blocks and UTF-8',
        () {
      final rcContent = File('windows/runner/Runner.rc').readAsStringSync();

      expect(rcContent, contains('#pragma code_page(65001)'));
      expect(rcContent, contains('BLOCK "040904e4"'));
      expect(rcContent, contains('BLOCK "080404b0"'));
      expect(
          rcContent, contains('VALUE "Translation", 0x409, 1252, 0x804, 1200'));

      // Check English block content
      final block0409 = rcContent.substring(
        rcContent.indexOf('BLOCK "040904e4"'),
        rcContent.indexOf('BLOCK "080404b0"'),
      );
      expect(block0409, contains('VALUE "FileDescription", "ThoughtEcho"'));
      expect(block0409, contains('VALUE "ProductName", "ThoughtEcho"'));

      // Check Chinese block content
      final block0804 = rcContent.substring(
        rcContent.indexOf('BLOCK "080404b0"'),
        rcContent.indexOf('BLOCK "VarFileInfo"'),
      );
      expect(block0804, contains('VALUE "FileDescription", "心迹"'));
      expect(block0804, contains('VALUE "ProductName", "心迹"'));
    });

    test(
        'Web Manifest file provides static ThoughtEcho metadata and no Chinese variant',
        () {
      final defaultManifest =
          jsonDecode(File('web/manifest.json').readAsStringSync())
              as Map<String, dynamic>;
      expect(defaultManifest['name'], 'ThoughtEcho');
      expect(defaultManifest['short_name'], 'ThoughtEcho');
      expect(defaultManifest['description'], isNotEmpty);

      expect(
        File('web/manifest.zh.json').existsSync(),
        isFalse,
        reason: 'AGENTS.md prohibits adding Web multilingual variants',
      );
    });

    test(
        'Web index.html maintains static metadata without dynamic language script',
        () {
      final htmlContent = File('web/index.html').readAsStringSync();

      expect(htmlContent, contains('<title>ThoughtEcho</title>'));
      expect(
        htmlContent,
        contains(
            '<meta name="apple-mobile-web-app-title" content="ThoughtEcho">'),
      );
      expect(
          htmlContent, contains('<link rel="manifest" href="manifest.json">'));

      expect(htmlContent, isNot(contains('manifest.zh.json')));
      expect(htmlContent, isNot(contains('navigator.language')));
    });
  });
}
