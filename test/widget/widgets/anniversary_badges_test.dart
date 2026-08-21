import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/widgets/anniversary_badges.dart';

Future<void> _pumpBadges(WidgetTester tester, List<int> years) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(
        body: AnniversaryBadgeRow(
          years: years,
          overflowColor: const Color(0xFF0B3D6B),
        ),
      ),
    ),
  );
}

void main() {
  group('AnniversaryBadgeRow', () {
    testWidgets('参与过几届就挂几枚', (tester) async {
      await _pumpBadges(tester, const [1, 2]);

      expect(find.byType(Tooltip), findsNWidgets(2));
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('没有记录时不占位', (tester) async {
      await _pumpBadges(tester, const []);

      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets('超出上限的收进 +N', (tester) async {
      await _pumpBadges(tester, const [1, 2, 3, 4, 5, 6, 7]);

      expect(find.byType(Tooltip), findsNWidgets(5));
      expect(find.text('+2'), findsOneWidget);
      expect(find.text('6'), findsNothing);
    });
  });
}
