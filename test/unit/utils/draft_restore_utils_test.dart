import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/utils/draft_restore_utils.dart';

void main() {
  group('buildRestoredDraftQuote', () {
    test('restores fields for an existing note draft', () {
      final original = Quote(
        id: 'note-1',
        content: 'old content',
        date: '2026-03-20T12:00:00.000',
        aiAnalysis: 'old analysis',
        sourceAuthor: 'old author',
        sourceWork: 'old work',
        tagIds: ['tag1'],
        colorHex: '#FFFFFF',
        location: 'old location',
        latitude: 1.0,
        longitude: 2.0,
        weather: 'Sunny',
        temperature: '25',
      );

      final restored = buildRestoredDraftQuote(
        draftData: {
          'id': 'note-1',
          'plainText': 'draft content',
          'deltaContent': '[{"insert":"draft content\\n"}]',
          'aiAnalysis': 'draft analysis',
          'author': 'new author',
          'work': 'new work',
          'tagIds': ['tag2'],
          'colorHex': '#000000',
          'location': 'new location',
          'latitude': 3.0,
          'longitude': 4.0,
          'weather': 'Rainy',
          'temperature': '20',
        },
        original: original,
      );

      expect(restored.id, 'note-1');
      expect(restored.content, 'draft content');
      expect(restored.deltaContent, '[{"insert":"draft content\\n"}]');
      expect(restored.aiAnalysis, 'draft analysis');
      expect(restored.sourceAuthor, 'new author');
      expect(restored.sourceWork, 'new work');
      expect(restored.tagIds, ['tag2']);
      expect(restored.colorHex, '#000000');
      expect(restored.location, 'new location');
      expect(restored.latitude, 3.0);
      expect(restored.longitude, 4.0);
      expect(restored.weather, 'Rainy');
      expect(restored.temperature, '20');
    });

    test('restores fields for a new note draft', () {
      final restored = buildRestoredDraftQuote(
        draftData: {
          'id': 'new_123',
          'plainText': 'draft content',
          'deltaContent': '[{"insert":"draft content\\n"}]',
          'aiAnalysis': 'draft analysis',
          'author': 'new author',
          'work': 'new work',
          'tagIds': ['tag2'],
          'colorHex': '#000000',
          'location': 'new location',
          'latitude': 3.0,
          'longitude': 4.0,
          'weather': 'Rainy',
          'temperature': '20',
        },
        now: DateTime.parse('2026-03-21T12:00:00.000Z'),
      );

      expect(restored.id, isNull);
      expect(restored.content, 'draft content');
      expect(restored.deltaContent, '[{"insert":"draft content\\n"}]');
      expect(restored.date, '2026-03-21T12:00:00.000Z');
      expect(restored.aiAnalysis, 'draft analysis');
      expect(restored.sourceAuthor, 'new author');
      expect(restored.sourceWork, 'new work');
      expect(restored.tagIds, ['tag2']);
      expect(restored.colorHex, '#000000');
      expect(restored.location, 'new location');
      expect(restored.latitude, 3.0);
      expect(restored.longitude, 4.0);
      expect(restored.weather, 'Rainy');
      expect(restored.temperature, '20');
      expect(restored.editSource, 'fullscreen');
    });

    test('restores fields with null values gracefully', () {
      final restored = buildRestoredDraftQuote(
        draftData: {
          'id': 'new_123',
          // plainText will default to '' if null according to logic
        },
        now: DateTime.parse('2026-03-21T12:00:00.000Z'),
      );

      expect(restored.id, isNull);
      expect(restored.content, '');
      expect(restored.deltaContent, isNull);
      expect(restored.aiAnalysis, isNull);
      expect(restored.sourceAuthor, isNull);
      expect(restored.sourceWork, isNull);
      expect(restored.tagIds, isEmpty);
      expect(restored.colorHex, isNull);
      expect(restored.location, isNull);
      expect(restored.latitude, isNull);
      expect(restored.longitude, isNull);
      expect(restored.weather, isNull);
      expect(restored.temperature, isNull);
      expect(restored.editSource, 'fullscreen');
    });
  });
}
