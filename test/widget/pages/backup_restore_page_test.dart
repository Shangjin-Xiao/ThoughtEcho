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

  testWidgets('BackupRestorePage renders backup section correctly', (
    tester,
  ) async {
    final mockBackupService = _MockBackupService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<BackupService>.value(value: mockBackupService),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('zh'),
          home: BackupRestorePage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('数据备份'), findsOneWidget);
    expect(find.text('创建备份'), findsOneWidget);
  });
}
