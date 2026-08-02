import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/thoughter_entry.dart';

void main() {
  group('ThoughterEntryConfig', () {
    test('explore entry defaults to agent mode', () {
      final config = ThoughterEntryConfig(
        source: ThoughterEntrySource.explore,
      );

      expect(config.defaultMode, ThoughterPageMode.agent);
      expect(config.allowsMode(ThoughterPageMode.chat), isFalse);
      expect(config.allowsMode(ThoughterPageMode.noteChat), isFalse);
      expect(config.allowsMode(ThoughterPageMode.agent), isTrue);
    });

    test('note entry defaults to agent mode', () {
      final config = ThoughterEntryConfig(
        source: ThoughterEntrySource.note,
      );

      expect(config.defaultMode, ThoughterPageMode.agent);
      expect(config.allowsMode(ThoughterPageMode.chat), isFalse);
      expect(config.allowsMode(ThoughterPageMode.noteChat), isFalse);
      expect(config.allowsMode(ThoughterPageMode.agent), isTrue);
    });

    test('falls back to default mode when restored mode is invalid', () {
      final config = ThoughterEntryConfig(
        source: ThoughterEntrySource.explore,
      );

      expect(
        config.resolveRestoredMode(ThoughterPageMode.noteChat),
        ThoughterPageMode.agent,
      );
    });
  });
}
