import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/ai_assistant_entry.dart';

void main() {
  group('AIAssistantEntryConfig', () {
    test('explore entry defaults to agent mode', () {
      final config = AIAssistantEntryConfig(
        source: AIAssistantEntrySource.explore,
      );

      expect(config.defaultMode, AIAssistantPageMode.agent);
      expect(config.allowsMode(AIAssistantPageMode.chat), isFalse);
      expect(config.allowsMode(AIAssistantPageMode.noteChat), isFalse);
      expect(config.allowsMode(AIAssistantPageMode.agent), isTrue);
    });

    test('note entry defaults to agent mode', () {
      final config = AIAssistantEntryConfig(
        source: AIAssistantEntrySource.note,
      );

      expect(config.defaultMode, AIAssistantPageMode.agent);
      expect(config.allowsMode(AIAssistantPageMode.chat), isFalse);
      expect(config.allowsMode(AIAssistantPageMode.noteChat), isFalse);
      expect(config.allowsMode(AIAssistantPageMode.agent), isTrue);
    });

    test('falls back to default mode when restored mode is invalid', () {
      final config = AIAssistantEntryConfig(
        source: AIAssistantEntrySource.explore,
      );

      expect(
        config.resolveRestoredMode(AIAssistantPageMode.noteChat),
        AIAssistantPageMode.agent,
      );
    });
  });
}
