import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApiService local-only fallback logic', () {
    test('useLocalOnly + tagOnly 在没有本地内容时返回历史每日一言空状态', () async {
      final l10n = lookupAppLocalizations(const Locale('zh'));

      final result = await ApiService.getDailyQuote(
        l10n,
        'a',
        useLocalOnly: true,
        offlineQuoteSource: 'tagOnly',
        databaseService: null,
      );

      expect(result['content'], l10n.noLocalSavedQuotes);
      expect(result['type'], 'local-empty');
    });

    test('useLocalOnly + allNotes 在没有本地内容时仍可使用默认一言', () async {
      final l10n = lookupAppLocalizations(const Locale('zh'));

      final result = await ApiService.getDailyQuote(
        l10n,
        'a',
        useLocalOnly: true,
        offlineQuoteSource: 'allNotes',
        databaseService: null,
      );

      final defaultQuotes = [
        l10n.defaultQuote1,
        l10n.defaultQuote2,
        l10n.defaultQuote3,
      ];

      expect(defaultQuotes.contains(result['content']), isTrue);
    });
  });
}
