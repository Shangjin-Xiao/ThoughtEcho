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
  });
}
