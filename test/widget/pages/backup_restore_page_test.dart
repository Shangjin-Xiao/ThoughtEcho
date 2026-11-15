import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/pages/backup_restore_page.dart';
import 'package:thoughtecho/services/backup_service.dart';
import 'package:thoughtecho/services/large_file_manager.dart';
import 'package:thoughtecho/services/media_sync_manifest.dart';

class _MockBackupService extends Mock implements BackupService {
  @override
  List<String> get lastExportDeltaConversionFailures => [];

  @override
  Future<String> exportAllData({
    required bool includeMediaFiles,
    MediaSyncManifest? receiverMediaManifest,
    String? customPath,
    Function(int current, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    return '/tmp/test_backup.zip';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('BackupRestorePage renders backup section and expandable scope', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockBackupService = _MockBackupService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [Provider<BackupService>.value(value: mockBackupService)],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('zh'),
          home: BackupRestorePage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

    expect(find.text(l10n.dataBackup), findsOneWidget);
    expect(find.text(l10n.createBackup), findsOneWidget);
    expect(find.text(l10n.backupScopeTitle), findsOneWidget);
    expect(find.text(l10n.backupScopeSubtitle), findsOneWidget);

    // Scope details start collapsed.
    expect(find.text(l10n.backupScopeIncludedHeader), findsNothing);
    expect(find.text(l10n.backupScopeExcludedHeader), findsNothing);

    // Expand scope card to verify included/excluded items.
    await tester.tap(find.text(l10n.backupScopeTitle));
    await tester.pumpAndSettle();

    expect(find.text(l10n.backupScopeIncludedHeader), findsOneWidget);
    expect(find.text(l10n.backupScopeIncludedNotes), findsOneWidget);
    expect(find.text(l10n.backupScopeIncludedMedia), findsOneWidget);
    expect(find.text(l10n.backupScopeIncludedSettings), findsOneWidget);
    expect(find.text(l10n.backupScopeIncludedAiAnalyses), findsOneWidget);

    expect(find.text(l10n.backupScopeExcludedHeader), findsOneWidget);
    expect(find.text(l10n.backupScopeExcludedCredentials), findsOneWidget);
    expect(find.text(l10n.backupScopeExcludedDrafts), findsOneWidget);
    expect(find.text(l10n.backupScopeExcludedChatsAndMemory), findsOneWidget);
    expect(find.text(l10n.backupScopeExcludedInsightsAndLogs), findsOneWidget);
    expect(find.text(l10n.backupScopeRestoreModeNote), findsOneWidget);
  });
}
