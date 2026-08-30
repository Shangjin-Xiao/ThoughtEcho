import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/note_list_image_profile.dart';

void main() {
  tearDown(NoteListImageProfile.endSession);

  group('滚动会话之外不记账', () {
    test('没开会话时 markResolveStart 返回 null 且计数不动', () {
      NoteListImageProfile.endSession();

      expect(NoteListImageProfile.markResolveStart(), isNull);
      NoteListImageProfile.markFirstFrame(
        resolve: const NoteListImageResolve(session: 1, startMicros: 0),
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
        resolve: start,
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
        resolve: start,
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
        resolve: start,
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
      resolve: third,
      synchronous: true,
    );

    // pending 大说明解码排到了会话结束之后，那部分成本会记到下一段去 ——
    // 读日志时不看这一格，会把「图片很快」这个结论建立在漏掉的样本上。
    expect(NoteListImageProfile.toCompactText(), contains('pending=2'));
  });

  test('上一段开始解析、这一段才出图的记进 stale，不污染当段', () {
    NoteListImageProfile.beginSession();
    final crossing = NoteListImageProfile.markResolveStart();

    // 用户接着滑了第二段，解码这时候才完成。
    NoteListImageProfile.beginSession();
    NoteListImageProfile.markFirstFrame(
      resolve: crossing,
      synchronous: false,
    );

    final text = NoteListImageProfile.toCompactText();
    // 不带会话代号的话，这里会凭空多一个 async（没有对应的 resolve），
    // 等待时长还横跨两段——又一个「在边界上给出看起来合理其实错的数」。
    expect(text, contains('resolve=0'));
    expect(text, contains('async=0'));
    expect(text, contains('stale=1'));
    expect(text, contains('worstWait=0.0ms'));
  });

  test('失败是终态，记进 failed 而不是一直躺在 pending 里', () {
    NoteListImageProfile.beginSession();
    final ok = NoteListImageProfile.markResolveStart();
    final broken = NoteListImageProfile.markResolveStart();
    NoteListImageProfile.markFirstFrame(resolve: ok, synchronous: true);
    NoteListImageProfile.markFailed(resolve: broken);

    final text = NoteListImageProfile.toCompactText();
    expect(text, contains('failed=1'));
    // 关键：失败的那张不能算进 pending，否则「延迟解码有多严重」会被整体夸大，
    // 而那正是要拿来和 worstVsync 对相关性的数。
    expect(text, contains('pending=0'));
  });
}
