import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/intelligent_memory_manager.dart';

void main() {
  group('Intelligent Memory Manager Tests', () {
    test('MemoryPressureException formats correctly', () {
      final exception = MemoryPressureException('Test pressure message');
      expect(exception.toString(),
          equals('MemoryPressureException: Test pressure message'));
    });
  });
}
