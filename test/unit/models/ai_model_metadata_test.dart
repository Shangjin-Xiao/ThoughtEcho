import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/ai_model_metadata.dart';
import 'package:thoughtecho/models/ai_task.dart';

void main() {
  group('AITask', () {
    test('defines all six task slots with stable storage keys', () {
      expect(AITask.values, [
        AITask.dailyInsight,
        AITask.periodicInsight,
        AITask.dreaming,
        AITask.agent,
        AITask.cardGeneration,
        AITask.sessionTitle,
      ]);
      for (final task in AITask.values) {
        expect(AITask.tryParse(task.storageKey), task);
        expect(AITask.tryParse('  ${task.storageKey}  '), task);
      }
      expect(AITask.tryParse('unknown_task'), isNull);
      expect(AITask.tryParse(''), isNull);
      expect(AITask.tryParse(null), isNull);
    });
  });

  group('AIProtocolType', () {
    test('maps models.dev npm package identifiers to transport protocols', () {
      expect(
        AIProtocolType.tryFromModelsDevNpm('@ai-sdk/openai-compatible'),
        AIProtocolType.openAICompatible,
      );
      expect(
        AIProtocolType.tryFromModelsDevNpm('@ai-sdk/openai'),
        AIProtocolType.openAICompatible,
      );
      expect(
        AIProtocolType.tryFromModelsDevNpm('@ai-sdk/anthropic'),
        AIProtocolType.anthropicMessages,
      );
      expect(AIProtocolType.tryFromModelsDevNpm('@ai-sdk/unknown'), isNull);
      expect(
        AIProtocolType.fromModelsDevNpm('@ai-sdk/unknown'),
        AIProtocolType.openAICompatible,
      );
    });

    test('round-trips storageKey values', () {
      for (final protocol in AIProtocolType.values) {
        expect(AIProtocolType.fromStorageKey(protocol.storageKey), protocol);
      }
      expect(AIProtocolType.fromStorageKey('invalid'), isNull);
    });
  });

  group('AIModelMetadata', () {
    test('parses models.dev model schema fields accurately', () {
      final metadata = AIModelMetadata.fromModelsDevJson({
        'id': 'claude-sonnet-4-5',
        'reasoning': true,
        'tool_call': true,
        'modalities': {
          'input': ['text', 'image', 'pdf'],
          'output': ['text'],
        },
        'limit': {
          'context': 200000,
          'output': 64000,
        },
        'cost': {
          'input': 3,
          'output': 15.5,
        },
      });

      expect(metadata.contextWindow, 200000);
      expect(metadata.maxOutputTokens, 64000);
      expect(metadata.reasoning, isTrue);
      expect(metadata.toolCall, isTrue);
      expect(metadata.supportsVision, isTrue);
      expect(metadata.inputCostPerMillion, 3.0);
      expect(metadata.outputCostPerMillion, 15.5);
    });

    test(
        'marks supportsVision false when image is absent from input modalities',
        () {
      final metadata = AIModelMetadata.fromModelsDevJson({
        'reasoning': false,
        'tool_call': true,
        'modalities': {
          'input': ['text'],
        },
        'limit': {
          'context': 128000,
          'output': 8192,
        },
      });

      expect(metadata.supportsVision, isFalse);
      expect(metadata.reasoning, isFalse);
      expect(metadata.toolCall, isTrue);
      expect(metadata.contextWindow, 128000);
      expect(metadata.maxOutputTokens, 8192);
      expect(metadata.inputCostPerMillion, isNull);
      expect(metadata.outputCostPerMillion, isNull);
    });

    test('round-trips toJson and fromJson with value equality', () {
      const original = AIModelMetadata(
        contextWindow: 131072,
        maxOutputTokens: 16384,
        reasoning: true,
        toolCall: true,
        supportsVision: false,
        inputCostPerMillion: 0.55,
        outputCostPerMillion: 2.19,
      );

      final restored = AIModelMetadata.fromJson(original.toJson());
      expect(restored, equals(original));
      expect(restored.hashCode, equals(original.hashCode));

      final updated = original.copyWith(
        contextWindow: 65536,
        inputCostPerMillion: null,
      );
      expect(updated.contextWindow, 65536);
      expect(updated.inputCostPerMillion, isNull);
      expect(updated.maxOutputTokens, 16384);
    });
  });
}
