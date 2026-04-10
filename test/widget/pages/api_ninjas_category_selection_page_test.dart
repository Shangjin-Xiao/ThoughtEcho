import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/pages/api_ninjas_category_selection_page.dart';

import '../../test_setup.dart';

void main() {
  setUpAll(() async {
    await TestSetup.setupWidgetTest();
  });

  testWidgets('初始化时过滤不支持的分类', (tester) async {
    final localizations =
        await AppLocalizations.delegate.load(const Locale('zh'));

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ApiNinjasCategorySelectionPage(
          initialSelectedCategories: ['wisdom', 'unsupported'],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(localizations.dailyQuoteApiNinjasSelectedCount(1)),
      findsOneWidget,
    );
  });

  testWidgets('API Ninjas 分类页支持搜索和多选', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ApiNinjasCategorySelectionPage(
          initialSelectedCategories: ['wisdom'],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('智慧'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      '成功',
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ListTile, '成功'), findsOneWidget);
    expect(find.text('智慧'), findsNothing);

    await tester.tap(find.widgetWithText(ListTile, '成功'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_rounded), findsWidgets);
  });
}
