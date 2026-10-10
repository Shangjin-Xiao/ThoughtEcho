import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/sqlite_type_utils.dart';

void main() {
  group('safeParseInt', () {
    test('解析常规整数', () {
      expect(safeParseInt(42), 42);
      expect(safeParseInt(0), 0);
      expect(safeParseInt(-10), -10);
    });

    test('解析浮点数', () {
      expect(safeParseInt(42.0), 42);
      expect(safeParseInt(42.9), 42);
    });

    test('过滤 NaN 与 Infinity 并返回默认值', () {
      expect(safeParseInt(double.nan), 0);
      expect(safeParseInt(double.nan, 99), 99);
      expect(safeParseInt(double.infinity), 0);
      expect(safeParseInt(double.negativeInfinity, -1), -1);
      expect(safeParseInt('NaN', 0), 0);
      expect(safeParseInt('Infinity', 0), 0);
      expect(safeParseInt('-Infinity', 5), 5);
    });

    test('解析字符串形式的数字', () {
      expect(safeParseInt('42'), 42);
      expect(safeParseInt('42.0'), 42);
      expect(safeParseInt('-5'), -5);
    });

    test('非数字或空值返回默认值', () {
      expect(safeParseInt(null), 0);
      expect(safeParseInt(null, 10), 10);
      expect(safeParseInt('abc'), 0);
      expect(safeParseInt('abc', 7), 7);
      expect(safeParseInt(Object(), 3), 3);
    });
  });
}
