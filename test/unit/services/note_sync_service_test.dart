import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thoughtecho/models/merge_report.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/ai_analysis_database_service.dart';
import 'package:thoughtecho/services/backup_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/large_file_manager.dart' as lfm;
import 'package:thoughtecho/services/localsend/constants.dart';
import 'package:thoughtecho/services/localsend/localsend_send_provider.dart';
import 'package:thoughtecho/services/localsend/models/device.dart';
import 'package:thoughtecho/services/media_sync_manifest.dart';
import 'package:thoughtecho/services/note_sync_service.dart';
import 'package:thoughtecho/services/settings_service.dart';

class _FakeBackupService implements BackupService {
  @override
  Future<String> exportAllData({
    required bool includeMediaFiles,
    String? customPath,
    Function(int current, int total)? onProgress,
    lfm.CancelToken? cancelToken,
    MediaSyncManifest? receiverMediaManifest,
  }) async {
    return 'mock_backup_path.zip';
  }

  @override
  Future<MergeReport?> importData(
    String filePath, {
    bool clearExisting = true,
    bool merge = false,
    Function(int current, int total)? onProgress,
    lfm.CancelToken? cancelToken,
    String? sourceDevice,
  }) async {
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDatabaseService implements DatabaseService {
  @override
  Future<List<Quote>> getAllQuotes({
    bool excludeHiddenNotes = true,
    bool includeDeleted = false,
  }) async {
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettingsService implements SettingsService {
  bool skipConfirm = false;

  @override
  bool get syncSkipConfirm => skipConfirm;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAIAnalysisDatabaseService implements AIAnalysisDatabaseService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _waitForCondition(
  NoteSyncService service,
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  if (predicate()) return;
  final completer = Completer<void>();
  void listener() {
    if (predicate() && !completer.isCompleted) {
      completer.complete();
    }
  }

  service.addListener(listener);
  try {
    await completer.future.timeout(timeout);
  } finally {
    service.removeListener(listener);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NoteSyncService sender metadata', () {
    late NoteSyncService syncService;
    late _FakeSettingsService settingsService;
    HttpOverrides? originalHttpOverrides;

    setUp(() {
      originalHttpOverrides = HttpOverrides.current;
      // flutter_test 默认注入返回 400 的 mock HttpClient，解除以便走本地 loopback HTTP。
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({});
      settingsService = _FakeSettingsService();
      syncService = NoteSyncService(
        backupService: _FakeBackupService(),
        databaseService: _FakeDatabaseService(),
        settingsService: settingsService,
        aiAnalysisDbService: _FakeAIAnalysisDatabaseService(),
      );
    });

    tearDown(() async {
      await syncService.stopServer();
      syncService.dispose();
      HttpOverrides.global = originalHttpOverrides;
    });

    test('getters normalize values and clear on reject/cancel/stopServer',
        () async {
      expect(syncService.receiveSenderIp, isNull);
      expect(syncService.receiveSenderPort, isNull);
      expect(syncService.receiveSenderFingerprint, isNull);

      var notifications = 0;
      syncService.addListener(() => notifications++);

      syncService.debugSetReceiveSenderInfo(
        senderIp: ' 192.168.1.50 ',
        senderPort: 53320,
        senderFingerprint: ' sender-fp-abcdef ',
      );
      expect(syncService.receiveSenderIp, '192.168.1.50');
      expect(syncService.receiveSenderPort, 53320);
      expect(syncService.receiveSenderFingerprint, 'sender-fp-abcdef');
      expect(notifications, 1);

      // Whitespace-only strings and non-positive ports normalize to null.
      syncService.debugSetReceiveSenderInfo(
        senderIp: '   ',
        senderPort: 0,
        senderFingerprint: ' ',
      );
      expect(syncService.receiveSenderIp, isNull);
      expect(syncService.receiveSenderPort, isNull);
      expect(syncService.receiveSenderFingerprint, isNull);

      // rejectIncoming clears sender metadata.
      syncService.debugHandleReceiveSessionCreated('sid-reject', 128, 'Peer A');
      syncService.debugSetReceiveSenderInfo(
        senderIp: '192.168.1.50',
        senderPort: 53320,
        senderFingerprint: 'sender-fp-abcdef',
      );
      syncService.rejectIncoming();
      expect(syncService.receiveSenderIp, isNull);
      expect(syncService.receiveSenderPort, isNull);
      expect(syncService.receiveSenderFingerprint, isNull);
      expect(syncService.syncStatus, SyncStatus.failed);

      // cancelReceiving clears sender metadata.
      syncService.debugHandleReceiveSessionCreated('sid-cancel', 256, 'Peer B');
      syncService.debugSetReceiveSenderInfo(
        senderIp: '192.168.1.60',
        senderPort: 53321,
        senderFingerprint: 'sender-fp-123456',
      );
      syncService.cancelReceiving();
      expect(syncService.receiveSenderIp, isNull);
      expect(syncService.receiveSenderPort, isNull);
      expect(syncService.receiveSenderFingerprint, isNull);
      expect(syncService.syncStatus, SyncStatus.failed);

      // stopServer clears sender metadata.
      syncService.debugSetReceiveSenderInfo(
        senderIp: '192.168.1.70',
        senderPort: 53322,
        senderFingerprint: 'sender-fp-999999',
      );
      await syncService.stopServer();
      expect(syncService.receiveSenderIp, isNull);
      expect(syncService.receiveSenderPort, isNull);
      expect(syncService.receiveSenderFingerprint, isNull);
    });

    test(
      'startServer populates sender metadata on /api/thoughtecho/v1/sync-intent and clears on reject or remote cancel',
      () async {
        await syncService.startServer();
        final port = syncService.debugServerPort!;

        final client = HttpClient();
        addTearDown(() => client.close(force: true));

        // 1. Live sync-intent -> awaitingUserApproval -> rejectIncoming clears metadata
        final req1 = await client.postUrl(
          Uri.parse('http://127.0.0.1:$port/api/thoughtecho/v1/sync-intent'),
        );
        req1.headers.contentType = ContentType.json;
        req1.write(
          jsonEncode({
            'intentId': 'intent-live-1',
            'alias': 'Intent Sender',
            'fingerprint': 'intent-fp-abcdef',
            'port': 54444,
          }),
        );
        final respFuture1 = req1.close();

        await _waitForCondition(
          syncService,
          () => syncService.awaitingUserApproval,
        );
        expect(syncService.receiveSenderAlias, 'Intent Sender');
        expect(syncService.receiveSenderIp, '127.0.0.1');
        expect(syncService.receiveSenderPort, 54444);
        expect(syncService.receiveSenderFingerprint, 'intent-fp-abcdef');

        syncService.rejectIncoming();
        final resp1 = await respFuture1;
        final body1 = jsonDecode(await utf8.decoder.bind(resp1).join())
            as Map<String, dynamic>;
        expect(resp1.statusCode, HttpStatus.ok);
        expect(body1['approved'], isFalse);
        expect(syncService.awaitingUserApproval, isFalse);
        expect(syncService.receiveSenderIp, isNull);
        expect(syncService.receiveSenderPort, isNull);
        expect(syncService.receiveSenderFingerprint, isNull);

        // 2. Live sync-intent -> remote cancel clears metadata
        final req2 = await client.postUrl(
          Uri.parse('http://127.0.0.1:$port/api/thoughtecho/v1/sync-intent'),
        );
        req2.headers.contentType = ContentType.json;
        req2.write(
          jsonEncode({
            'intentId': 'intent-live-cancel',
            'alias': 'Cancelling Sender',
            'fingerprint': 'cancel-fp-112233',
            'port': 54445,
          }),
        );
        final respFuture2 = req2.close();

        await _waitForCondition(
          syncService,
          () => syncService.awaitingUserApproval,
        );
        expect(syncService.receiveSenderIp, '127.0.0.1');
        expect(syncService.receiveSenderPort, 54445);
        expect(syncService.receiveSenderFingerprint, 'cancel-fp-112233');

        final cancelReq = await client.postUrl(
          Uri.parse(
            'http://127.0.0.1:$port/api/thoughtecho/v1/sync-intent/cancel',
          ),
        );
        cancelReq.headers.contentType = ContentType.json;
        cancelReq.write(jsonEncode({'intentId': 'intent-live-cancel'}));
        final cancelResp = await cancelReq.close();
        await cancelResp.drain<void>();
        expect(cancelResp.statusCode, HttpStatus.ok);

        final resp2 = await respFuture2;
        final body2 = jsonDecode(await utf8.decoder.bind(resp2).join())
            as Map<String, dynamic>;
        expect(body2['approved'], isFalse);
        expect(syncService.awaitingUserApproval, isFalse);
        expect(syncService.receiveSenderIp, isNull);
        expect(syncService.receiveSenderPort, isNull);
        expect(syncService.receiveSenderFingerprint, isNull);
      },
    );

    test(
      'startServer populates sender metadata on /api/localsend/v2/prepare-upload',
      () async {
        await syncService.startServer();
        final port = syncService.debugServerPort!;

        final client = HttpClient();
        addTearDown(() => client.close(force: true));

        final request = await client.postUrl(
          Uri.parse('http://127.0.0.1:$port/api/localsend/v2/prepare-upload'),
        );
        request.headers.contentType = ContentType.json;
        request.write(
          jsonEncode({
            'info': {
              'alias': 'Prepare Sender',
              'fingerprint': 'prepare-fp-abcdef',
              'port': 55555,
            },
            'files': {
              'file-1': {
                'id': 'file-1',
                'fileName': 'backup.zip',
                'size': 1024,
                'fileType': 'application/zip',
              },
            },
          }),
        );
        final respFuture = request.close();

        await _waitForCondition(
          syncService,
          () => syncService.awaitingUserApproval,
        );
        expect(syncService.receiveSenderAlias, 'Prepare Sender');
        expect(syncService.receiveSenderIp, '127.0.0.1');
        expect(syncService.receiveSenderPort, 55555);
        expect(syncService.receiveSenderFingerprint, 'prepare-fp-abcdef');

        syncService.rejectIncoming();
        final resp = await respFuture;
        await resp.drain<void>();
        expect(resp.statusCode, isNot(HttpStatus.ok));
        expect(syncService.awaitingUserApproval, isFalse);
        expect(syncService.receiveSenderIp, isNull);
        expect(syncService.receiveSenderPort, isNull);
        expect(syncService.receiveSenderFingerprint, isNull);
      },
    );

    test(
      'createSyncPackage includes local server port in /api/thoughtecho/v1/sync-intent payload',
      () async {
        Map<String, dynamic>? capturedIntentBody;
        final peerServer =
            await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => peerServer.close(force: true));

        peerServer.listen((HttpRequest request) async {
          if (request.uri.path == '/api/localsend/v2/info') {
            request.response.statusCode = HttpStatus.ok;
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({'alias': 'Peer'}));
            await request.response.close();
            return;
          }
          if (request.uri.path == '/api/thoughtecho/v1/sync-intent') {
            final raw = await utf8.decoder.bind(request).join();
            capturedIntentBody = jsonDecode(raw) as Map<String, dynamic>;
            request.response.statusCode = HttpStatus.ok;
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({'approved': false}));
            await request.response.close();
            return;
          }
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        });

        await syncService.startServer();
        syncService.localSendProviderForTesting = LocalSendProvider();

        final targetDevice = Device(
          signalingId: null,
          ip: '127.0.0.1',
          version: '2.1',
          port: peerServer.port,
          https: false,
          fingerprint: 'peer-fingerprint',
          alias: 'Peer',
          deviceModel: 'Peer Model',
          deviceType: DeviceType.desktop,
          download: true,
          discoveryMethods: <DiscoveryMethod>{const MulticastDiscovery()},
        );

        await expectLater(
          () => syncService.createSyncPackage(targetDevice),
          throwsException,
        );

        expect(capturedIntentBody, isNotNull);
        expect(
          capturedIntentBody!['port'],
          syncService.debugServerPort ?? defaultPort,
        );
      },
    );
  });
}
