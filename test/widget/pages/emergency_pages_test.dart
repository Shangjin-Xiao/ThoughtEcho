import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/main.dart';

Widget _buildTestWidget(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.deepPurple,
        brightness: Brightness.light,
      ),
    ),
    home: child,
  );
}

void main() {
  testWidgets(
      'EmergencyRecoveryPage renders title, icons and buttons correctly',
      (WidgetTester tester) async {
    await tester.pumpWidget(_buildTestWidget(const EmergencyRecoveryPage()));
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byType(OutlinedButton), findsOneWidget);
  });

  testWidgets('EmergencyHomePage renders error cards correctly',
      (WidgetTester tester) async {
    await tester.pumpWidget(_buildTestWidget(
      const EmergencyHomePage(
        error: 'Database Corrupted Test Error',
        stackTrace: 'Stack trace details line 1\nStack trace details line 2',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Database Corrupted Test Error'), findsOneWidget);
    expect(find.byType(Card), findsAtLeastNWidgets(1));
    expect(find.byType(FilledButton), findsNWidgets(2));
    expect(find.byType(OutlinedButton), findsOneWidget);
  });

  testWidgets('EmergencyBackupPage renders backup tool options correctly',
      (WidgetTester tester) async {
    await tester.pumpWidget(_buildTestWidget(const EmergencyBackupPage()));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.data_saver_on), findsOneWidget);
    expect(find.byType(FilledButton), findsNWidgets(2));
  });
}
