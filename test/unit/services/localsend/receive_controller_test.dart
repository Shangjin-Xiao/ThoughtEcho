import "dart:typed_data";
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/localsend/models/session_status.dart';
import 'package:thoughtecho/services/localsend/receive_controller.dart';

import '../../../test_harness.dart';

class MockHttpRequest extends Fake implements HttpRequest {
  final Stream<Uint8List> body;
  final ContentType? contentType;

  MockHttpRequest({Stream<Uint8List>? body, this.contentType})
      : body = body ??
            Stream<Uint8List>.fromIterable([
              Uint8List.fromList([1, 2, 3, 4]),
            ]);

  @override
  HttpHeaders get headers => MockHttpHeaders(contentType);

  @override
  Stream<R> cast<R>() => body.cast<R>();

  @override
  StreamSubscription<Uint8List> listen(void Function(Uint8List event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return body.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}

class MockHttpHeaders extends Fake implements HttpHeaders {
  MockHttpHeaders(this.contentType);

  @override
  final ContentType? contentType;
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

    test('handlePrepareUpload rejects without an approval handler', () async {
      await expectLater(
        controller.handlePrepareUpload({
          'info': {'alias': 'Test Sender'},
          'files': {
            'file-1': {
              'id': 'file-1',
              'fileName': 'package.zip',
              'size': 4,
              'fileType': 'application/zip',
            },
          },
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('接收端已拒绝'),
          ),
        ),
      );
      expect(controller.sessions.values.single.fileTokens, isNull);
      expect(
        controller.sessions.values.single.status,
        SessionStatus.canceledByReceiver,
      );
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
        onApprovalNeeded: (_, __, ___) async => true,
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
        onApprovalNeeded: (_, __, ___) async => true,
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
        onApprovalNeeded: (_, __, ___) async => true,
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

    test('handlePrepareUpload handles onApprovalNeeded exception gracefully',
        () async {
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

      final controllerError = ReceiveController(
        onApprovalNeeded: (sessionId, totalBytes, senderAlias) async {
          throw StateError('Simulated approval error');
        },
      );

      expect(
        () => controllerError.handlePrepareUpload(requestData),
        throwsA(isA<Exception>()
            .having((e) => e.toString(), 'message', contains('接收端已拒绝'))),
      );

      controllerError.dispose();
    });
  });

  group('Receive cancellation', () {
    setUp(TestHarness.initialize);

    test('approval cannot revive a canceled preparation', () async {
      final approval = Completer<bool>();
      final approvalStarted = Completer<String>();
      final controller = ReceiveController(
        onApprovalNeeded: (id, _, __) {
          approvalStarted.complete(id);
          return approval.future;
        },
      );
      addTearDown(controller.dispose);

      final preparation = controller.handlePrepareUpload({
        'info': {'alias': 'Test Sender'},
        'files': {
          'file-1': {
            'id': 'file-1',
            'fileName': 'package.zip',
            'size': 4,
            'fileType': 'application/zip',
          },
        },
      });
      final sessionId = await approvalStarted.future;
      controller.cancelSession(sessionId);
      final rejected = expectLater(preparation, throwsException);
      approval.complete(true);
      await rejected;

      expect(controller.getSession(sessionId)!.status,
          SessionStatus.canceledByReceiver);
      expect(controller.getSession(sessionId)!.fileTokens, isNull);
    });

    for (final multipart in [false, true]) {
      for (final cancelAfterChunk in [null, 0, 1, 2]) {
        final encoding = multipart ? 'multipart' : 'raw';
        final scenario = switch (cancelAfterChunk) {
          null => 'completes with approval',
          0 => 'rejects a canceled session',
          1 => 'stops within the file after cancellation',
          _ => 'does not dispatch when canceled after the last data chunk',
        };
        test('$encoding upload $scenario', () async {
          const chunkSize = 128 * 1024;
          const totalSize = 2 * chunkSize;
          final fileName =
              'cancel_${DateTime.now().microsecondsSinceEpoch}.zip';
          final importedPaths = <String>[];
          final progress = <int>[];
          late String sessionId;
          late ReceiveController controller;
          controller = ReceiveController(
            onApprovalNeeded: (_, __, ___) async => true,
            onFileReceived: importedPaths.add,
            onReceiveProgress: (received, _) {
              progress.add(received);
              if (cancelAfterChunk != null &&
                  received == cancelAfterChunk * chunkSize) {
                controller.cancelSession(sessionId);
              }
            },
          );
          addTearDown(controller.dispose);

          Future<List<FileSystemEntity>> receivedFiles() async =>
              Directory.systemTemp
                  .list()
                  .where((entry) => entry.path.endsWith(fileName))
                  .toList();
          addTearDown(() async {
            for (final file in await receivedFiles()) {
              await file.delete();
            }
          });
          final preparation = await controller.handlePrepareUpload({
            'info': {'alias': 'Test Sender'},
            'files': {
              'file-1': {
                'id': 'file-1',
                'fileName': fileName,
                'size': totalSize,
                'fileType': 'application/zip',
              },
            },
          });
          sessionId = preparation['sessionId'] as String;
          if (cancelAfterChunk == 0) controller.cancelSession(sessionId);

          Stream<Uint8List> body() async* {
            if (multipart) {
              yield Uint8List.fromList(
                '--test-boundary\r\n'
                        'Content-Disposition: form-data; name="file"; filename="package.zip"\r\n'
                        'Content-Type: application/zip\r\n\r\n'
                    .codeUnits,
              );
            }
            yield Uint8List(chunkSize);
            yield Uint8List(chunkSize);
            if (multipart) {
              yield Uint8List.fromList('\r\n--test-boundary--\r\n'.codeUnits);
            }
          }

          final upload = controller.handleFileUpload(
            sessionId,
            'file-1',
            preparation['files']['file-1'] as String,
            MockHttpRequest(
              body: body(),
              contentType: multipart
                  ? ContentType('multipart', 'form-data',
                      parameters: {'boundary': 'test-boundary'})
                  : null,
            ),
          );

          if (cancelAfterChunk == null) {
            final response = await upload;
            expect(response['size'], totalSize);
            expect(importedPaths, hasLength(1));
            expect(await File(importedPaths.single).length(), totalSize);
            expect(progress.last, totalSize);
          } else {
            await expectLater(
              upload,
              throwsA(isA<Exception>()
                  .having((e) => e.toString(), 'message', contains('接收已取消'))),
            );
            expect(importedPaths, isEmpty);
            expect(progress, [
              for (var i = 1; i <= cancelAfterChunk; i++) i * chunkSize,
            ]);
            expect(controller.getSession(sessionId)!.status,
                SessionStatus.canceledByReceiver);
            expect(await receivedFiles(), isEmpty);
          }
        });
      }
    }
  });
}
