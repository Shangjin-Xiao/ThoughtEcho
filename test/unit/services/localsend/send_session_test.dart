import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/localsend/localsend_send_provider.dart';
import 'package:thoughtecho/services/localsend/models/device.dart';
import 'package:thoughtecho/services/localsend/models/session_status.dart';

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

    test('cancelSession aborts a pending prepare request promptly', () async {
      final prepareStarted = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        if (request.uri.path.endsWith('/info')) {
          request.response
            ..statusCode = HttpStatus.ok
            ..write('{}');
          await request.response.close();
          return;
        }
        if (request.uri.path.endsWith('/prepare-upload')) {
          if (!prepareStarted.isCompleted) prepareStarted.complete();
          await request.response.done;
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });
      final file = File(
        '${Directory.systemTemp.path}/localsend-cancel-test.txt',
      );
      await file.writeAsString('payload');
      addTearDown(() async {
        if (await file.exists()) await file.delete();
      });
      final provider = LocalSendProvider();
      addTearDown(provider.dispose);
      late String sessionId;
      final sendFuture = provider.startSession(
        target: Device.empty.copyWith(
          ip: InternetAddress.loopbackIPv4.address,
          port: server.port,
          https: false,
          version: '2.1',
        ),
        files: [file],
        onSessionCreated: (value) => sessionId = value,
      );
      await prepareStarted.future.timeout(const Duration(seconds: 2));

      final sendCompleted = Completer<void>();
      sendFuture.then<void>(
        (_) => sendCompleted.complete(),
        onError: (_) => sendCompleted.complete(),
      );
      provider.cancelSession(sessionId);

      await sendCompleted.future.timeout(const Duration(seconds: 2));
      expect(
        provider.getSession(sessionId)?.status,
        SessionStatus.canceledBySender,
      );
    });

    test('cancelSession aborts a pending info handshake promptly', () async {
      final infoStarted = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        if (request.uri.path.endsWith('/info')) {
          if (!infoStarted.isCompleted) infoStarted.complete();
          await request.response.done;
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });
      final file = File(
        '${Directory.systemTemp.path}/localsend-handshake-cancel-test.txt',
      );
      await file.writeAsString('payload');
      addTearDown(() async {
        if (await file.exists()) await file.delete();
      });
      final provider = LocalSendProvider();
      addTearDown(provider.dispose);
      late String sessionId;
      final sendFuture = provider.startSession(
        target: Device.empty.copyWith(
          ip: InternetAddress.loopbackIPv4.address,
          port: server.port,
          https: false,
          version: '2.1',
        ),
        files: [file],
        onSessionCreated: (value) => sessionId = value,
      );
      await infoStarted.future.timeout(const Duration(seconds: 2));
      final sendCompleted = Completer<void>();
      sendFuture.then<void>(
        (_) => sendCompleted.complete(),
        onError: (_) => sendCompleted.complete(),
      );

      provider.cancelSession(sessionId);

      await sendCompleted.future.timeout(const Duration(seconds: 2));
      expect(
        provider.getSession(sessionId)?.status,
        SessionStatus.canceledBySender,
      );
    });
  });
}
