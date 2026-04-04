library;

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/widgets/note_list/scroll_alignment.dart';

void main() {
  group('shouldSkipVisibleTargetAlignment', () {
    test(
        'skips redundant scrolling when target is already visible in normal mode',
        () {
      final shouldSkip = shouldSkipVisibleTargetAlignment(
        targetOffset: 480,
        currentOffset: 320,
        viewportExtent: 400,
        forceAlignToTop: false,
      );

      expect(shouldSkip, isTrue);
    });

    test(
        'does not skip alignment when notification navigation requires exact top alignment',
        () {
      final shouldSkip = shouldSkipVisibleTargetAlignment(
        targetOffset: 480,
        currentOffset: 320,
        viewportExtent: 400,
        forceAlignToTop: true,
      );

      expect(shouldSkip, isFalse);
    });
  });
}
