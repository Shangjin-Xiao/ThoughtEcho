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

      test('copyWith updates every field', () {
        const original = LocalAISettings(
          enabled: false,
          speechToTextEnabled: true,
          ocrEnabled: true,
          aiSearchEnabled: true,
          aiCorrectionEnabled: true,
          sourceRecognitionEnabled: true,
          smartTagsEnabled: true,
          noteClassificationEnabled: true,
          emotionDetectionEnabled: true,
          relatedNotesEnabled: true,
        );

        final updated = original.copyWith(
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

        expect(updated.enabled, isTrue);
        expect(updated.speechToTextEnabled, isFalse);
        expect(updated.ocrEnabled, isFalse);
        expect(updated.aiSearchEnabled, isFalse);
        expect(updated.aiCorrectionEnabled, isFalse);
        expect(updated.sourceRecognitionEnabled, isFalse);
        expect(updated.smartTagsEnabled, isFalse);
        expect(updated.noteClassificationEnabled, isFalse);
        expect(updated.emotionDetectionEnabled, isFalse);
        expect(updated.relatedNotesEnabled, isFalse);
      });

      test('copyWith with no arguments returns equivalent instance', () {
        const original = LocalAISettings(enabled: true);
        final copy = original.copyWith();

        expect(copy, equals(original));
      });
    });

    group('equality and toString', () {
      test('equals operator and hashCode work as expected', () {
        // 使用 final（非 const）避免编译期常量规范化命中 identical 短路分支，
        // 确保字段逐一比较与 hashCode 计算被真实执行。
        final a = LocalAISettings(
          enabled: true,
          speechToTextEnabled: false,
        );
        final b = LocalAISettings(
          enabled: true,
          speechToTextEnabled: false,
        );

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
        expect(identical(a, b), isFalse);

        final base = LocalAISettings(
          enabled: false,
          speechToTextEnabled: true,
          ocrEnabled: true,
          aiSearchEnabled: true,
          aiCorrectionEnabled: true,
          sourceRecognitionEnabled: true,
          smartTagsEnabled: true,
          noteClassificationEnabled: true,
          emotionDetectionEnabled: true,
          relatedNotesEnabled: true,
        );
        final variants = <LocalAISettings>[
          base.copyWith(enabled: true),
          base.copyWith(speechToTextEnabled: false),
          base.copyWith(ocrEnabled: false),
          base.copyWith(aiSearchEnabled: false),
          base.copyWith(aiCorrectionEnabled: false),
          base.copyWith(sourceRecognitionEnabled: false),
          base.copyWith(smartTagsEnabled: false),
          base.copyWith(noteClassificationEnabled: false),
          base.copyWith(emotionDetectionEnabled: false),
          base.copyWith(relatedNotesEnabled: false),
        ];
        for (final variant in variants) {
          expect(variant, isNot(equals(base)));
        }
      });

      test('toString contains class name and key field values', () {
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
        final str = settings.toString();

        expect(str, contains('LocalAISettings'));
        expect(str, contains('enabled: true'));
        expect(str, contains('speechToTextEnabled: false'));
        expect(str, contains('ocrEnabled: false'));
        expect(str, contains('aiSearchEnabled: false'));
        expect(str, contains('aiCorrectionEnabled: false'));
        expect(str, contains('sourceRecognitionEnabled: false'));
        expect(str, contains('smartTagsEnabled: false'));
        expect(str, contains('noteClassificationEnabled: false'));
        expect(str, contains('emotionDetectionEnabled: false'));
        expect(str, contains('relatedNotesEnabled: false'));
      });
    });
  });
}
