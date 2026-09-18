import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/local_ai_settings.dart';

void main() {
  group('LocalAISettings', () {
    test('default constructor initializes with correct default values', () {
      const settings = LocalAISettings();

      expect(settings.enabled, isFalse);
      expect(settings.speechToTextEnabled, isTrue);
      expect(settings.ocrEnabled, isTrue);
      expect(settings.aiSearchEnabled, isTrue);
      expect(settings.aiCorrectionEnabled, isTrue);
      expect(settings.sourceRecognitionEnabled, isTrue);
      expect(settings.smartTagsEnabled, isTrue);
      expect(settings.noteClassificationEnabled, isTrue);
      expect(settings.emotionDetectionEnabled, isTrue);
      expect(settings.relatedNotesEnabled, isTrue);
    });

    test('defaultSettings factory returns default instance', () {
      final settings = LocalAISettings.defaultSettings();
      expect(settings, const LocalAISettings());
      expect(settings.enabled, isFalse);
    });

    test('custom constructor initializes with provided values', () {
      const settings = LocalAISettings(
        enabled: true,
        speechToTextEnabled: false,
        ocrEnabled: false,
        aiSearchEnabled: false,
        aiCorrectionEnabled: false,
        sourceRecognitionEnabled: false,
        smartTagsEnabled: false,
        noteClassificationEnabled: false,
        emotionDetectionEnabled: false,
        relatedNotesEnabled: false,
      );

      expect(settings.enabled, isTrue);
      expect(settings.speechToTextEnabled, isFalse);
      expect(settings.ocrEnabled, isFalse);
      expect(settings.aiSearchEnabled, isFalse);
      expect(settings.aiCorrectionEnabled, isFalse);
      expect(settings.sourceRecognitionEnabled, isFalse);
      expect(settings.smartTagsEnabled, isFalse);
      expect(settings.noteClassificationEnabled, isFalse);
      expect(settings.emotionDetectionEnabled, isFalse);
      expect(settings.relatedNotesEnabled, isFalse);
    });

    group('JSON serialization', () {
      test('toJson outputs correct map representation', () {
        const settings = LocalAISettings(
          enabled: true,
          speechToTextEnabled: false,
          ocrEnabled: true,
          aiSearchEnabled: false,
          aiCorrectionEnabled: true,
          sourceRecognitionEnabled: false,
          smartTagsEnabled: true,
          noteClassificationEnabled: false,
          emotionDetectionEnabled: true,
          relatedNotesEnabled: false,
        );

        final json = settings.toJson();

        expect(json, {
          'enabled': true,
          'speechToTextEnabled': false,
          'ocrEnabled': true,
          'aiSearchEnabled': false,
          'aiCorrectionEnabled': true,
          'sourceRecognitionEnabled': false,
          'smartTagsEnabled': true,
          'noteClassificationEnabled': false,
          'emotionDetectionEnabled': true,
          'relatedNotesEnabled': false,
        });
      });

      test('fromJson parses full JSON map correctly', () {
        final json = <String, dynamic>{
          'enabled': true,
          'speechToTextEnabled': false,
          'ocrEnabled': true,
          'aiSearchEnabled': false,
          'aiCorrectionEnabled': true,
          'sourceRecognitionEnabled': false,
          'smartTagsEnabled': true,
          'noteClassificationEnabled': false,
          'emotionDetectionEnabled': true,
          'relatedNotesEnabled': false,
        };

        final settings = LocalAISettings.fromJson(json);

        expect(settings.enabled, isTrue);
        expect(settings.speechToTextEnabled, isFalse);
        expect(settings.ocrEnabled, isTrue);
        expect(settings.aiSearchEnabled, isFalse);
        expect(settings.aiCorrectionEnabled, isTrue);
        expect(settings.sourceRecognitionEnabled, isFalse);
        expect(settings.smartTagsEnabled, isTrue);
        expect(settings.noteClassificationEnabled, isFalse);
        expect(settings.emotionDetectionEnabled, isTrue);
        expect(settings.relatedNotesEnabled, isFalse);
      });

      test('fromJson handles missing keys with default fallbacks', () {
        final settings = LocalAISettings.fromJson(const {});

        expect(settings.enabled, isFalse);
        expect(settings.speechToTextEnabled, isTrue);
        expect(settings.ocrEnabled, isTrue);
        expect(settings.aiSearchEnabled, isTrue);
        expect(settings.aiCorrectionEnabled, isTrue);
        expect(settings.sourceRecognitionEnabled, isTrue);
        expect(settings.smartTagsEnabled, isTrue);
        expect(settings.noteClassificationEnabled, isTrue);
        expect(settings.emotionDetectionEnabled, isTrue);
        expect(settings.relatedNotesEnabled, isTrue);
      });

      test('round-trip serialization produces identical instance', () {
        const original = LocalAISettings(
          enabled: true,
          speechToTextEnabled: false,
          ocrEnabled: true,
        );

        final json = original.toJson();
        final restored = LocalAISettings.fromJson(json);

        expect(restored, equals(original));
      });
    });

    group('copyWith', () {
      test('copyWith updates specified fields and preserves unsupplied fields',
          () {
        const original = LocalAISettings(enabled: false, ocrEnabled: true);

        final updated = original.copyWith(
          enabled: true,
          speechToTextEnabled: false,
        );

        expect(updated.enabled, isTrue);
        expect(updated.speechToTextEnabled, isFalse);
        expect(updated.ocrEnabled, isTrue);
        expect(updated.aiSearchEnabled, isTrue);
      });

      test('copyWith with no arguments returns equivalent instance', () {
        const original = LocalAISettings(enabled: true);
        final copy = original.copyWith();

        expect(copy, equals(original));
      });
    });

    group('equality and toString', () {
      test('equals operator and hashCode work as expected', () {
        const a = LocalAISettings(enabled: true, speechToTextEnabled: false);
        const b = LocalAISettings(enabled: true, speechToTextEnabled: false);
        const c = LocalAISettings(enabled: false, speechToTextEnabled: false);

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
        expect(a, isNot(equals(c)));
      });

      test('toString contains class name and key field values', () {
        const settings = LocalAISettings(enabled: true);
        final str = settings.toString();

        expect(str, contains('LocalAISettings'));
        expect(str, contains('enabled: true'));
        expect(str, contains('speechToTextEnabled: true'));
      });
    });
  });
}
