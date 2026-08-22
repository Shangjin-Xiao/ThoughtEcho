import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/smart_push_service.dart';

/// 检测字符串里是否存在"未配对"的代理项。
///
/// 注意：合法 emoji 本身就由一对代理项组成（😀 = 0xD83D 0xDE00），
/// 所以不能简单断言"不含代理项码元"，必须成对校验。
bool hasLoneSurrogate(String s) {
  for (var i = 0; i < s.length; i++) {
    final unit = s.codeUnitAt(i);
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      // 高位代理项：后面必须紧跟一个低位代理项
      if (i + 1 >= s.length) return true;
      final next = s.codeUnitAt(i + 1);
      if (next < 0xDC00 || next > 0xDFFF) return true;
      i++; // 跳过已配对的低位代理项
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      // 落单的低位代理项
      return true;
    }
  }
  return false;
}

void main() {
  group('通知正文截断', () {
    test('emoji 落在截断边界上时不会被从代理对中间切开', () {
      // 第 100 个 UTF-16 码元正好落在 emoji 的代理对中间：
      // 99 个中文（99 码元）+ 😀（2 码元）→ 旧的 substring(0, 100) 只会留下高位代理项
      final content = '${'字' * 99}😀${'尾' * 60}';
      final note = Quote(
        id: 'surrogate-boundary',
        content: content,
        date: '2026-01-01T00:00:00',
      );

      final body = SmartPushService.buildNotificationBodyForTest(note);

      expect(
        hasLoneSurrogate(body),
        isFalse,
        reason: '正文里出现了未配对的代理项，emoji 被切碎了',
      );
      expect(body.contains('�'), isFalse, reason: '不应出现替换字符');
      // 该 emoji 落在前 100 个字素簇内，应当被完整保留
      expect(body.contains('😀'), isTrue);
    });

    test('hasLoneSurrogate 本身能分辨配对与落单', () {
      expect(hasLoneSurrogate('😀'), isFalse);
      expect(hasLoneSurrogate('普通文本'), isFalse);
      expect(hasLoneSurrogate('abc\uD83D'), isTrue); // 落单高位
      expect(hasLoneSurrogate('\uDE00abc'), isTrue); // 落单低位
    });

    test('短内容原样返回，不加省略号', () {
      final note = Quote(
        id: 'short',
        content: '很短的一条笔记 😀',
        date: '2026-01-01T00:00:00',
      );
      expect(
        SmartPushService.buildNotificationBodyForTest(note),
        '很短的一条笔记 😀',
      );
    });
  });
}
