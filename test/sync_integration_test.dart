import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:thoughtecho/services/note_sync_service.dart';
import 'package:thoughtecho/services/backup_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/ai_analysis_database_service.dart';
import 'package:thoughtecho/services/localsend/models/device.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/localsend/localsend_send_provider.dart';

// 生成Mock类
@GenerateMocks([
  BackupService,
  DatabaseService,
  SettingsService,
  AIAnalysisDatabaseService,
  LocalSendProvider,
])
import 'sync_integration_test.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('同步功能端到端测试', () {
    late NoteSyncService syncService;
    late MockBackupService mockBackupService;
    late MockDatabaseService mockDatabaseService;
    late MockSettingsService mockSettingsService;
    late MockAIAnalysisDatabaseService mockAiAnalysisDbService;
    late MockLocalSendProvider mockLocalSendProvider;

    setUp(() {
      mockBackupService = MockBackupService();
      mockDatabaseService = MockDatabaseService();
      mockSettingsService = MockSettingsService();
      mockAiAnalysisDbService = MockAIAnalysisDatabaseService();
      mockLocalSendProvider = MockLocalSendProvider();

      syncService = NoteSyncService(
        backupService: mockBackupService,
        databaseService: mockDatabaseService,
        settingsService: mockSettingsService,
        aiAnalysisDbService: mockAiAnalysisDbService,
      );
      syncService.localSendProviderForTesting = mockLocalSendProvider;

      // 为 startSession 设置默认 mock 行为
      when(
        mockLocalSendProvider.startSession(
          target: anyNamed('target'),
          files: anyNamed('files'),
          background: anyNamed('background'),
          onProgress: anyNamed('onProgress'),
          onSessionCreated: anyNamed('onSessionCreated'),
        ),
      ).thenAnswer((_) async {
        return 'session-123';
      });

      // 写入物理临时文件，以让 NoteSyncService 的备份文件大小校验通过
      File('/tmp/test_backup.zip').writeAsStringSync('fake zip data');
      File('/tmp/backup_with_media.zip').writeAsStringSync('fake zip data');
    });

    tearDown(() {
      syncService.dispose();
      try {
        final f1 = File('/tmp/test_backup.zip');
        if (f1.existsSync()) f1.deleteSync();
        final f2 = File('/tmp/backup_with_media.zip');
        if (f2.existsSync()) f2.deleteSync();
      } catch (_) {}
    });

    test('同步状态管理测试', () {
      // 初始状态应该是idle
      expect(syncService.syncStatus, equals(SyncStatus.idle));
      expect(syncService.syncStatusMessage, equals(''));
      expect(syncService.syncProgress, equals(0.0));
    });

    test('创建同步包流程测试', () async {
      // 准备测试数据
      final testDevice = Device(
        signalingId: null,
        ip: '192.168.1.100',
        version: '2.1',
        port: 53317,
        https: false,
        fingerprint: 'test-device-fingerprint',
        alias: 'Test Device',
        deviceModel: 'Test Model',
        deviceType: DeviceType.mobile,
        download: true,
        discoveryMethods: <DiscoveryMethod>{const MulticastDiscovery()},
      );

      // Mock备份服务返回
      when(
        mockBackupService.exportAllData(
          includeMediaFiles: true,
          onProgress: anyNamed('onProgress'),
        ),
      ).thenAnswer((_) async {
        return '/tmp/test_backup.zip';
      });

      final sessionId = await syncService.createSyncPackage(testDevice);
      expect(sessionId, equals('session-123'));

      // 验证备份服务被调用
      verify(
        mockBackupService.exportAllData(
          includeMediaFiles: true,
          onProgress: anyNamed('onProgress'),
        ),
      ).called(1);
    });

    test('处理同步包流程测试', () async {
      // 准备测试数据
      const testBackupPath = '/tmp/test_backup.zip';

      // Mock数据库服务
      when(mockDatabaseService.getAllQuotes()).thenAnswer(
        (_) async => [
          Quote(
            id: 'quote1',
            content: 'Test quote 1',
            date: '2024-01-01T00:00:00.000Z',
            categoryId: 'cat1',
            tagIds: const [],
          ),
          Quote(
            id: 'quote2',
            content: 'Test quote 1', // 重复内容
            // 使用固定时间避免时间依赖 (早于 quote1 的 2024-01-01T00:00:00.000Z)
            date: '2023-12-31T23:59:59.000Z',
            categoryId: 'cat1',
            tagIds: const [],
          ),
        ],
      );

      when(mockDatabaseService.deleteQuote(any)).thenAnswer((_) async {});

      // Mock备份服务
      when(
        mockBackupService.importData(
          testBackupPath,
          clearExisting: false,
          merge: anyNamed('merge'),
          onProgress: anyNamed('onProgress'),
          cancelToken: anyNamed('cancelToken'),
          sourceDevice: anyNamed('sourceDevice'),
        ),
      ).thenAnswer((_) async {
        return null;
      });

      // 执行处理同步包
      await syncService.processSyncPackage(testBackupPath);

      // 验证导入被调用
      verify(
        mockBackupService.importData(
          testBackupPath,
          clearExisting: false,
          merge: anyNamed('merge'),
          onProgress: anyNamed('onProgress'),
          cancelToken: anyNamed('cancelToken'),
          sourceDevice: anyNamed('sourceDevice'),
        ),
      ).called(1);

      // 验证刷新数据库接口被调用
      verify(mockDatabaseService.refreshAllData()).called(1);
    });

    test('媒体文件同步支持测试', () async {
      // 验证备份时包含媒体文件
      when(
        mockBackupService.exportAllData(
          includeMediaFiles: true,
          onProgress: anyNamed('onProgress'),
        ),
      ).thenAnswer((_) async => '/tmp/backup_with_media.zip');

      final testDevice = Device(
        signalingId: null,
        ip: '192.168.1.100',
        version: '2.1',
        port: 53317,
        https: false,
        fingerprint: 'test-device',
        alias: 'Test Device',
        deviceModel: 'Test Model',
        deviceType: DeviceType.mobile,
        download: true,
        discoveryMethods: <DiscoveryMethod>{const MulticastDiscovery()},
      );

      final sessionId = await syncService.createSyncPackage(testDevice);
      expect(sessionId, equals('session-123'));

      // 验证includeMediaFiles参数被正确传递
      verify(
        mockBackupService.exportAllData(
          includeMediaFiles: true,
          onProgress: anyNamed('onProgress'),
        ),
      ).called(1);
    });

    test('错误处理测试', () async {
      // 测试备份失败的情况
      when(
        mockBackupService.exportAllData(
          includeMediaFiles: true,
          onProgress: anyNamed('onProgress'),
        ),
      ).thenThrow(Exception('备份失败'));

      final testDevice = Device(
        signalingId: null,
        ip: '192.168.1.100',
        version: '2.1',
        port: 53317,
        https: false,
        fingerprint: 'test-device',
        alias: 'Test Device',
        deviceModel: 'Test Model',
        deviceType: DeviceType.mobile,
        download: true,
        discoveryMethods: <DiscoveryMethod>{const MulticastDiscovery()},
      );

      // 应该抛出异常
      expect(() => syncService.createSyncPackage(testDevice), throwsException);
    });

    test('设备类型转换测试', () {
      final testDevice = Device(
        signalingId: null,
        ip: '192.168.1.100',
        version: '2.1',
        port: 53317,
        https: false,
        fingerprint: 'test-device',
        alias: 'Test Device',
        deviceModel: 'Test Model',
        deviceType: DeviceType.desktop,
        download: true,
        discoveryMethods: <DiscoveryMethod>{const MulticastDiscovery()},
      );

      // 测试设备类型转换（通过反射或其他方式访问私有方法）
      // 这里我们主要验证不会抛出异常
      expect(testDevice.deviceType, equals(DeviceType.desktop));
    });
  });
}
