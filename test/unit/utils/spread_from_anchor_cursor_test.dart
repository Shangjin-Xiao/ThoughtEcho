import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/spread_from_anchor_cursor.dart';

List<int> _drain(SpreadFromAnchorCursor cursor, int length, {int? take}) {
  final out = <int>[];
  while (take == null || out.length < take) {
    final next = cursor.next(length);
    if (next == null) break;
    out.add(next);
  }
  return out;
}

void main() {
  group('SpreadFromAnchorCursor', () {
    test('从锚点向两边交替扩散，同距离时先向下', () {
      final cursor = SpreadFromAnchorCursor()..restart(anchor: 5, length: 10);
      expect(_drain(cursor, 10, take: 6), [5, 6, 4, 7, 3, 8]);
    });

    test('一轮把每个下标不重不漏地走一遍', () {
      final cursor = SpreadFromAnchorCursor()..restart(anchor: 3, length: 10);
      final visited = _drain(cursor, 10);
      expect(visited.length, 10);
      expect(visited.toSet().length, 10);
      expect(cursor.emitted, 10);
    });

    test('一头先到边界后，剩下的全从另一头继续', () {
      final cursor = SpreadFromAnchorCursor()..restart(anchor: 1, length: 6);
      expect(_drain(cursor, 6), [1, 2, 0, 3, 4, 5]);
    });

    test('预热途中追加了新页，接着往下走而不用重来', () {
      final cursor = SpreadFromAnchorCursor()..restart(anchor: 0, length: 3);
      expect(_drain(cursor, 3), [0, 1, 2]);
      // 分页追加：长度变长，游标接着吐新来的那几条。
      expect(_drain(cursor, 5), [3, 4]);
    });

    test('锚点越界或列表为空都不会空转', () {
      final cursor = SpreadFromAnchorCursor()..restart(anchor: 99, length: 4);
      expect(cursor.anchor, 3);
      expect(_drain(cursor, 4), [3, 2, 1, 0]);

      cursor.restart(anchor: -5, length: 0);
      expect(cursor.next(0), isNull);
    });
  });
}
