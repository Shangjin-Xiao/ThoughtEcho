import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/note_list_image_profile.dart';

void main() {
  tearDown(NoteListImageProfile.endSession);

  group('滚动会话之外不记账', () {
    test('没开会话时 markResolveStart 返回 null 且计数不动', () {
      NoteListImageProfile.endSession();

      expect(NoteListImageProfile.markResolveStart(), isNull);
      NoteListImageProfile.markFirstFrame(
        startMicros: 0,
        synchronous: false,
      );

      NoteListImageProfile.beginSession();
      expect(
        NoteListImageProfile.toCompactText(),
        contains('resolve=0,sync=0,async=0'),
      );
    });

    test('endSession 之后再出的图不会记进上一段', () {
      NoteListImageProfile.beginSession();
      final start = NoteListImageProfile.markResolveStart();
      NoteListImageProfile.endSession();

      NoteListImageProfile.markFirstFrame(
        startMicros: start,
        synchronous: false,
      );

      // 会话已经关了，async 不该涨；这一格量的是「这一段滚动里的图片管线」。
      expect(NoteListImageProfile.toCompactText(), contains('async=0'));
    });
  });

  group('同步命中与异步等待分开计', () {
    test('imageCache 命中只涨 sync，不进等待统计', () {
      NoteListImageProfile.beginSession();
      final start = NoteListImageProfile.markResolveStart();
      NoteListImageProfile.markFirstFrame(
        startMicros: start,
        synchronous: true,
      );

      final text = NoteListImageProfile.toCompactText();
      expect(text, contains('resolve=1'));
      expect(text, contains('sync=1'));
      expect(text, contains('async=0'));
      expect(text, contains('worstWait=0.0ms'));
    });

    test('异步出图记进 async 和等待时长', () async {
      NoteListImageProfile.beginSession();
      final start = NoteListImageProfile.markResolveStart();
      expect(start, isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 12));
      NoteListImageProfile.markFirstFrame(
        startMicros: start,
        synchronous: false,
      );

      final text = NoteListImageProfile.toCompactText();
      expect(text, contains('async=1'));
      expect(text, contains('sync=0'));
      final worst = RegExp(r'worstWait=([\d.]+)ms').firstMatch(text);
      expect(worst, isNotNull);
      expect(double.parse(worst!.group(1)!), greaterThanOrEqualTo(10.0));
    });
  });

  test('解析了但还没出图的记进 pending', () {
    NoteListImageProfile.beginSession();
    NoteListImageProfile.markResolveStart();
    NoteListImageProfile.markResolveStart();
    final third = NoteListImageProfile.markResolveStart();
    NoteListImageProfile.markFirstFrame(
      startMicros: third,
      synchronous: true,
    );

    // pending 大说明解码排到了会话结束之后，那部分成本会记到下一段去 ——
    // 读日志时不看这一格，会把「图片很快」这个结论建立在漏掉的样本上。
    expect(NoteListImageProfile.toCompactText(), contains('pending=2'));
  });
}
