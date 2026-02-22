/// 本地 AI 服务相关测试
///
/// 测试语音识别结果、录制状态模型以及语音浮层阶段逻辑
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/speech_recognition_result.dart';
import 'package:thoughtecho/widgets/local_ai/voice_input_overlay.dart';

void main() {
  group('RecordingStatus Tests', () {
    test('idle status has correct default values', () {
      const status = RecordingStatus();
      expect(status.state, RecordingState.idle);
      expect(status.isRecording, false);
      expect(status.isProcessing, false);
      expect(status.hasError, false);
      expect(status.durationSeconds, 0.0);
      expect(status.volumeLevel, 0.0);
    });

    test('isRecording returns true only for recording state', () {
      const recording = RecordingStatus(state: RecordingState.recording);
      const processing = RecordingStatus(state: RecordingState.processing);
      const completed = RecordingStatus(state: RecordingState.completed);

      expect(recording.isRecording, true);
      expect(processing.isRecording, false);
      expect(completed.isRecording, false);
    });

    test('copyWith correctly updates state', () {
      const original = RecordingStatus(
        state: RecordingState.recording,
        durationSeconds: 5.0,
        volumeLevel: 0.5,
      );

      final updated = original.copyWith(state: RecordingState.processing);

      expect(updated.state, RecordingState.processing);
      expect(updated.durationSeconds, 5.0); // preserved
      expect(updated.volumeLevel, 0.5); // preserved
    });

    test('copyWith preserves original values when not specified', () {
      const original = RecordingStatus(
        state: RecordingState.recording,
        durationSeconds: 10.0,
        volumeLevel: 0.8,
        errorMessage: null,
      );

      final updated = original.copyWith(volumeLevel: 0.3);

      expect(updated.state, RecordingState.recording);
      expect(updated.durationSeconds, 10.0);
      expect(updated.volumeLevel, 0.3);
    });
  });

  group('VoiceOverlayPhase Tests', () {
    test('all phases are defined', () {
      expect(VoiceOverlayPhase.values.length, 4);
      expect(
          VoiceOverlayPhase.values, contains(VoiceOverlayPhase.initializing));
      expect(VoiceOverlayPhase.values, contains(VoiceOverlayPhase.recording));
      expect(VoiceOverlayPhase.values, contains(VoiceOverlayPhase.processing));
      expect(VoiceOverlayPhase.values, contains(VoiceOverlayPhase.error));
    });

    test('isDone logic: not recording, not initializing, has text, no error',
        () {
      // Simulate the isDone logic from voice_input_overlay.dart
      bool computeIsDone(VoiceOverlayPhase phase, bool hasText, bool isError) {
        final isRecording = phase == VoiceOverlayPhase.recording;
        final isInitializing = phase == VoiceOverlayPhase.initializing;
        return !isRecording && !isInitializing && hasText && !isError;
      }

      // Should be done: processing phase with text
      expect(computeIsDone(VoiceOverlayPhase.processing, true, false), true);

      // Should NOT be done: recording phase
      expect(computeIsDone(VoiceOverlayPhase.recording, true, false), false);

      // Should NOT be done: no text
      expect(computeIsDone(VoiceOverlayPhase.processing, false, false), false);

      // Should NOT be done: error
      expect(computeIsDone(VoiceOverlayPhase.processing, true, true), false);

      // Should NOT be done: initializing
      expect(computeIsDone(VoiceOverlayPhase.initializing, true, false), false);
    });
  });

  group('SpeechRecognitionResult integration', () {
    test('empty result text should not be inserted into editor', () {
      final result = SpeechRecognitionResult(text: '');
      expect(result.text.trim().isEmpty, true);
    });

    test('whitespace-only result text should not be inserted', () {
      final result = SpeechRecognitionResult(text: '   \n  ');
      expect(result.text.trim().isEmpty, true);
    });

    test('valid result text should be inserted into editor', () {
      final result = SpeechRecognitionResult(text: '你好世界');
      expect(result.text.trim().isEmpty, false);
      expect(result.text.trim(), '你好世界');
    });

    test('result with leading/trailing whitespace is trimmed before insert',
        () {
      final result = SpeechRecognitionResult(text: '  你好世界  ');
      final trimmed = result.text.trim();
      expect(trimmed, '你好世界');
      expect(trimmed.isNotEmpty, true);
    });
  });
}
