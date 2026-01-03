import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/local_ai_model.dart';
import 'package:thoughtecho/models/speech_recognition_result.dart';
import 'package:thoughtecho/models/ocr_result.dart';
import 'package:thoughtecho/models/embedding_result.dart';
import 'package:thoughtecho/models/text_processing_result.dart';

void main() {
  group('LocalAIModel Tests', () {
    test('LocalAIModelInfo formattedSize returns correct format', () {
      const model = LocalAIModelInfo(
        id: 'test',
        name: 'Test Model',
        type: LocalAIModelType.llm,
        description: 'Test description',
        sizeBytes: 1500 * 1024 * 1024, // 1.5 GB
        downloadUrl: 'https://example.com',
        fileName: 'test.bin',
        version: '1.0',
      );

      expect(model.formattedSize, '1.46 GB');
    });

    test('LocalAIModelInfo copyWith updates status', () {
      const model = LocalAIModelInfo(
        id: 'test',
        name: 'Test Model',
        type: LocalAIModelType.llm,
        description: 'Test',
        sizeBytes: 100,
        downloadUrl: '',
        fileName: '',
        version: '1.0',
      );

      final updated = model.copyWith(status: LocalAIModelStatus.downloaded);

      expect(updated.status, LocalAIModelStatus.downloaded);
      expect(updated.id, model.id);
    });

    test('LocalAIModels.all returns all predefined models', () {
      final models = LocalAIModels.all;

      // Check for specific essential models rather than exact count
      expect(models.isNotEmpty, true);
      expect(models.any((m) => m.id == 'gemma-2b'), true);
      expect(models.any((m) => m.id == 'gecko-384'), true);
      expect(models.any((m) => m.id == 'whisper-tiny'), true);
      expect(models.any((m) => m.id == 'tesseract-chi-sim-eng'), true);
    });

    test('LocalAIModels.byType filters correctly', () {
      final llmModels = LocalAIModels.byType(LocalAIModelType.llm);
      final asrModels = LocalAIModels.byType(LocalAIModelType.asr);

      // Check models exist for each type
      expect(llmModels.isNotEmpty, true);
      expect(asrModels.isNotEmpty, true);
      // LLM should contain Gemma
      expect(llmModels.any((m) => m.id == 'gemma-2b'), true);
      // ASR should contain Whisper models
      expect(asrModels.any((m) => m.id == 'whisper-tiny'), true);
    });
  });

  group('SpeechRecognitionResult Tests', () {
    test('isEmpty returns true for empty text', () {
      const result = SpeechRecognitionResult(text: '');
      expect(result.isEmpty, true);
      expect(result.isNotEmpty, false);
    });

    test('isEmpty returns true for whitespace only', () {
      const result = SpeechRecognitionResult(text: '   ');
      expect(result.isEmpty, true);
    });

    test('isNotEmpty returns true for non-empty text', () {
      const result = SpeechRecognitionResult(text: 'Hello');
      expect(result.isEmpty, false);
      expect(result.isNotEmpty, true);
    });

    test('toJson and fromJson roundtrip', () {
      final original = SpeechRecognitionResult(
        text: 'Test text',
        confidence: 0.95,
        isFinal: true,
        timestamp: DateTime(2024, 1, 1),
      );

      final json = original.toJson();
      final restored = SpeechRecognitionResult.fromJson(json);

      expect(restored.text, original.text);
      expect(restored.confidence, original.confidence);
      expect(restored.isFinal, original.isFinal);
    });
  });

  group('OCRResult Tests', () {
    test('isEmpty returns true for empty text', () {
      const result = OCRResult(fullText: '');
      expect(result.isEmpty, true);
    });

    test('selectedBlocks returns only selected blocks', () {
      const result = OCRResult(
        fullText: 'Test',
        blocks: [
          TextBlock(
            text: 'Block 1',
            boundingBox: Rect.zero,
            isSelected: true,
          ),
          TextBlock(
            text: 'Block 2',
            boundingBox: Rect.zero,
            isSelected: false,
          ),
          TextBlock(
            text: 'Block 3',
            boundingBox: Rect.zero,
            isSelected: true,
          ),
        ],
      );

      expect(result.selectedBlocks.length, 2);
      expect(result.selectedText, 'Block 1\nBlock 3');
    });
  });

  group('TextProcessingResult Tests', () {
    test('SourceRecognitionResult hasSource is true when author is present', () {
      const result = SourceRecognitionResult(
        author: 'Test Author',
      );
      expect(result.hasSource, true);
    });

    test('SourceRecognitionResult hasSource is true when work is present', () {
      const result = SourceRecognitionResult(
        work: 'Test Work',
      );
      expect(result.hasSource, true);
    });

    test('SourceRecognitionResult hasSource is false when both are null', () {
      const result = SourceRecognitionResult();
      expect(result.hasSource, false);
    });

    test('SourceRecognitionResult formattedSource formats correctly', () {
      const result = SourceRecognitionResult(
        author: 'Author',
        work: 'Work',
      );
      expect(result.formattedSource, 'Author - 《Work》');
    });

    test('TextCorrectionResult noChange creates unchanged result', () {
      final result = TextCorrectionResult.noChange('original text');
      
      expect(result.originalText, 'original text');
      expect(result.correctedText, 'original text');
      expect(result.hasChanges, false);
    });

    test('TagSuggestionResult tagNames extracts names', () {
      const result = TagSuggestionResult(
        tags: [
          SuggestedTag(name: 'tag1'),
          SuggestedTag(name: 'tag2'),
          SuggestedTag(name: 'tag3'),
        ],
      );

      expect(result.tagNames, ['tag1', 'tag2', 'tag3']);
    });

    test('EmotionResult isPositive returns correct value', () {
      const happyResult = EmotionResult(primaryEmotion: EmotionType.happy);
      const sadResult = EmotionResult(primaryEmotion: EmotionType.sad);
      const neutralResult = EmotionResult(primaryEmotion: EmotionType.neutral);

      expect(happyResult.isPositive, true);
      expect(sadResult.isPositive, false);
      expect(neutralResult.isNeutral, true);
    });
  });

  group('Embedding Tests', () {
    test('cosineSimilarity returns 1.0 for identical vectors', () {
      final embedding1 = Embedding(
        vector: [1.0, 0.0, 0.0],
        sourceText: 'test',
      );
      final embedding2 = Embedding(
        vector: [1.0, 0.0, 0.0],
        sourceText: 'test',
      );

      expect(embedding1.cosineSimilarity(embedding2), closeTo(1.0, 0.001));
    });

    test('cosineSimilarity returns 0.0 for orthogonal vectors', () {
      final embedding1 = Embedding(
        vector: [1.0, 0.0, 0.0],
        sourceText: 'test',
      );
      final embedding2 = Embedding(
        vector: [0.0, 1.0, 0.0],
        sourceText: 'test',
      );

      expect(embedding1.cosineSimilarity(embedding2), closeTo(0.0, 0.001));
    });

    test('dimension returns correct vector length', () {
      final embedding = Embedding(
        vector: List.filled(384, 0.0),
        sourceText: 'test',
      );

      expect(embedding.dimension, 384);
    });
  });
}
