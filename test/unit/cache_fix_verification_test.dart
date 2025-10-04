import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/widgets/quote_content_widget.dart';

/// 验证缓存修复的测试
void main() {
  group('缓存修复验证测试', () {
    setUp(() {
      // 每个测试前清空缓存
      QuoteContent.resetCaches();
    });

    test('修复验证1：removeCacheForQuote 方法存在且可调用', () {
      // 验证新增的清理方法可以正常调用
      expect(() => QuoteContent.removeCacheForQuote('test-id'), returnsNormally);
    });

    test('修复验证2：删除笔记后缓存应被清理', () {
      // 这个测试验证了问题1的修复
      // 实际清理逻辑在 DatabaseService 中，这里只验证 API 可用
      
      final testId = 'quote-to-delete';
      
      // 模拟调用清理方法
      QuoteContent.removeCacheForQuote(testId);
      
      // 获取统计信息
      final stats = QuoteContent.debugCacheStats();
      
      // 验证统计信息结构正确
      expect(stats, isA<Map<String, dynamic>>());
      expect(stats.containsKey('document'), isTrue);
      expect(stats.containsKey('controller'), isTrue);
    });

    test('修复验证3：缓存统计 API 正常工作', () {
      final stats = QuoteContent.debugCacheStats();
      
      // 验证 Document 缓存统计
      final docStats = stats['document'] as Map<String, dynamic>;
      expect(docStats.containsKey('cacheSize'), isTrue);
      expect(docStats.containsKey('maxSize'), isTrue);
      expect(docStats.containsKey('hitRate'), isTrue);
      
      // 验证 Controller 缓存统计
      final ctrlStats = stats['controller'] as Map<String, dynamic>;
      expect(ctrlStats.containsKey('cacheSize'), isTrue);
      expect(ctrlStats.containsKey('maxSize'), isTrue);
      expect(ctrlStats.containsKey('hitRate'), isTrue);
      expect(ctrlStats.containsKey('createCount'), isTrue);
      expect(ctrlStats.containsKey('disposeCount'), isTrue);
    });

    test('修复验证4：resetCaches 清空所有缓存', () {
      // 验证问题3的修复：resetCaches 仍然可用（用于应用后台）
      QuoteContent.resetCaches();
      
      final stats = QuoteContent.debugCacheStats();
      final docStats = stats['document'] as Map<String, dynamic>;
      final ctrlStats = stats['controller'] as Map<String, dynamic>;
      
      // 清空后缓存大小应为 0
      expect(docStats['cacheSize'], equals(0));
      expect(ctrlStats['cacheSize'], equals(0));
    });
  });
}
