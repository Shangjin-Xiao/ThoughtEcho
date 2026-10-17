import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thoughtecho/services/version_check_service.dart';
import 'package:thoughtecho/utils/update_dialog_helper.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';

void main() {
  group('UpdateDialogHelper Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('should not show dialog if version is ignored', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (BuildContext context) {
              return ElevatedButton(
                onPressed: () async {
                  final versionInfo = VersionInfo(
                    currentVersion: '1.0.0',
                    latestVersion: '1.0.1',
                    downloadUrl: 'url',
                    releaseNotes: 'notes',
                    publishedAt: DateTime.now(),
                    hasUpdate: true,
                  );

                  // Set the version as ignored
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('ignored_update_version', '1.0.1');

                  await UpdateDialogHelper.showUpdateDialog(
                    context,
                    versionInfo,
                  );
                },
                child: const Text('Show Dialog'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Verify that the bottom sheet is not shown
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('should show dialog if version is not ignored', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (BuildContext context) {
              return ElevatedButton(
                onPressed: () async {
                  final versionInfo = VersionInfo(
                    currentVersion: '1.0.0',
                    latestVersion: '1.0.2',
                    downloadUrl: 'url',
                    releaseNotes: 'notes',
                    publishedAt: DateTime.now(),
                    hasUpdate: true,
                  );

                  // Set a different version as ignored to verify non-matching version is not suppressed
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('ignored_update_version', '1.0.1');

                  await UpdateDialogHelper.showUpdateDialog(
                    context,
                    versionInfo,
                  );
                },
                child: const Text('Show Dialog'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Verify that the bottom sheet is shown
      expect(find.byType(BottomSheet), findsOneWidget);
    });
  });
}
