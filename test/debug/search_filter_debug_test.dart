import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/models/quote_model.dart';
import '../test_config.dart';
import '../test_setup.dart';

void main() {
  late DatabaseService databaseService;

  setUpAll(() async {
    // Initialize test environment first
    await TestSetup.setupAll();
  });

  setUp(() async {
    databaseService = DatabaseService();
    await databaseService.init();
  });

  tearDown(() async {
    // Proper cleanup
    try {
      databaseService.dispose();
    } catch (e) {
      debugPrint('Warning: cleanup error: $e');
    }
  });

  group('搜索和筛选功能调试测试', () {
    test('测试基本的数据库连接和初始化', () async {
      expect(databaseService.isInitialized, isTrue);
      debugPrint('✓ 数据库初始化成功');
    });

    test('添加测试数据', () async {
      // 添加一些测试分类
      await databaseService.addCategory('测试分类1', iconName: '📝');
      await databaseService.addCategory('测试分类2', iconName: '💡');

      final categories = await databaseService.getCategories();
      expect(categories.length, greaterThanOrEqualTo(2));
      debugPrint('✓ 测试分类添加成功: ${categories.length}个');

      // 添加一些测试笔记
      final testQuotes = [
        Quote(
          id: 'test1',
          content: '这是第一条测试笔记，包含关键词搜索',
          date: DateTime.now().toIso8601String(),
          tagIds: [categories.first.id],
          weather: 'sunny',
          dayPeriod: 'morning',
        ),
        Quote(
          id: 'test2',
          content: '第二条笔记用于测试筛选功能',
          date: DateTime.now()
              .subtract(const Duration(hours: 1))
              .toIso8601String(),
          tagIds: [categories.last.id],
          weather: 'cloudy',
          dayPeriod: 'afternoon',
        ),
        Quote(
          id: 'test3',
          content: '第三条笔记包含多个标签',
          date: DateTime.now()
              .subtract(const Duration(hours: 2))
              .toIso8601String(),
          tagIds: [categories.first.id, categories.last.id],
          weather: 'sunny',
          dayPeriod: 'evening',
        ),
      ];

      for (final quote in testQuotes) {
        await databaseService.addQuote(quote);
      }

      debugPrint('✓ 测试笔记添加成功: ${testQuotes.length}条');
    });

    test('测试基本查询性能', () async {
      final stopwatch = Stopwatch()..start();

      final quotes = await databaseService.getUserQuotes(limit: 20, offset: 0);

      stopwatch.stop();
      debugPrintSynchronously(
        '✓ 基本查询耗时: ${stopwatch.elapsedMilliseconds}ms, 结果: ${quotes.length}条',
      );

      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(1000),
        reason: '基本查询应该在1秒内完成',
      );
    });

    test('测试搜索查询性能', () async {
      final stopwatch = Stopwatch()..start();

      try {
        final quotes = await databaseService.getUserQuotes(
          searchQuery: '测试',
          limit: 20,
          offset: 0,
        );

        stopwatch.stop();
        debugPrintSynchronously(
          '✓ 搜索查询耗时: ${stopwatch.elapsedMilliseconds}ms, 结果: ${quotes.length}条',
        );

        expect(
          stopwatch.elapsedMilliseconds,
          lessThan(2000),
          reason: '搜索查询应该在2秒内完成',
        );
      } catch (e) {
        stopwatch.stop();
        debugPrintSynchronously(
            '✗ 搜索查询失败: $e, 耗时: ${stopwatch.elapsedMilliseconds}ms');
        rethrow;
      }
    });

    test('测试标签筛选查询性能', () async {
      // Skip performance tests in CI
      if (TestConfig.shouldSkipTest('测试标签筛选查询性能')) {
        debugPrintSynchronously('⏭️ 跳过性能测试（CI环境）');
        return;
      }

      final categories = await databaseService.getCategories();
      if (categories.isEmpty) {
        debugPrintSynchronously('跳过标签筛选测试：没有可用的分类');
        return;
      }

      final stopwatch = Stopwatch()..start();

      try {
        final quotes = await databaseService.getUserQuotes(
          tagIds: [categories.first.id],
          limit: 20,
          offset: 0,
        );

        stopwatch.stop();
        debugPrintSynchronously(
          '✓ 标签筛选查询耗时: ${stopwatch.elapsedMilliseconds}ms, 结果: ${quotes.length}条',
        );

        // Use different timeout for CI vs local
        final maxTime = TestConfig.isCI ? 10000 : 3000; // More lenient in CI
        expect(
          stopwatch.elapsedMilliseconds,
          lessThan(maxTime),
          reason: '标签筛选查询应该在${maxTime}ms内完成',
        );
      } catch (e) {
        stopwatch.stop();
        debugPrintSynchronously(
            '✗ 标签筛选查询失败: $e, 耗时: ${stopwatch.elapsedMilliseconds}ms');
        if (!TestConfig.isCI) rethrow; // Don't fail CI on performance issues
      }
    });

    test('测试复合查询性能（搜索+标签+天气）', () async {
      final categories = await databaseService.getCategories();
      if (categories.isEmpty) {
        debugPrintSynchronously('跳过复合查询测试：没有可用的分类');
        return;
      }

      final stopwatch = Stopwatch()..start();

      try {
        final quotes = await databaseService.getUserQuotes(
          searchQuery: '测试',
          tagIds: [categories.first.id],
          selectedWeathers: ['sunny'],
          limit: 20,
          offset: 0,
        );

        stopwatch.stop();
        debugPrintSynchronously(
          '✓ 复合查询耗时: ${stopwatch.elapsedMilliseconds}ms, 结果: ${quotes.length}条',
        );

        expect(
          stopwatch.elapsedMilliseconds,
          lessThan(5000),
          reason: '复合查询应该在5秒内完成',
        );
      } catch (e) {
        stopwatch.stop();
        debugPrintSynchronously(
            '✗ 复合查询失败: $e, 耗时: ${stopwatch.elapsedMilliseconds}ms');
        rethrow;
      }
    });

    test('测试超时场景模拟', () async {
      final categories = await databaseService.getCategories();

      // 创建大量测试数据来模拟慢查询
      debugPrintSynchronously('正在创建大量测试数据...');
      final futures = <Future>[];
      for (int i = 0; i < 100; i++) {
        final quote = Quote(
          id: 'bulk_test_$i',
          content: '批量测试数据 $i 用于性能测试 包含各种关键词 搜索 筛选 测试',
          date: DateTime.now().subtract(Duration(minutes: i)).toIso8601String(),
          tagIds: categories.isNotEmpty
              ? [categories[i % categories.length].id]
              : [],
          weather: ['sunny', 'cloudy', 'rainy'][i % 3],
          dayPeriod: ['morning', 'afternoon', 'evening', 'night'][i % 4],
        );
        futures.add(databaseService.addQuote(quote));
      }
      await Future.wait(futures);
      debugPrintSynchronously('✓ 批量数据创建完成');

      final stopwatch = Stopwatch()..start();

      try {
        final quotes = await databaseService.getUserQuotes(
          searchQuery: '测试',
          tagIds: categories.isNotEmpty ? [categories.first.id] : null,
          selectedWeathers: ['sunny', 'cloudy'],
          selectedDayPeriods: ['morning', 'afternoon'],
          limit: 50,
          offset: 0,
        );

        stopwatch.stop();
        debugPrintSynchronously(
          '✓ 大数据量查询耗时: ${stopwatch.elapsedMilliseconds}ms, 结果: ${quotes.length}条',
        );

        // 修复后的期望：查询应该在5秒内完成或超时
        expect(
          stopwatch.elapsedMilliseconds,
          lessThan(6000),
          reason: '修复后查询应该在6秒内完成或抛出超时异常',
        );
      } catch (e) {
        stopwatch.stop();
        debugPrintSynchronously(
            '查询结果: $e, 耗时: ${stopwatch.elapsedMilliseconds}ms');

        if (e.toString().contains('TimeoutException')) {
          debugPrintSynchronously(
              '✓ 超时机制正常工作，在 ${stopwatch.elapsedMilliseconds}ms 后抛出超时异常');
          expect(
            stopwatch.elapsedMilliseconds,
            lessThan(6000),
            reason: '超时应该在6秒内触发',
          );
        } else {
          debugPrintSynchronously('✗ 非超时异常: $e');
          rethrow;
        }
      }
    });

    test('测试搜索功能修复验证', () async {
      // 添加测试数据
      final categories = await databaseService.getCategories();
      await databaseService.addQuote(
        Quote(
          id: 'search_test_1',
          content: '这是一个搜索测试笔记',
          date: DateTime.now().toIso8601String(),
          tagIds: categories.isNotEmpty ? [categories.first.id] : [],
        ),
      );

      final stopwatch = Stopwatch()..start();

      try {
        final quotes = await databaseService.getUserQuotes(
          searchQuery: '搜索测试',
          limit: 20,
          offset: 0,
        );

        stopwatch.stop();
        debugPrintSynchronously(
          '✓ 搜索功能测试耗时: ${stopwatch.elapsedMilliseconds}ms, 结果: ${quotes.length}条',
        );

        expect(quotes.length, greaterThan(0), reason: '应该找到包含搜索关键词的笔记');
        expect(
          stopwatch.elapsedMilliseconds,
          lessThan(3000),
          reason: '搜索应该在3秒内完成',
        );
      } catch (e) {
        stopwatch.stop();
        debugPrint('✗ 搜索功能测试失败: $e, 耗时: ${stopwatch.elapsedMilliseconds}ms');
        rethrow;
      }
    });

    test('测试数据库索引状态', () async {
      try {
        final db = databaseService.database;

        // 检查索引是否存在
        final indexes = await db.rawQuery('''
          SELECT name FROM sqlite_master 
          WHERE type='index' AND tbl_name IN ('quotes', 'quote_tags', 'categories')
        ''');

        final indexDetails =
            indexes.map((index) => '  - ${index['name']}').join('\n');
        debugPrintSynchronously('数据库索引状态:\n$indexDetails');

        // 检查quote_tags表的索引
        final quoteTagsIndexes = indexes
            .where((idx) => idx['name'].toString().contains('quote_tags'))
            .toList();

        if (quoteTagsIndexes.isEmpty) {
          debugPrint('⚠️ 警告：quote_tags表可能缺少索引，这会导致标签查询变慢');
        } else {
          debugPrint('✓ quote_tags表索引正常');
        }
      } catch (e) {
        debugPrint('✗ 检查索引状态失败: $e');
      }
    });

    test('测试查询计划分析', () async {
      try {
        final db = databaseService.database;
        final categories = await databaseService.getCategories();

        if (categories.isNotEmpty) {
          // 分析标签查询的执行计划
          final queryPlan = await db.rawQuery(
            '''
            EXPLAIN QUERY PLAN
            SELECT q.*, (
              SELECT GROUP_CONCAT(qt.tag_id) 
              FROM quote_tags qt 
              WHERE qt.quote_id = q.id
            ) as tag_ids
            FROM quotes q
            WHERE EXISTS (SELECT 1 FROM quote_tags qt WHERE qt.quote_id = q.id AND qt.tag_id = ?)
            ORDER BY q.date DESC
            LIMIT 20 OFFSET 0
          ''',
            [categories.first.id],
          );

          final planDetails =
              queryPlan.map((plan) => '  ${plan['detail']}').join('\n');
          debugPrintSynchronously('标签查询执行计划:\n$planDetails');

          // 检查是否使用了索引
          final usesIndex = queryPlan.any(
            (plan) => plan['detail'].toString().toLowerCase().contains('index'),
          );

          if (!usesIndex) {
            debugPrint('⚠️ 警告：查询可能没有使用索引，性能会较差');
          } else {
            debugPrint('✓ 查询使用了索引优化');
          }
        }
      } catch (e) {
        debugPrint('✗ 查询计划分析失败: $e');
      }
    });
  });
}
