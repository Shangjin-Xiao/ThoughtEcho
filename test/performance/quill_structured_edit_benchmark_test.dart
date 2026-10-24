import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/quill_structured_edit.dart';

void main() {
  test('alignPunctuationStyle performance benchmark', () {
    final original = 'This is a "test" with “curly” quotes and plain ones.';
    final replacement = 'Replacement text.';

    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < 50000; i++) {
      QuillStructuredEdit.alignPunctuationStyle(replacement, original);
    }
    stopwatch.stop();

    print(
        'alignPunctuationStyle x50000 took ${stopwatch.elapsedMilliseconds}ms');
    expect(stopwatch.elapsedMilliseconds, lessThan(500));
  });

  test('plainTextOf performance benchmark', () {
    final ops = [
      {'insert': 'Hello\nWorld\n'},
      {'insert': 'End\n'}
    ];

    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < 50000; i++) {
      QuillStructuredEdit.plainTextOf(ops);
    }
    stopwatch.stop();

    print('plainTextOf x50000 took ${stopwatch.elapsedMilliseconds}ms');
    expect(stopwatch.elapsedMilliseconds, lessThan(500));
  });
}
