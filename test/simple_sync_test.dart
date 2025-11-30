import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/note_sync_service.dart';
import 'package:thoughtecho/services/backup_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/ai_analysis_database_service.dart';
import 'package:thoughtecho/services/localsend/models/device.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/large_file_manager.dart';
import 'package:thoughtecho/models/merge_report.dart';

void main() {
  group('简化同步功能测试', () {
    test('NoteSyncService 初始化测试', () async {
      // 创建模拟服务
      final backupService = MockBackupService();
      final databaseService = MockDatabaseService();
      final settingsService = MockSettingsService();
      final aiService = MockAIAnalysisDatabaseService();

      // 创建同步服务
      final syncService = NoteSyncService(
        backupService: backupService,
        databaseService: databaseService,
        settingsService: settingsService,
        aiAnalysisDbService: aiService,
      );

      // 验证初始状态
      expect(syncService.syncStatus, SyncStatus.idle);
      expect(syncService.syncProgress, 0.0);
    });

    test('Device 创建测试', () {
      // 测试Device类的基本功能
      final device = Device(
        signalingId: null,
        ip: '192.168.1.100',
        version: '2.1',
        port: 53317,
        https: false,
        fingerprint: 'test-fingerprint',
        alias: 'Test Device',
        deviceModel: 'Test Model',
        deviceType: DeviceType.mobile,
        download: true,
        discoveryMethods: <DiscoveryMethod>{const MulticastDiscovery()},
      );

      expect(device.ip, '192.168.1.100');
      expect(device.alias, 'Test Device');
      expect(device.deviceType, DeviceType.mobile);
    });

    test('同步状态枚举测试', () {
      // 测试所有同步状态
      expect(SyncStatus.values.contains(SyncStatus.idle), true);
      expect(SyncStatus.values.contains(SyncStatus.packaging), true);
      expect(SyncStatus.values.contains(SyncStatus.sending), true);
      expect(SyncStatus.values.contains(SyncStatus.receiving), true);
      expect(SyncStatus.values.contains(SyncStatus.merging), true);
      expect(SyncStatus.values.contains(SyncStatus.completed), true);
      expect(SyncStatus.values.contains(SyncStatus.failed), true);
    });

    test('接收取消后重新接收应刷新状态与进度', () {
      final backupService = MockBackupService();
      final databaseService = MockDatabaseService();
      final settingsService = MockSettingsService();
      final aiService = MockAIAnalysisDatabaseService();

      final syncService = NoteSyncService(
        backupService: backupService,
        databaseService: databaseService,
        settingsService: settingsService,
        aiAnalysisDbService: aiService,
      );

      syncService.debugHandleReceiveSessionCreated('session-a', 1024, '设备A');
      expect(syncService.syncStatus, SyncStatus.receiving);

      syncService.cancelReceiving();
      expect(syncService.syncStatus, SyncStatus.failed);

      syncService.debugHandleReceiveSessionCreated('session-b', 2048, '设备B');
      expect(syncService.syncStatus, SyncStatus.receiving);

      syncService.debugHandleReceiveProgress(1024, 2048);
      expect(syncService.syncStatus, SyncStatus.receiving);
      expect(syncService.syncProgress, greaterThan(0.05));
    });
  });
}

// 模拟服务类
class MockBackupService implements BackupService {
  @override
  Future<String> exportAllData({
    required bool includeMediaFiles,
    String? customPath,
    Function(int current, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    return 'mock_backup_path.zip';
  }

  @override
  Future<MergeReport?> importData(
    String filePath, {
    bool clearExisting = true,
    bool merge = false,
    Function(int current, int total)? onProgress,
    CancelToken? cancelToken,
    String? sourceDevice,
  }) async {
    // 返回一个空的合并报告或 null（当 merge=false 时与真实逻辑一致）
    if (merge) {
      return MergeReport.start(sourceDevice: sourceDevice).completed();
    }
    return null;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockDatabaseService implements DatabaseService {
  @override
  Future<List<Quote>> getAllQuotes() async {
    return [];
  }

  @override
  Future<void> deleteQuote(String id) async {
    // Mock implementation
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockSettingsService implements SettingsService {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockAIAnalysisDatabaseService implements AIAnalysisDatabaseService {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
