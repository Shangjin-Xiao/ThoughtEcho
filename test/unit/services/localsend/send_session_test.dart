import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/localsend/localsend_send_provider.dart';
import 'package:thoughtecho/services/localsend/models/device.dart';
import 'package:thoughtecho/services/localsend/models/session_status.dart';
import 'dart:io';

void main() {
  group('SendSession Tests', () {
    test('Can create a SendSession instance', () {
      final session = SendSession(
        sessionId: 'test-session-id',
        target: Device.empty,
        files: [],
        status: SessionStatus.waiting,
      );

      expect(session.sessionId, 'test-session-id');
      expect(session.remoteSessionId, isNull);
      expect(session.target, Device.empty);
      expect(session.files, isEmpty);
      expect(session.status, SessionStatus.waiting);
      expect(session.fileTokens, isNull);
      expect(session.errorMessage, isNull);
    });

    group('copyWith Tests', () {
      test('copyWith updates specified fields', () {
        final session = SendSession(
          sessionId: 'test-session-id',
          target: Device.empty,
          files: [],
          status: SessionStatus.waiting,
        );

        final newTarget = Device.empty.copyWith(alias: 'new-alias');
        final newFiles = [File('test.txt')];
        final newTokens = {'test.txt': 'token123'};

        final updatedSession = session.copyWith(
          sessionId: 'new-session-id',
          remoteSessionId: 'remote-id',
          target: newTarget,
          files: newFiles,
          status: SessionStatus.sending,
          fileTokens: newTokens,
          errorMessage: 'error',
        );

        expect(updatedSession.sessionId, 'new-session-id');
        expect(updatedSession.remoteSessionId, 'remote-id');
        expect(updatedSession.target, newTarget);
        expect(updatedSession.files, newFiles);
        expect(updatedSession.status, SessionStatus.sending);
        expect(updatedSession.fileTokens, newTokens);
        expect(updatedSession.errorMessage, 'error');
      });

      test('copyWith retains old fields when not specified', () {
        final session = SendSession(
          sessionId: 'test-session-id',
          remoteSessionId: 'remote-id',
          target: Device.empty,
          files: [],
          status: SessionStatus.waiting,
          fileTokens: {'file': 'token'},
          errorMessage: 'error',
        );

        final updatedSession = session.copyWith();

        expect(updatedSession.sessionId, session.sessionId);
        expect(updatedSession.remoteSessionId, session.remoteSessionId);
        expect(updatedSession.target, session.target);
        expect(updatedSession.files, session.files);
        expect(updatedSession.status, session.status);
        expect(updatedSession.fileTokens, session.fileTokens);
        expect(updatedSession.errorMessage, session.errorMessage);
      });
    });
  });
}
