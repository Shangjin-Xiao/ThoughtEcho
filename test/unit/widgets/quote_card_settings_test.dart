import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/utils/time_utils.dart';
import 'package:thoughtecho/widgets/quote_card_settings.dart';

class _MockSettingsService extends ChangeNotifier implements SettingsService {
  @override
  bool get showExactTime => true;

  @override
  bool get showNoteEditTime => false;

  @override
  bool get noteListDisableCardShadows => true;

  @override
  String get noteCardMediaStyle => 'banner';

  @override
  bool get prioritizeBoldContentInCollapse => true;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('QuoteCardSettings tests', () {
    test('constructs correctly from SettingsService', () {
      final settings = _MockSettingsService();
      final cardSettings = QuoteCardSettings.fromSettings(settings);

      expect(cardSettings.showExactTime, isTrue);
      expect(cardSettings.showNoteEditTime, isFalse);
      expect(cardSettings.disableCardShadows, isTrue);
      expect(cardSettings.mediaStyle, 'banner');
      expect(cardSettings.prioritizeBoldContent, isTrue);
    });

    test('value equality and hashCode behavior', () {
      const a = QuoteCardSettings(
        showExactTime: true,
        showNoteEditTime: false,
        disableCardShadows: true,
        mediaStyle: 'thumbnail',
        prioritizeBoldContent: false,
      );

      const b = QuoteCardSettings(
        showExactTime: true,
        showNoteEditTime: false,
        disableCardShadows: true,
        mediaStyle: 'thumbnail',
        prioritizeBoldContent: false,
      );

      const c = QuoteCardSettings(
        showExactTime: false,
        showNoteEditTime: false,
        disableCardShadows: true,
        mediaStyle: 'thumbnail',
        prioritizeBoldContent: false,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, isNot(equals(c.hashCode)));
    });
  });

  group('TimeUtils reverse day period map tests', () {
    testWidgets(
        'formatQuoteDateLocalized uses static reverse map without error',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Builder(
            builder: (context) {
              final testDate = DateTime(2026, 5, 20, 9, 30);
              // Test passing english key
              final resKey = TimeUtils.formatQuoteDateLocalized(
                context,
                testDate,
                dayPeriod: 'morning',
              );
              // Test passing legacy chinese label
              final resLabel = TimeUtils.formatQuoteDateLocalized(
                context,
                testDate,
                dayPeriod: '上午',
              );

              expect(resKey, contains('2026-05-20'));
              expect(resLabel, contains('2026-05-20'));
              expect(resKey, equals(resLabel));

              // Exact time
              final exact = TimeUtils.formatQuoteDateLocalized(
                context,
                testDate,
                dayPeriod: 'morning',
                showExactTime: true,
              );
              expect(exact, contains('09:30'));

              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });
  });
}
