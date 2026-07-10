import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/pages/ai_periodic_report_page.dart';
import 'package:thoughtecho/services/ai_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/insight_history_service.dart';
import 'package:thoughtecho/services/settings_service.dart';

class _EmptyPeriodDatabaseService extends DatabaseService {
  _EmptyPeriodDatabaseService() : super.forTesting();

  @override
  Future<List<Quote>> getQuotesForPeriod(
    DateTime start,
    DateTime end, {
    bool excludeHiddenNotes = true,
    bool includeDeleted = false,
  }) async {
    return const [];
  }
}

class _ReportSettingsService extends ChangeNotifier implements SettingsService {
  @override
  bool get reportInsightsUseAI => false;

  @override
  Future<String?> getCustomString(String key) async => null;

  @override
  Future<void> setCustomString(String key, String value) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('SettingsService.${invocation.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('empty period still shows zero statistics and AI entry',
      (tester) async {
    final settings = _ReportSettingsService();
    final database = _EmptyPeriodDatabaseService();
    final insights = InsightHistoryService(settingsService: settings);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<DatabaseService>.value(value: database),
          ChangeNotifierProvider<InsightHistoryService>.value(value: insights),
          ChangeNotifierProvider<AIService>(
            create: (_) => AIService(settingsService: settings),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AIPeriodicReportPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(AIPeriodicReportPage));
    final l10n = AppLocalizations.of(context);
    expect(find.text(l10n.dataOverview), findsOneWidget);
    expect(find.text(l10n.aiChat), findsOneWidget);
    expect(find.text('0'), findsWidgets);
    expect(find.text(l10n.noDataYet), findsWidgets);
  });
}
