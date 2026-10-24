import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thoughtecho/utils/quill_structured_edit.dart';

void main() {
  test('alignPunctuationStyle performance benchmark', () {
    const original = 'This is a "test" with “curly” quotes and plain ones.';
    const replacement = 'Replacement text.';
    const iterations = 50000;

    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      QuillStructuredEdit.alignPunctuationStyle(replacement, original);
    }
    stopwatch.stop();

    final elapsedMs = stopwatch.elapsedMilliseconds;
    final usPerOp =
        (stopwatch.elapsedMicroseconds / iterations).toStringAsFixed(2);

    debugPrint(
      'alignPunctuationStyle x$iterations took $elapsedMs ms ($usPerOp us/op)',
    );
    expect(elapsedMs, greaterThanOrEqualTo(0));
  });

  test('plainTextOf performance benchmark', () {
    final ops = [
      {'insert': 'Hello\nWorld\n'},
      {'insert': 'End\n'}
    ];
    const iterations = 50000;

    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      QuillStructuredEdit.plainTextOf(ops);
    }
    stopwatch.stop();

    final elapsedMs = stopwatch.elapsedMilliseconds;
    final usPerOp =
        (stopwatch.elapsedMicroseconds / iterations).toStringAsFixed(2);

    debugPrint(
      'plainTextOf x$iterations took $elapsedMs ms ($usPerOp us/op)',
    );
    expect(elapsedMs, greaterThanOrEqualTo(0));
  });
}
