import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thoughtecho/services/log_database_service.dart';
import 'package:thoughtecho/services/unified_log_service.dart';
import '../../test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('日志持久化', () {
    test('写入后可从数据库查询到', () async {
      await TestHarness.initialize();
      final unified = UnifiedLogService.instance;
      unified.setPersistenceEnabled(true);

      // 写入一条唯一日志
      final uniqueMessage = '持久化测试-${DateTime.now().microsecondsSinceEpoch}';
      unified.info(uniqueMessage, source: 'LogPersistTest');

      // 立即刷新到数据库
      await unified.flushLogs();

      // 通过统一日志服务查询数据库，验证存在
      await Future.delayed(const Duration(milliseconds: 80));
      final queried = await unified.queryLogs(
        searchText: uniqueMessage,
        limit: 20,
      );
      final found = queried.any((e) => e.message == uniqueMessage);

      expect(found, true, reason: '数据库中未找到刚写入的日志');
    });
  });

  group('WebLogStorage 内存缓存与防抖异步持久化', () {
    setUp(() async {
      await TestHarness.initialize();
      SharedPreferences.setMockInitialValues({});
    });

    test('高频连续 insertLog 写入与 flushLogs 持久化完整性验证', () async {
      final storage = WebLogStorage(
        saveDebounceDuration: const Duration(milliseconds: 500),
      );
      await storage.initialize();

      const totalLogs = 50;
      final stopwatch = Stopwatch()..start();
      for (int i = 0; i < totalLogs; i++) {
        await storage.insertLog({
          'timestamp': DateTime.now().toIso8601String(),
          'level': 'info',
          'message': '高频日志测试-$i',
          'source': 'WebLogTest',
          'error': null,
          'stack_trace': null,
        });
      }
      stopwatch.stop();

      // 内存缓存中立即可见，无需等待持久化
      expect(await storage.getLogCount(), totalLogs);
      final memoryLogs = await storage.queryLogs(limit: 100);
      expect(memoryLogs.length, totalLogs);

      // 防抖窗口内，SharedPreferences 尚未写入全量磁盘数据
      final prefs = await SharedPreferences.getInstance();
      final immediateDiskLogs = prefs.getStringList('app_logs_storage') ?? [];
      expect(
        immediateDiskLogs.length,
        lessThan(totalLogs),
        reason: '高频写入应当被防抖延迟，不应在每次调用时全量持久化',
      );

      // 显式触发 flushLogs 刷盘
      await storage.flushLogs();

      // 验证全量数据已被刷入磁盘持久化存储
      final flushedDiskLogs = prefs.getStringList('app_logs_storage') ?? [];
      expect(flushedDiskLogs.length, totalLogs);

      // 验证重新初始化后能从磁盘完整加载数据
      final reloadedStorage = WebLogStorage();
      await reloadedStorage.initialize();
      expect(await reloadedStorage.getLogCount(), totalLogs);
      final reloadedLogs = await reloadedStorage.queryLogs(limit: 100);
      expect(reloadedLogs.length, totalLogs);
      expect(reloadedLogs.first['message'], contains('高频日志测试-'));

      await storage.close();
      await reloadedStorage.close();
    });

    test('批量 insertLogs 写入与内存缓存即时查询', () async {
      final storage = WebLogStorage(
        saveDebounceDuration: const Duration(milliseconds: 500),
      );
      await storage.initialize();

      final batch = List.generate(
        25,
        (i) => {
          'timestamp': DateTime.now().toIso8601String(),
          'level': 'warning',
          'message': '批量日志-$i',
          'source': 'BatchTest',
          'error': null,
          'stack_trace': null,
        },
      );

      await storage.insertLogs(batch);
      expect(await storage.getLogCount(), 25);

      final recent = await storage.getRecentLogs(10);
      expect(recent.length, 10);
      expect(recent.first['source'], 'BatchTest');

      await storage.flushLogs();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('app_logs_storage')?.length, 25);

      await storage.close();
    });

    test('防抖定时器自动持久化刷盘', () async {
      final storage = WebLogStorage(
        saveDebounceDuration: const Duration(milliseconds: 50),
      );
      await storage.initialize();

      await storage.insertLog({
        'timestamp': DateTime.now().toIso8601String(),
        'level': 'debug',
        'message': '自动定时刷盘日志',
        'source': 'TimerTest',
        'error': null,
        'stack_trace': null,
      });

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('app_logs_storage'), isNull);

      // 等待防抖定时器触发
      await Future.delayed(const Duration(milliseconds: 80));

      final diskLogs = prefs.getStringList('app_logs_storage') ?? [];
      expect(diskLogs.length, 1);
      expect(diskLogs.first, contains('自动定时刷盘日志'));

      await storage.close();
    });

    test('deleteOldLogs 同步更新内存缓存并持久化', () async {
      final storage = WebLogStorage(
        saveDebounceDuration: const Duration(milliseconds: 500),
      );
      await storage.initialize();

      for (int i = 0; i < 20; i++) {
        await storage.insertLog({
          'timestamp':
              DateTime.now().add(Duration(seconds: i)).toIso8601String(),
          'level': 'info',
          'message': '保留测试-$i',
          'source': 'TrimTest',
          'error': null,
          'stack_trace': null,
        });
      }
      await storage.flushLogs();

      // 保留最新的 5 条
      final deleted = await storage.deleteOldLogs(5);
      expect(deleted, 15);
      expect(await storage.getLogCount(), 5);

      final remaining = await storage.queryLogs(limit: 20);
      expect(remaining.length, 5);

      // 等待防抖窗口，确认旧状态不会覆盖已清理的缓存
      await Future.delayed(const Duration(milliseconds: 80));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('app_logs_storage')?.length, 5);

      await storage.close();
    });

    test('clearAllLogs 清空缓存并取消待执行刷盘', () async {
      final storage = WebLogStorage(
        saveDebounceDuration: const Duration(milliseconds: 500),
      );
      await storage.initialize();

      for (int i = 0; i < 10; i++) {
        await storage.insertLog({
          'timestamp': DateTime.now().toIso8601String(),
          'level': 'info',
          'message': '清理测试-$i',
          'source': 'ClearTest',
          'error': null,
          'stack_trace': null,
        });
      }

      // 未手动 flush 时直接清空
      final cleared = await storage.clearAllLogs();
      expect(cleared, 10);
      expect(await storage.getLogCount(), 0);

      // 等待超过防抖时间，确认不会有残留日志刷盘
      await Future.delayed(const Duration(milliseconds: 80));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('app_logs_storage'), isNull);
      expect(prefs.getInt('app_logs_count'), isNull);

      await storage.close();
    });

    test('close 方法自动等待并刷盘未保存日志', () async {
      final storage = WebLogStorage(
        saveDebounceDuration: const Duration(milliseconds: 500),
      );
      await storage.initialize();

      await storage.insertLog({
        'timestamp': DateTime.now().toIso8601String(),
        'level': 'error',
        'message': '关闭前写入日志',
        'source': 'CloseTest',
        'error': 'test error',
        'stack_trace': null,
      });

      // 直接 close，应当触发 _flushPendingSave
      await storage.close();

      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('app_logs_storage') ?? [];
      expect(saved.length, 1);
      expect(saved.first, contains('关闭前写入日志'));
    });
  });
}
