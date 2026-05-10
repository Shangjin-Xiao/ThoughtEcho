import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/ai_assistant_entry.dart';
import 'package:thoughtecho/models/ai_workflow_descriptor.dart';

void main() {
  group('AIAssistantEntryConfig', () {
    test('explore entry defaults to chat mode', () {
      final config = AIAssistantEntryConfig(
        source: AIAssistantEntrySource.explore,
      );

      expect(config.defaultMode, AIAssistantPageMode.chat);
      expect(config.allowsMode(AIAssistantPageMode.chat), isTrue);
      expect(config.allowsMode(AIAssistantPageMode.noteChat), isFalse);
      expect(config.allowsMode(AIAssistantPageMode.agent), isTrue);
    });

    test('note entry defaults to note chat mode', () {
      final config = AIAssistantEntryConfig(
        source: AIAssistantEntrySource.note,
      );

      expect(config.defaultMode, AIAssistantPageMode.noteChat);
      expect(config.allowsMode(AIAssistantPageMode.chat), isFalse);
      expect(config.allowsMode(AIAssistantPageMode.noteChat), isTrue);
      expect(config.allowsMode(AIAssistantPageMode.agent), isTrue);
    });

    test('falls back to default mode when restored mode is invalid', () {
      final config = AIAssistantEntryConfig(
        source: AIAssistantEntrySource.explore,
      );

      expect(
        config.resolveRestoredMode(AIAssistantPageMode.noteChat),
        AIAssistantPageMode.chat,
      );
    });
  });

  group('AIWorkflowCommandRegistry', () {
    test('matches localized slash commands', () {
      expect(
        AIWorkflowCommandRegistry.match('/润色'),
        AIWorkflowId.polish,
      );
      expect(
        AIWorkflowCommandRegistry.match('/续写'),
        AIWorkflowId.continueWriting,
      );
      expect(
        AIWorkflowCommandRegistry.match('/深度分析'),
        AIWorkflowId.deepAnalysis,
      );
      expect(
        AIWorkflowCommandRegistry.match('/分析来源'),
        AIWorkflowId.sourceAnalysis,
      );
      expect(
        AIWorkflowCommandRegistry.match('/智能洞察'),
        AIWorkflowId.insights,
      );
    });

    test('matches english aliases case-insensitively', () {
      expect(
        AIWorkflowCommandRegistry.match('/POLISH'),
        AIWorkflowId.polish,
      );
      expect(
        AIWorkflowCommandRegistry.match('/Continue'),
        AIWorkflowId.continueWriting,
      );
    });

    test('matches slash command when prompt text follows', () {
      expect(
        AIWorkflowCommandRegistry.match('/深度分析 帮我拆解重点'),
        AIWorkflowId.deepAnalysis,
      );
      expect(
        AIWorkflowCommandRegistry.match('/POLISH improve readability'),
        AIWorkflowId.polish,
      );
    });

    test('matches full-width slash command input', () {
      expect(
        AIWorkflowCommandRegistry.match('／深度分析'),
        AIWorkflowId.deepAnalysis,
      );
    });
  });
}
