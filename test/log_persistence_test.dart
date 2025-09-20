import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/unified_log_service.dart';
import 'test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('日志持久化', () {
    test('写入后可从数据库查询到', () async {
      await TestSetup.setupAll();
      final unified = UnifiedLogService.instance;

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
}
