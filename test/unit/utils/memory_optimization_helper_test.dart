import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/memory_optimization_helper.dart';

void main() {
  group('ProcessingStrategyExt', () {
    test('description should return correct labels', () {
      expect(ProcessingStrategy.direct.description, '直接处理');
      expect(ProcessingStrategy.chunked.description, '分块处理');
      expect(ProcessingStrategy.streaming.description, '流式处理');
      expect(ProcessingStrategy.minimal.description, '最小化处理');
    });

    test('useIsolate should return correct boolean', () {
      expect(ProcessingStrategy.direct.useIsolate, false);
      expect(ProcessingStrategy.chunked.useIsolate, false);
      expect(ProcessingStrategy.streaming.useIsolate, false);
      expect(ProcessingStrategy.minimal.useIsolate, false);
    });
  });
}
