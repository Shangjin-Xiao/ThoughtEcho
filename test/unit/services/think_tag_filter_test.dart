import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/openai_stream_service.dart';

/// 把一串 chunk 喂进过滤器，返回最终可见的正文。
String runFilter(List<String> chunks) {
  final filter = ThinkTagFilter();
  final buffer = StringBuffer();
  for (final chunk in chunks) {
    buffer.write(filter.process(chunk));
  }
  buffer.write(filter.flush());
  return buffer.toString();
}

void main() {
  group('ThinkTagFilter', () {
    test('没有思考标签时原样透传', () {
      expect(runFilter(['今天', '写点什么？']), '今天写点什么？');
    });

    test('剥掉完整的思考块，只留正文', () {
      expect(
        runFilter(['<think>先想想天气</think>窗外在下雨，你在想什么？']),
        '窗外在下雨，你在想什么？',
      );
    });

    test('标签被切在 chunk 中间也能剥干净', () {
      expect(
        runFilter(['<thi', 'nk>用户在夜里记录</thi', 'nk>夜色很静，', '适合想事情。']),
        '夜色很静，适合想事情。',
      );
    });

    test('半截标签不会被当成正文提前吐出去', () {
      final filter = ThinkTagFilter();
      // `<thi` 可能是 `<think>` 的开头，必须先攒着而不是立刻输出。
      expect(filter.process('好的<thi'), '好的');
      expect(filter.process('nk>思考</think>结果'), '结果');
    });

    test('支持 <thinking> 变体', () {
      expect(
        runFilter(['<thinking>推理过程</thinking>正文']),
        '正文',
      );
    });

    test('思考块前后的正文都保留', () {
      expect(
        runFilter(['前言<think>中间</think>后记']),
        '前言后记',
      );
    });

    test('同一条流里多个思考块都剥掉', () {
      expect(
        runFilter(['<think>一</think>A<think>二</think>B']),
        'AB',
      );
    });

    test('未闭合的思考块整段丢弃，不吐半截推理', () {
      expect(runFilter(['<think>想到一半就断了']), '');
    });

    test('小于号不构成标签时不受影响', () {
      expect(runFilter(['a < b，b > c']), 'a < b，b > c');
    });

    test('剥下来的思考内容转交 onThinking', () {
      final thinking = StringBuffer();
      final filter = ThinkTagFilter(onThinking: thinking.write);

      expect(filter.process('<think>先看天气，'), '');
      expect(filter.process('再决定语气</think>今天想写点什么？'), '今天想写点什么？');
      expect(filter.flush(), '');
      expect(thinking.toString(), '先看天气，再决定语气');
    });

    test('没有 onThinking 时思考内容直接丢弃', () {
      // 每日提示面板在整条流没有正文时会退回本地提示，
      // 所以这里返回空串是对的——绝不能把推理当答案显示。
      expect(runFilter(['<think>只有思考</think>']), '');
    });
  });
}
