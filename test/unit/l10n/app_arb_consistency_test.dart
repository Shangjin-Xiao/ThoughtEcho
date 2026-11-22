import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thoughtecho/gen_l10n/app_localizations.dart';

void main() {
  group('ARB consistency', () {
    test('AppLocalizations default fallback language is English', () {
      expect(AppLocalizations.supportedLocales.first, const Locale('en'));
    });

    test('app_zh.arb exposes the simple operation failure key', () {
      final data = jsonDecode(File('lib/l10n/app_zh.arb').readAsStringSync())
          as Map<String, dynamic>;

      expect(data['operationFailedSimple'], '操作失败');
      expect(data['skipNonFullscreenEditor'], isNotEmpty);
      expect(data['skipNonFullscreenEditorDesc'], isNotEmpty);
    });

    test('app_zh.arb uses treasured wording in periodic reports', () {
      final data = jsonDecode(File('lib/l10n/app_zh.arb').readAsStringSync())
          as Map<String, dynamic>;

      expect(data['mostFavoritedInPeriod'], '本周期珍藏数最多');
    });

    test('app_en.arb exposes direct fullscreen editor strings', () {
      final data = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
          as Map<String, dynamic>;

      expect(data['skipNonFullscreenEditor'], isNotEmpty);
      expect(data['skipNonFullscreenEditorDesc'], isNotEmpty);
    });

    test('ARB files follow UX writing guidelines without technical jargon', () {
      final zh = jsonDecode(File('lib/l10n/app_zh.arb').readAsStringSync())
          as Map<String, dynamic>;
      final en = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
          as Map<String, dynamic>;

      expect(zh['openapiCompatible'], 'OpenAI 兼容');
      expect(en['openapiCompatible'], 'OpenAI Compatible');

      expect(zh['databaseMaintenance'], '本地存储维护优化');
      expect(en['databaseMaintenance'], 'Storage Optimization');

      expect(zh['mergeConfirmDialogItem1'], isNot(contains('wins')));
      expect(en['mergeConfirmDialogItem1'], isNot(contains('Wins')));

      expect(zh['leaveWhileSyncing'], isNot(contains('服务器')));
      expect(en['leaveWhileSyncing'], isNot(contains('server')));
    });

    test(
        'app_zh_Hant.arb contains all keys from app_zh.arb and preserves placeholders',
        () {
      final zh = jsonDecode(File('lib/l10n/app_zh.arb').readAsStringSync())
          as Map<String, dynamic>;
      final zhHant =
          jsonDecode(File('lib/l10n/app_zh_Hant.arb').readAsStringSync())
              as Map<String, dynamic>;

      expect(zhHant['@@locale'], 'zh_Hant');

      final zhKeys = zh.keys.where((k) => !k.startsWith('@')).toSet();
      final zhHantKeys = zhHant.keys.where((k) => !k.startsWith('@')).toSet();

      final missingKeys = zhKeys.difference(zhHantKeys);
      expect(missingKeys, isEmpty,
          reason:
              'app_zh_Hant.arb should contain all translation keys from app_zh.arb');

      expect(zhHant['appTitle'], '心跡');
      expect(zhHant['languageChinese'], '簡體中文');
      expect(zhHant['languageTraditionalChinese'], '繁體中文');
    });

    test(
        'AI settings, dual-mode routing, and model attribution keys exist across locales without technical jargon',
        () {
      final zh = jsonDecode(File('lib/l10n/app_zh.arb').readAsStringSync())
          as Map<String, dynamic>;
      final en = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
          as Map<String, dynamic>;
      final zhHant =
          jsonDecode(File('lib/l10n/app_zh_Hant.arb').readAsStringSync())
              as Map<String, dynamic>;

      const requiredKeys = [
        'aiServiceEntrySectionTitle',
        'aiServiceEntrySummaryDefault',
        'aiServiceEntrySummaryTieredLight',
        'aiServiceEntrySummaryCustom',
        'aiFeaturesSectionTitle',
        'aiServiceConfigTitle',
        'aiModelAllocationSectionTitle',
        'aiRoutingModeTiered',
        'aiRoutingModeCustom',
        'aiRoutingTieredDesc',
        'aiTierPrimaryTitle',
        'aiTierPrimaryTasksHint',
        'aiTierLightTitle',
        'aiTierLightTasksHint',
        'lightModelBadge',
        'aiTaskCardGenerationTitle',
        'aiTaskSessionTitleTitle',
        'aiTaskBadgeCardGeneration',
        'aiTaskBadgeSessionTitle',
        'aiTaskCardGenerationHint',
        'aiTaskSessionTitleHint',
        'toolProgressModelUsed',
      ];

      for (final key in requiredKeys) {
        expect(zh[key], isA<String>(), reason: 'Missing $key in app_zh.arb');
        expect((zh[key] as String).trim(), isNotEmpty);
        expect(en[key], isA<String>(), reason: 'Missing $key in app_en.arb');
        expect((en[key] as String).trim(), isNotEmpty);
        expect(zhHant[key], isA<String>(),
            reason: 'Missing $key in app_zh_Hant.arb');
        expect((zhHant[key] as String).trim(), isNotEmpty);

        // UX writing gate: user-facing copy must not leak internal jargon
        for (final value in [zh[key] as String, zhHant[key] as String]) {
          expect(value, isNot(contains('Dreaming')));
          expect(value, isNot(contains('SVG')));
          expect(value, isNot(contains('Token')));
          expect(value, isNot(contains('无状态回退')));
          expect(value, isNot(contains('路由槽位')));
        }
      }

      expect(zh['agentMemoryManageTitle'], '查看与管理记忆');
      expect(zh['dreamingEnableTitle'], '自动整理记忆');
      expect(zh['dreamingEnableTitle'], isNot(contains('Dreaming')));
    });
  });
}
