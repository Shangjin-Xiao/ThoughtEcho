import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/generated_card.dart';

void main() {
  group('GeneratedCard.fromJson', () {
    test('parses standard JSON correctly', () {
      final json = {
        'id': 'card_123',
        'noteId': 'note_456',
        'originalContent': 'Test content',
        'svgContent': '<svg></svg>',
        'type': 'CardType.knowledge',
        'createdAt': '2026-03-29T10:00:00.000Z',
        'author': 'Author',
        'source': 'Book',
        'location': 'Beijing',
        'weather': 'Sunny',
        'temperature': '25C',
        'date': '2026-03-29',
        'dayPeriod': 'Morning',
      };

      final card = GeneratedCard.fromJson(json);

      expect(card.id, 'card_123');
      expect(card.noteId, 'note_456');
      expect(card.originalContent, 'Test content');
      expect(card.svgContent, '<svg></svg>');
      expect(card.type, CardType.knowledge);
      expect(card.createdAt, DateTime.parse('2026-03-29T10:00:00.000Z'));
      expect(card.author, 'Author');
      expect(card.source, 'Book');
    });

    test('handles missing or non-string fields gracefully without crashing',
        () {
      final json = <String, dynamic>{
        'id': 123, // non-string id
        'noteId': null,
        'originalContent': null,
        'svgContent': null,
        'type': 'invalid_enum_type',
        'createdAt': 'invalid-date-format',
        'author': 999,
      };

      final card = GeneratedCard.fromJson(json);

      expect(card.id, '123');
      expect(card.noteId, '');
      expect(card.originalContent, '');
      expect(card.svgContent, '');
      expect(card.type, CardType.knowledge); // default fallback
      expect(card.author, '999');
      expect(card.createdAt, isA<DateTime>());
    });

    test('supports enum name matching for type field', () {
      final json = {
        'id': 'card_789',
        'noteId': 'note_789',
        'originalContent': 'Content',
        'svgContent': '<svg></svg>',
        'type': 'sotaModern',
        'createdAt': '2026-03-29T10:00:00.000Z',
      };

      final card = GeneratedCard.fromJson(json);

      expect(card.type, CardType.sotaModern);
    });
  });
}
