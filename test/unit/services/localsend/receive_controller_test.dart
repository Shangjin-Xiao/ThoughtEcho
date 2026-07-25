import "dart:typed_data";
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/localsend/models/session_status.dart';
import 'package:thoughtecho/services/localsend/receive_controller.dart';

class MockHttpRequest extends Fake implements HttpRequest {
  @override
  HttpHeaders get headers => MockHttpHeaders();

  @override
  StreamSubscription<Uint8List> listen(void Function(Uint8List event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return Stream<Uint8List>.fromIterable([
      Uint8List.fromList([1, 2, 3, 4])
    ]).listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}

class MockHttpHeaders extends Fake implements HttpHeaders {
  @override
  ContentType? get contentType => null;
}

void main() {
  group('ReceiveController Tests', () {
    late ReceiveController controller;

    setUp(() {
      controller = ReceiveController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('Can create a ReceiveController instance', () {
      expect(controller.sessions, isEmpty);
    });

    test('handleInfoRequest returns correct info', () {
      final info = controller.handleInfoRequest();
      expect(info['alias'], 'ThoughtEcho');
      expect(info['deviceType'], 'mobile');
      expect(info['download'], true);
    });

    test('handlePrepareUpload creates a session and approves it', () async {
      final requestData = {
        'info': {
          'alias': 'Test Sender',
          'version': '2.0',
          'deviceModel': 'Test Model',
          'deviceType': 'desktop',
          'fingerprint': 'test-fingerprint',
          'port': 53320,
          'protocol': 'http',
          'download': false,
        },
        'files': {
          'file-1': {
            'id': 'file-1',
            'fileName': 'test.txt',
            'size': 100,
            'fileType': 'text/plain',
          }
        }
      };

      final controllerWithApproval = ReceiveController(
        consumePreApproval: (fp) => true, // pre-approved
      );

      final response =
          await controllerWithApproval.handlePrepareUpload(requestData);

      expect(response, isNotNull);
      expect(response['sessionId'], isNotNull);
      expect(response['files'], isNotNull);
      expect(response['files']['file-1'], isNotNull);

      final session = controllerWithApproval.getSession(response['sessionId']);
      expect(session, isNotNull);
      expect(session!.status, SessionStatus.sending);
      expect(session.fileTokens!['file-1'], response['files']['file-1']);

      controllerWithApproval.dispose();
    });

    test('handlePrepareUpload rejects when approval is false', () async {
      final requestData = {
        'info': {
          'alias': 'Test Sender',
          'version': '2.0',
          'deviceModel': 'Test Model',
          'deviceType': 'desktop',
          'fingerprint': 'test-fingerprint',
          'port': 53320,
          'protocol': 'http',
          'download': false,
        },
        'files': {
          'file-1': {
            'id': 'file-1',
            'fileName': 'test.txt',
            'size': 100,
            'fileType': 'text/plain',
          }
        }
      };

      final controllerRejecting = ReceiveController(
        consumePreApproval: (fp) => false,
        onApprovalNeeded: (sessionId, totalBytes, senderAlias) async => false,
      );

      expect(
        () => controllerRejecting.handlePrepareUpload(requestData),
        throwsA(isA<Exception>()
            .having((e) => e.toString(), 'message', contains('接收端已拒绝'))),
      );

      controllerRejecting.dispose();
    });

    test('cancelSession updates session status', () async {
      final requestData = {
        'info': {
          'alias': 'Test Sender',
          'version': '2.0',
          'deviceModel': 'Test Model',
          'deviceType': 'desktop',
          'fingerprint': 'test-fingerprint',
          'port': 53320,
          'protocol': 'http',
          'download': false,
        },
        'files': {
          'file-1': {
            'id': 'file-1',
            'fileName': 'test.txt',
            'size': 100,
            'fileType': 'text/plain',
          }
        }
      };

      final controllerWithApproval = ReceiveController(
        consumePreApproval: (fp) => true,
      );

      final response =
          await controllerWithApproval.handlePrepareUpload(requestData);
      final sessionId = response['sessionId'];

      controllerWithApproval.cancelSession(sessionId);

      final session = controllerWithApproval.getSession(sessionId);
      expect(session!.status, SessionStatus.canceledByReceiver);

      controllerWithApproval.dispose();
    });

    test('handleFileUpload with fake HttpRequest', () async {
      final requestData = {
        'info': {
          'alias': 'Test Sender',
          'version': '2.0',
          'deviceModel': 'Test Model',
          'deviceType': 'desktop',
          'fingerprint': 'test-fingerprint',
          'port': 53320,
          'protocol': 'http',
          'download': false,
        },
        'files': {
          'file-1': {
            'id': 'file-1',
            'fileName': 'test.txt',
            'size': 4,
            'fileType': 'text/plain',
          }
        }
      };

      bool fileReceived = false;
      int bytesReceived = 0;
      final controllerForUpload = ReceiveController(
        consumePreApproval: (fp) => true,
        onFileReceived: (path) => fileReceived = true,
        onReceiveProgress: (received, total) => bytesReceived = received,
      );

      final response =
          await controllerForUpload.handlePrepareUpload(requestData);
      final sessionId = response['sessionId'];
      final token = response['files']['file-1'];

      final uploadResponse = await controllerForUpload.handleFileUpload(
        sessionId,
        'file-1',
        token,
        MockHttpRequest(),
      );

      expect(uploadResponse['message'], 'File uploaded successfully');
      expect(uploadResponse['fileId'], 'file-1');
      expect(uploadResponse['size'], 4);
      expect(fileReceived, true);
      // Wait a bit since onReceiveProgress is called after stream completes
      await Future.delayed(const Duration(milliseconds: 100));
      expect(bytesReceived, 4);

      controllerForUpload.dispose();
    });
  });
}
