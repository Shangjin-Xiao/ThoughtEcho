import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/constants/card_templates.dart';

void main() {
  group('CardTemplates renderLineNumbers test', () {
    test('应该渲染 0 行数字当 count 为 0', () {
      final result = CardTemplates.renderLineNumbers(0, 100.0, 20.0, 14.0);
      expect(result, equals(''));
    });

    test('应该渲染 1 行数字当 count 为 1', () {
      final result = CardTemplates.renderLineNumbers(1, 100.0, 20.0, 14.0);
      expect(
          result,
          contains(
              '<text x="50" y="100.0" text-anchor="end" fill="#4b5563" font-family="monospace" font-size="14">1</text>'));
      expect(result.trim().split('\n').length, 1);
    });

    test('应该渲染多行数字', () {
      final result = CardTemplates.renderLineNumbers(3, 100.0, 20.0, 14.0);
      expect(
          result,
          contains(
              '<text x="50" y="100.0" text-anchor="end" fill="#4b5563" font-family="monospace" font-size="14">1</text>'));
      expect(
          result,
          contains(
              '<text x="50" y="120.0" text-anchor="end" fill="#4b5563" font-family="monospace" font-size="14">2</text>'));
      expect(
          result,
          contains(
              '<text x="50" y="140.0" text-anchor="end" fill="#4b5563" font-family="monospace" font-size="14">3</text>'));

      final lines = result.trim().split('\n');
      expect(lines.length, 3);
    });

    test('格式化的 font-size 应该忽略小数部分', () {
      final result = CardTemplates.renderLineNumbers(1, 100.0, 20.0, 14.8);
      expect(
          result, contains('font-size="15"')); // 14.8.toStringAsFixed(0) is 15
    });
  });
}
