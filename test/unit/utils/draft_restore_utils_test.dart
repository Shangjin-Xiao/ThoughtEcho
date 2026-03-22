import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/utils/draft_restore_utils.dart';

void main() {
  group('buildRestoredDraftQuote', () {
    test('restores aiAnalysis for an existing note draft', () {
      final original = Quote(
        id: 'note-1',
        content: 'old content',
        date: '2026-03-20T12:00:00.000',
        aiAnalysis: 'old analysis',
      );

      final restored = buildRestoredDraftQuote(
        draftData: {
          'id': 'note-1',
          'plainText': 'draft content',
          'deltaContent': '[{"insert":"draft content\\n"}]',
          'aiAnalysis': 'draft analysis',
        },
        original: original,
      );

      expect(restored.id, 'note-1');
      expect(restored.content, 'draft content');
      expect(restored.aiAnalysis, 'draft analysis');
    });

    test('restores aiAnalysis for a new note draft', () {
      final restored = buildRestoredDraftQuote(
        draftData: {
          'id': 'new_123',
          'plainText': 'draft content',
          'deltaContent': '[{"insert":"draft content\\n"}]',
          'aiAnalysis': 'draft analysis',
        },
        now: DateTime.parse('2026-03-21T12:00:00.000Z'),
      );

      expect(restored.id, isNull);
      expect(restored.content, 'draft content');
      expect(restored.aiAnalysis, 'draft analysis');
      expect(restored.editSource, 'fullscreen');
    });
  });
}
