import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/smart_push_service.dart';

void main() {
  test('通知正文不会把 emoji 从代理对中间切断', () {
    // 第 100 个 UTF-16 code unit 正好落在 emoji 的代理对中间
    final content = '${'字' * 99}😀 后面还有很多内容才会触发截断${'尾' * 50}';
    final note = Quote(id: 'x', content: content, date: '2026-01-01T00:00:00');

    final body = SmartPushService.buildNotificationBodyForTest(note);

    // 不得含有落单的代理项
    for (final unit in body.codeUnits) {
      expect(unit >= 0xD800 && unit <= 0xDFFF, isFalse,
          reason: '正文里出现了未配对的代理项，emoji 被切碎了');
    }
    expect(body.contains('�'), isFalse);
  });
}
