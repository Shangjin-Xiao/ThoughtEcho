import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/main.dart';
import 'package:thoughtecho/pages/backup_restore_page.dart';
import 'package:thoughtecho/services/ai_analysis_database_service.dart';
import 'package:thoughtecho/services/backup_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/large_file_manager.dart';
import 'package:thoughtecho/services/media_sync_manifest.dart';
import 'package:thoughtecho/services/settings_service.dart';

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

class _MockSettingsService extends Mock implements SettingsService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void setPhoneSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('EmergencyApp and EmergencyRecoveryPage Provider Tests', () {
    testWidgets(
      'EmergencyApp provides BackupService to BackupRestorePage when navigating to /backup_restore',
      (tester) async {
        setPhoneSurface(tester);
        final mockBackupService = _MockBackupService();
        final navKey = GlobalKey<NavigatorState>();

        await tester.pumpWidget(
          EmergencyApp(
            error: 'Test initialization failure',
            stackTrace: 'Test stack trace details',
            customNavigatorKey: navKey,
            backupService: mockBackupService,
          ),
        );
        await tester.pumpAndSettle();

        // 验证主紧急页面正常渲染
        expect(find.byType(EmergencyHomePage), findsOneWidget);

        // 点击备份与恢复按钮，导航至 EmergencyBackupPage
        final backupButtons = find.widgetWithIcon(FilledButton, Icons.backup);
        expect(backupButtons, findsWidgets);
        await tester.tap(backupButtons.first);
        await tester.pumpAndSettle();

        expect(find.byType(EmergencyBackupPage), findsOneWidget);

        // 点击尝试打开标准备份还原页面按钮，导航至 /backup_restore
        final openStandardButtons =
            find.widgetWithIcon(FilledButton, Icons.backup);
        expect(openStandardButtons, findsWidgets);
        await tester.tap(openStandardButtons.first);
        await tester.pumpAndSettle();

        // 验证 BackupRestorePage 成功渲染且未发生 ProviderNotFoundException
        expect(find.byType(BackupRestorePage), findsOneWidget);

        final backupRestoreElement =
            tester.element(find.byType(BackupRestorePage));
        final providedBackupService =
            Provider.of<BackupService>(backupRestoreElement, listen: false);
        expect(providedBackupService, equals(mockBackupService));

        // 验证 DatabaseService 与 AIAnalysisDatabaseService 也已一并注入
        final providedDbService =
            Provider.of<DatabaseService>(backupRestoreElement, listen: false);
        expect(providedDbService, isNotNull);

        final providedAiDbService = Provider.of<AIAnalysisDatabaseService>(
          backupRestoreElement,
          listen: false,
        );
        expect(providedAiDbService, isNotNull);
      },
    );

    testWidgets(
      'EmergencyApp directly pushing /backup_restore provides all required services',
      (tester) async {
        setPhoneSurface(tester);
        final mockBackupService = _MockBackupService();
        final mockSettingsService = _MockSettingsService();
        final navKey = GlobalKey<NavigatorState>();

        await tester.pumpWidget(
          EmergencyApp(
            error: 'Test error',
            stackTrace: 'Test trace',
            customNavigatorKey: navKey,
            backupService: mockBackupService,
            settingsService: mockSettingsService,
          ),
        );
        await tester.pumpAndSettle();

        navKey.currentState!.pushNamed('/backup_restore');
        await tester.pumpAndSettle();

        expect(find.byType(BackupRestorePage), findsOneWidget);

        final element = tester.element(find.byType(BackupRestorePage));
        expect(
          Provider.of<BackupService>(element, listen: false),
          equals(mockBackupService),
        );
        expect(
          Provider.of<SettingsService>(element, listen: false),
          equals(mockSettingsService),
        );
      },
    );

    testWidgets(
      'EmergencyRecoveryPage provides BackupService when navigating to BackupRestorePage',
      (tester) async {
        setPhoneSurface(tester);
        final mockBackupService = _MockBackupService();

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: EmergencyRecoveryPage(
              backupService: mockBackupService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(EmergencyRecoveryPage), findsOneWidget);

        // 点击“备份和恢复数据”按钮
        final backupButton = find.widgetWithIcon(FilledButton, Icons.backup);
        expect(backupButton, findsOneWidget);
        await tester.tap(backupButton);
        await tester.pumpAndSettle();

        // 验证 BackupRestorePage 渲染且能获取 BackupService
        expect(find.byType(BackupRestorePage), findsOneWidget);

        final element = tester.element(find.byType(BackupRestorePage));
        final providedBackupService =
            Provider.of<BackupService>(element, listen: false);
        expect(providedBackupService, equals(mockBackupService));
      },
    );

    testWidgets('Emergency strings verify database file terminology', (
      tester,
    ) async {
      setPhoneSurface(tester);
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('zh'),
          home: Scaffold(
            body: EmergencyBackupPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证中文文案
      expect(
        find.textContaining('导出数据库文件 — 将原始数据库文件保存至本地'),
        findsOneWidget,
      );
      expect(
        find.textContaining('选择本地已有的 .zip 或 .json 备份文件进行数据恢复尝试'),
        findsOneWidget,
      );
      expect(
        find.textContaining('提示：导出的数据库文件包含你的完整笔记记录'),
        findsOneWidget,
      );
    });

    testWidgets('Emergency strings in English verify database file terminology',
        (tester) async {
      setPhoneSurface(tester);
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          home: Scaffold(
            body: EmergencyBackupPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证英文文案
      expect(
        find.textContaining(
            'Export database file — Save your raw database file'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
            'Select an existing local .zip or .json backup file to attempt recovery'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
            'Tip: The exported database file contains your complete note history'),
        findsOneWidget,
      );
    });
  });
}
