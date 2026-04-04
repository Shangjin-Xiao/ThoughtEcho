library;

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/ai_skill.dart';

void main() {
  group('AISkill model', () {
    test('creates instance with required fields', () {
      final skill = AISkill(
        id: 'note_summarize',
        name: 'Note Summarize',
        triggerWord: '/summary',
        systemPrompt: 'You summarize the given note.',
      );

      expect(skill.id, 'note_summarize');
      expect(skill.name, 'Note Summarize');
      expect(skill.triggerWord, '/summary');
      expect(skill.systemPrompt, 'You summarize the given note.');
      expect(skill.description, isNull);
      expect(skill.inputProperties, isEmpty);
      expect(skill.requiredInputs, isEmpty);
    });

    test('throws when required fields are invalid', () {
      expect(
        () => AISkill(
          id: '',
          name: 'Name',
          triggerWord: '/x',
          systemPrompt: 'prompt',
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => AISkill(
          id: 'invalid id',
          name: 'Name',
          triggerWord: '/x',
          systemPrompt: 'prompt',
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => AISkill(
          id: 'valid_id',
          name: '',
          triggerWord: '/x',
          systemPrompt: 'prompt',
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => AISkill(
          id: 'valid_id',
          name: 'Name',
          triggerWord: '',
          systemPrompt: 'prompt',
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => AISkill(
          id: 'valid_id',
          name: 'Name',
          triggerWord: '/x',
          systemPrompt: '',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws when required inputs are not defined in properties', () {
      expect(
        () => AISkill(
          id: 'note_summarize',
          name: 'Note Summarize',
          triggerWord: '/summary',
          systemPrompt: 'You summarize the given note.',
          inputProperties: {
            'note': {'type': 'string'},
          },
          requiredInputs: const ['tone'],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('toOpenAITool maps to strict OpenAI function schema', () {
      final skill = AISkill(
        id: 'note_summarize',
        name: 'Note Summarize',
        triggerWord: '/summary',
        systemPrompt: 'You summarize the given note.',
        description: 'Summarize a note with optional tone.',
        inputProperties: {
          'note': {
            'type': 'string',
            'description': 'The note content to summarize.',
          },
          'tone': {
            'type': 'string',
            'enum': ['brief', 'detailed'],
          },
        },
        requiredInputs: const ['note'],
      );

      final tool = skill.toOpenAITool();
      final function = tool['function'] as Map<String, Object?>;
      final parameters = function['parameters'] as Map<String, Object?>;
      final properties = parameters['properties'] as Map<String, Object?>;

      expect(tool['type'], 'function');
      expect(function['name'], 'note_summarize');
      expect(function['description'], 'Summarize a note with optional tone.');
      expect(function['strict'], isTrue);
      expect(parameters['type'], 'object');
      expect(parameters['additionalProperties'], isFalse);
      expect(parameters['required'], ['note']);
      expect(properties.keys, containsAll(['note', 'tone']));
    });

    test('toOpenAITool defaults required fields to all defined properties', () {
      final skill = AISkill(
        id: 'rewrite_note',
        name: 'Rewrite Note',
        triggerWord: '/rewrite',
        systemPrompt: 'You rewrite note content.',
        inputProperties: {
          'content': {'type': 'string'},
          'style': {'type': 'string'},
        },
      );

      final tool = skill.toOpenAITool();
      final function = tool['function'] as Map<String, Object?>;
      final parameters = function['parameters'] as Map<String, Object?>;
      final required = parameters['required'] as List<Object?>;

      expect(required, ['content', 'style']);
    });
  });
}
