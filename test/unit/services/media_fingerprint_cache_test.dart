import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thoughtecho/services/media_fingerprint_cache.dart';
import 'package:thoughtecho/services/unified_log_service.dart';
import 'package:thoughtecho/utils/app_logger.dart';

class _MockPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String docsPath;

  _MockPathProvider(this.docsPath);

  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

class _RecordingLogService implements UnifiedLogService {
  final List<
      ({
        UnifiedLogLevel level,
        String message,
        String? source,
        Object? error,
        StackTrace? stackTrace,
      })> records = [];

  @override
  void verbose(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      log(
        UnifiedLogLevel.verbose,
        message,
        source: source,
        error: error,
        stackTrace: stackTrace,
      );

  @override
  void debug(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      log(
        UnifiedLogLevel.debug,
        message,
        source: source,
        error: error,
        stackTrace: stackTrace,
      );

  @override
  void info(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      log(
        UnifiedLogLevel.info,
        message,
        source: source,
        error: error,
        stackTrace: stackTrace,
      );

  @override
  void warning(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(
      UnifiedLogLevel.warning,
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  void error(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      log(
        UnifiedLogLevel.error,
        message,
        source: source,
        error: error,
        stackTrace: stackTrace,
      );

  @override
  void log(
    UnifiedLogLevel level,
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    records.add((
      level: level,
      message: message,
      source: source,
      error: error,
      stackTrace: stackTrace,
    ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('media_fp_cache_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<File> writeMediaFile(
    String relativePath,
    List<int> bytes, {
    DateTime? modifiedAt,
  }) async {
    final file = File(p.join(tempDir.path, 'media', relativePath));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    if (modifiedAt != null) {
      await file.setLastModified(modifiedAt);
    }
    return file;
  }

  group('MediaFingerprintEntry', () {
    final sampleSha256 = sha256.convert(utf8.encode('sample-bytes')).toString();
    final sampleMd5 = md5.convert(utf8.encode('sample-bytes')).toString();
    final syncedSha256 = sha256.convert(utf8.encode('prior-bytes')).toString();

    test('serializes toJson and deserializes fromJson normalizing hex', () {
      final jsonMap = <String, dynamic>{
        'fileSize': 123,
        'lastModifiedEpochMs': 1700000000123,
        'sha256': sampleSha256.toUpperCase(),
        'md5': sampleMd5.toUpperCase(),
        'syncedSha256': syncedSha256.toUpperCase(),
        'syncedRemoteEtag': 'etag-v1',
      };

      final parsed = MediaFingerprintEntry.fromJson(jsonMap);
      expect(parsed.fileSize, 123);
      expect(parsed.lastModifiedEpochMs, 1700000000123);
      expect(parsed.sha256, sampleSha256);
      expect(parsed.md5, sampleMd5);
      expect(parsed.syncedSha256, syncedSha256);
      expect(parsed.syncedRemoteEtag, 'etag-v1');

      final roundTripped = MediaFingerprintEntry.fromJson(parsed.toJson());
      expect(roundTripped, equals(parsed));
    });

    test('copyWith updates fields and clears syncedRemoteEtag on demand', () {
      final base = MediaFingerprintEntry(
        fileSize: 42,
        lastModifiedEpochMs: 1000,
        sha256: sampleSha256,
        md5: sampleMd5,
        syncedSha256: sampleSha256,
        syncedRemoteEtag: 'etag-old',
      );

      final updated = base.copyWith(fileSize: 84, syncedRemoteEtag: 'etag-new');
      expect(updated.fileSize, 84);
      expect(updated.syncedRemoteEtag, 'etag-new');
      expect(updated.md5, sampleMd5);

      final cleared = updated.copyWith(clearSyncedRemoteEtag: true);
      expect(cleared.syncedRemoteEtag, isNull);
      expect(cleared.syncedSha256, sampleSha256);
    });

    test('fromJson throws FormatException for invalid fields', () {
      Map<String, dynamic> validBase() => <String, dynamic>{
            'fileSize': 10,
            'lastModifiedEpochMs': 5000,
            'sha256': sampleSha256,
          };

      expect(
        () => MediaFingerprintEntry.fromJson({...validBase(), 'fileSize': -1}),
        throwsFormatException,
      );
      expect(
        () =>
            MediaFingerprintEntry.fromJson({...validBase(), 'fileSize': '10'}),
        throwsFormatException,
      );
      expect(
        () => MediaFingerprintEntry.fromJson({
          ...validBase(),
          'lastModifiedEpochMs': 5000.5,
        }),
        throwsFormatException,
      );
      expect(
        () => MediaFingerprintEntry.fromJson({
          ...validBase(),
          'sha256': 'not-a-sha256',
        }),
        throwsFormatException,
      );
      expect(
        () => MediaFingerprintEntry.fromJson({
          ...validBase(),
          'sha256': 'z' * 64,
        }),
        throwsFormatException,
      );
      expect(
        () => MediaFingerprintEntry.fromJson({...validBase(), 'md5': 'short'}),
        throwsFormatException,
      );
      expect(
        () => MediaFingerprintEntry.fromJson({...validBase(), 'md5': 'g' * 32}),
        throwsFormatException,
      );
      expect(
        () => MediaFingerprintEntry.fromJson({
          ...validBase(),
          'syncedSha256': '',
        }),
        throwsFormatException,
      );
      expect(
        () => MediaFingerprintEntry.fromJson({
          ...validBase(),
          'syncedRemoteEtag': 999,
        }),
        throwsFormatException,
      );
    });
  });

  group('ETag helpers', () {
    test('isWeakEtag detects weak prefixes case-insensitively', () {
      expect(MediaFingerprintCache.isWeakEtag(null), isFalse);
      expect(MediaFingerprintCache.isWeakEtag(''), isFalse);
      expect(MediaFingerprintCache.isWeakEtag('"strong-etag"'), isFalse);
      expect(MediaFingerprintCache.isWeakEtag('"W/quoted"'), isFalse);
      expect(MediaFingerprintCache.isWeakEtag('W/"weak-etag"'), isTrue);
      expect(MediaFingerprintCache.isWeakEtag('w/"weak-etag"'), isTrue);
      expect(MediaFingerprintCache.isWeakEtag('  W/"padded"  '), isTrue);
    });

    test('cleanStrongEtag strips quotes and rejects weak or empty tags', () {
      expect(MediaFingerprintCache.cleanStrongEtag(null), isNull);
      expect(MediaFingerprintCache.cleanStrongEtag(''), isNull);
      expect(MediaFingerprintCache.cleanStrongEtag('   '), isNull);
      expect(MediaFingerprintCache.cleanStrongEtag('""'), isNull);
      expect(MediaFingerprintCache.cleanStrongEtag('"   "'), isNull);
      expect(MediaFingerprintCache.cleanStrongEtag('W/"abc"'), isNull);
      expect(MediaFingerprintCache.cleanStrongEtag('w/"abc"'), isNull);
      expect(MediaFingerprintCache.cleanStrongEtag('  "abc123"  '), 'abc123');
      expect(MediaFingerprintCache.cleanStrongEtag('plain-etag'), 'plain-etag');
    });
  });

  group('MediaFingerprintCache hashing and invalidation', () {
    test(
      'cache miss computes SHA-256 once, then cache hit computes zero',
      () async {
        final cache = MediaFingerprintCache(directory: tempDir);
        final bytes = utf8.encode('synthetic-media-payload-01');
        final mtime = DateTime.utc(2026, 3, 1, 12, 0, 0);
        final file = await writeMediaFile(
          'images/sample_01.jpg',
          bytes,
          modifiedAt: mtime,
        );

        final first = await cache.getOrCompute('images/sample_01.jpg', file);
        expect(cache.hashComputeCount, 1);
        expect(cache.sha256ComputeCount, 1);
        expect(cache.md5ComputeCount, 0);
        expect(cache.isDirty, isTrue);
        expect(cache.length, 1);
        expect(first.fileSize, bytes.length);
        expect(first.lastModifiedEpochMs, mtime.millisecondsSinceEpoch);
        expect(first.sha256, sha256.convert(bytes).toString());
        expect(first.md5, isNull);

        final second = await cache.getOrCompute('images\\sample_01.jpg', file);
        expect(cache.hashComputeCount, 1);
        expect(cache.sha256ComputeCount, 1);
        expect(cache.md5ComputeCount, 0);
        expect(second, equals(first));
      },
    );

    test(
      'computes MD5 lazily on cache hit without re-computing SHA-256',
      () async {
        final cache = MediaFingerprintCache(directory: tempDir);
        final bytes = utf8.encode('lazy-md5-payload');
        final mtime = DateTime.utc(2026, 3, 2, 8, 30, 0);
        final file = await writeMediaFile(
          'audios/clip_01.m4a',
          bytes,
          modifiedAt: mtime,
        );

        final initial = await cache.getOrCompute('audios/clip_01.m4a', file);
        expect(initial.md5, isNull);
        expect(cache.sha256ComputeCount, 1);
        expect(cache.md5ComputeCount, 0);

        await cache.save();
        expect(cache.isDirty, isFalse);

        final withMd5 = await cache.getOrCompute(
          'audios/clip_01.m4a',
          file,
          requireMd5: true,
        );
        expect(cache.sha256ComputeCount, 1);
        expect(cache.md5ComputeCount, 1);
        expect(cache.hashComputeCount, 2);
        expect(cache.isDirty, isTrue);
        expect(withMd5.md5, md5.convert(bytes).toString());

        final cachedAgain = await cache.getOrCompute(
          'audios/clip_01.m4a',
          file,
          requireMd5: true,
        );
        expect(cache.hashComputeCount, 2);
        expect(cachedAgain, equals(withMd5));
      },
    );

    test(
        'invalidates on size or same-size mtime change while preserving sync baseline and dropping stale md5',
        () async {
      final cache = MediaFingerprintCache(directory: tempDir);
      final initialBytes = utf8.encode('1234567890');
      final t1 = DateTime.utc(2026, 4, 1, 10, 0, 0);
      final file = await writeMediaFile(
        'images/sample_02.png',
        initialBytes,
        modifiedAt: t1,
      );

      final synced = await cache.markSynced(
        'images/sample_02.png',
        file,
        remoteEtag: '"etag-initial"',
        knownSha256: sha256.convert(initialBytes).toString(),
        knownMd5: md5.convert(initialBytes).toString(),
        knownSize: initialBytes.length,
        knownLastModified: t1,
      );
      expect(cache.hashComputeCount, 0);
      expect(synced.syncedSha256, sha256.convert(initialBytes).toString());
      expect(synced.syncedRemoteEtag, 'etag-initial');
      expect(synced.md5, md5.convert(initialBytes).toString());

      // Same-size edit with newer mtime and different content
      final sameSizeDifferentBytes = utf8.encode('abcdefghij');
      expect(sameSizeDifferentBytes.length, initialBytes.length);
      final t2 = t1.add(const Duration(seconds: 5));
      await file.writeAsBytes(sameSizeDifferentBytes, flush: true);
      await file.setLastModified(t2);

      final afterMtimeChange = await cache.getOrCompute(
        'images/sample_02.png',
        file,
        requireMd5: false,
      );
      expect(cache.sha256ComputeCount, 1);
      expect(cache.md5ComputeCount, 0);
      expect(
        afterMtimeChange.sha256,
        sha256.convert(sameSizeDifferentBytes).toString(),
      );
      expect(afterMtimeChange.md5, isNull);
      expect(
        afterMtimeChange.syncedSha256,
        sha256.convert(initialBytes).toString(),
      );
      expect(afterMtimeChange.syncedRemoteEtag, 'etag-initial');

      // Size change also invalidates and computes MD5 when requested
      final largerBytes = utf8.encode('larger-content-payload');
      final t3 = t2.add(const Duration(seconds: 5));
      await file.writeAsBytes(largerBytes, flush: true);
      await file.setLastModified(t3);

      final afterSizeChange = await cache.getOrCompute(
        'images/sample_02.png',
        file,
        requireMd5: true,
      );
      expect(cache.sha256ComputeCount, 2);
      expect(cache.md5ComputeCount, 1);
      expect(cache.hashComputeCount, 3);
      expect(afterSizeChange.fileSize, largerBytes.length);
      expect(afterSizeChange.sha256, sha256.convert(largerBytes).toString());
      expect(afterSizeChange.md5, md5.convert(largerBytes).toString());
      expect(
        afterSizeChange.syncedSha256,
        sha256.convert(initialBytes).toString(),
      );
    });

    test(
      'markSynced clears syncedRemoteEtag when server returns weak ETag',
      () async {
        final cache = MediaFingerprintCache(directory: tempDir);
        final bytes = utf8.encode('weak-etag-test');
        final file = await writeMediaFile('videos/clip_01.mp4', bytes);

        final first = await cache.markSynced(
          'videos\\clip_01.mp4',
          file,
          remoteEtag: '"strong-1"',
        );
        expect(first.syncedRemoteEtag, 'strong-1');
        expect(cache.hashComputeCount, 1);

        final second = await cache.markSynced(
          'videos/clip_01.mp4',
          file,
          remoteEtag: 'W/"weak-2"',
        );
        expect(second.syncedRemoteEtag, isNull);
        expect(second.syncedSha256, first.sha256);
        expect(cache.hashComputeCount, 1);
      },
    );

    test(
        'getOrCompute never promotes unsynced sha256 into syncedSha256 on mtime change',
        () async {
      final cache = MediaFingerprintCache(directory: tempDir);
      final t1 = DateTime.utc(2026, 5, 1, 10, 0, 0);
      final t2 = t1.add(const Duration(seconds: 5));
      final payload = utf8.encode('unsynced-payload-bytes');
      final file = await writeMediaFile(
        'images/unsynced_retry.png',
        payload,
        modifiedAt: t1,
      );

      final first = await cache.getOrCompute('images/unsynced_retry.png', file);
      expect(first.syncedSha256, isNull);

      // Simulate failed upload followed by mtime-only touch of same bytes
      await file.setLastModified(t2);
      final second = await cache.getOrCompute(
        'images/unsynced_retry.png',
        file,
      );
      expect(second.sha256, first.sha256);
      expect(second.syncedSha256, isNull);
      expect(second.syncedRemoteEtag, isNull);
    });

    test(
        'buildRemoteScope normalizes URLs and load clears sync baselines on scope change',
        () async {
      final scopeA1 = MediaFingerprintCache.buildRemoteScope(
        serverUrl: 'https://DAV.Example.com:443/dav/',
        username: 'alice',
      );
      final scopeA2 = MediaFingerprintCache.buildRemoteScope(
        serverUrl: 'https://dav.example.com/dav///',
        username: ' alice ',
      );
      final scopeB = MediaFingerprintCache.buildRemoteScope(
        serverUrl: 'https://dav.example.com/dav/',
        username: 'bob',
      );
      final scopeC = MediaFingerprintCache.buildRemoteScope(
        serverUrl: 'https://other.example.com/dav/',
        username: 'alice',
      );
      final scopeD = MediaFingerprintCache.buildRemoteScope(
        serverUrl: 'https://dav.example.com/dav/?ns=2',
        username: 'alice',
      );

      expect(scopeA1, isNotNull);
      expect(scopeA1, scopeA2);
      expect(scopeA1, isNot(scopeB));
      expect(scopeA1, isNot(scopeC));
      expect(scopeA1, isNot(scopeD));

      final mtime = DateTime.utc(2026, 5, 2, 12, 0, 0);
      final file = await writeMediaFile(
        'images/scoped.jpg',
        utf8.encode('scoped-bytes'),
        modifiedAt: mtime,
      );

      final cacheA = MediaFingerprintCache(
        directory: tempDir,
        remoteScope: scopeA1,
      );
      await cacheA.load();
      await cacheA.markSynced(
        'images/scoped.jpg',
        file,
        remoteEtag: '"server-a-etag"',
      );
      await cacheA.save();

      // Loading with same normalized scope retains synced baseline
      final reloadedA = MediaFingerprintCache(
        directory: tempDir,
        remoteScope: scopeA2,
      );
      await reloadedA.load();
      expect(reloadedA.isDirty, isFalse);
      expect(
        reloadedA.peek('images/scoped.jpg')?.syncedRemoteEtag,
        'server-a-etag',
      );
      expect(reloadedA.peek('images/scoped.jpg')?.syncedSha256, isNotNull);

      // Switching to scopeB clears sync baselines while preserving local hash
      final cacheB = MediaFingerprintCache(
        directory: tempDir,
        remoteScope: scopeB,
      );
      await cacheB.load();
      expect(cacheB.isDirty, isTrue);
      final entryB = cacheB.peek('images/scoped.jpg');
      expect(entryB, isNotNull);
      expect(entryB!.sha256, isNotEmpty);
      expect(entryB.syncedSha256, isNull);
      expect(entryB.syncedRemoteEtag, isNull);
    });
  });

  group('MediaFingerprintCache persistence and recovery', () {
    test(
      'save writes atomically with no leftover .tmp and load restores hits',
      () async {
        final nestedDir = Directory(
          p.join(tempDir.path, 'nested', 'cache_dir'),
        );
        final cache = MediaFingerprintCache(directory: nestedDir);

        // No-op when clean
        await cache.save();
        final targetFile = File(
          p.join(nestedDir.path, MediaFingerprintCache.defaultCacheFileName),
        );
        expect(await targetFile.exists(), isFalse);

        final bytes = utf8.encode('persisted-media-bytes');
        final mtime = DateTime.utc(2026, 5, 1, 9, 0, 0);
        final mediaFile = await writeMediaFile(
          'images/persisted.jpg',
          bytes,
          modifiedAt: mtime,
        );

        final computed = await cache.getOrCompute(
          'images/persisted.jpg',
          mediaFile,
        );
        await cache.markSynced(
          'images/persisted.jpg',
          mediaFile,
          remoteEtag: '"etag-saved"',
        );
        expect(cache.isDirty, isTrue);

        await cache.save();
        expect(cache.isDirty, isFalse);
        expect(await targetFile.exists(), isTrue);
        expect(await File('${targetFile.path}.tmp').exists(), isFalse);

        final decoded =
            jsonDecode(await targetFile.readAsString()) as Map<String, dynamic>;
        expect(decoded['version'], 1);
        expect(decoded['entries'], isA<Map<String, dynamic>>());

        final reloaded = MediaFingerprintCache(directory: nestedDir);
        await reloaded.load();
        expect(reloaded.isDirty, isFalse);
        expect(reloaded.length, 1);

        final hit = await reloaded.getOrCompute(
          'images/persisted.jpg',
          mediaFile,
        );
        expect(reloaded.hashComputeCount, 0);
        expect(hit.sha256, computed.sha256);
        expect(hit.syncedSha256, computed.sha256);
        expect(hit.syncedRemoteEtag, 'etag-saved');
      },
    );

    test('save(force: true) writes even when cache is clean', () async {
      final cacheFile = File(p.join(tempDir.path, 'forced_cache.json'));
      final cache = MediaFingerprintCache(cacheFile: cacheFile);
      await cache.load();
      expect(cache.isDirty, isFalse);
      expect(await cacheFile.exists(), isFalse);

      await cache.save(force: true);
      expect(await cacheFile.exists(), isTrue);
      expect(cache.isDirty, isFalse);
    });

    test(
      'load resolves default cache file via getApplicationDocumentsDirectory',
      () async {
        final originalProvider = PathProviderPlatform.instance;
        final docsDir = Directory(p.join(tempDir.path, 'app_docs'));
        await docsDir.create(recursive: true);
        PathProviderPlatform.instance = _MockPathProvider(docsDir.path);
        addTearDown(() => PathProviderPlatform.instance = originalProvider);

        final cache = MediaFingerprintCache();
        await cache.load();
        cache.putEntry(
          'images/default_dir.jpg',
          MediaFingerprintEntry(
            fileSize: 12,
            lastModifiedEpochMs: 123456,
            sha256: 'a' * 64,
          ),
        );
        await cache.save();

        final expectedFile = File(
          p.join(docsDir.path, MediaFingerprintCache.defaultCacheFileName),
        );
        expect(await expectedFile.exists(), isTrue);
      },
    );

    test('load tolerates flat map JSON without entries wrapper', () async {
      final cacheFile = File(p.join(tempDir.path, 'flat_cache.json'));
      await cacheFile.writeAsString(
        jsonEncode({
          'images\\flat.jpg': {
            'fileSize': 77,
            'lastModifiedEpochMs': 9000,
            'sha256': 'B' * 64,
          },
        }),
      );

      final cache = MediaFingerprintCache(cacheFile: cacheFile);
      await cache.load();
      expect(cache.isDirty, isFalse);
      expect(cache.length, 1);
      final entry = cache.peek('images/flat.jpg');
      expect(entry, isNotNull);
      expect(entry!.sha256, 'b' * 64);
    });

    test(
      'recovers from corrupted JSON, logs warning, and heals on next save',
      () async {
        final logService = _RecordingLogService();
        AppLogger.serviceForTesting = logService;
        addTearDown(AppLogger.initialize);

        final cacheFile = File(p.join(tempDir.path, 'corrupted.json'));
        await cacheFile.writeAsString('{broken-json');

        final cache = MediaFingerprintCache(cacheFile: cacheFile);
        cache.putEntry(
          'images/stale.jpg',
          MediaFingerprintEntry(
            fileSize: 1,
            lastModifiedEpochMs: 1,
            sha256: 'c' * 64,
          ),
        );

        await cache.load();
        expect(cache.length, 0);
        expect(cache.isDirty, isTrue);
        expect(
          logService.records.any(
            (r) =>
                r.level == UnifiedLogLevel.warning &&
                r.source == 'MediaFingerprintCache' &&
                r.message.contains('媒体指纹缓存损坏，已重置缓存'),
          ),
          isTrue,
        );

        await cache.save();
        expect(cache.isDirty, isFalse);

        final healed = MediaFingerprintCache(cacheFile: cacheFile);
        await healed.load();
        expect(healed.isDirty, isFalse);
        expect(healed.length, 0);
      },
    );

    test(
      'resets on invalid top-level structure (non-map or bad version)',
      () async {
        final logService = _RecordingLogService();
        AppLogger.serviceForTesting = logService;
        addTearDown(AppLogger.initialize);

        final cacheFile = File(p.join(tempDir.path, 'bad_top_level.json'));
        await cacheFile.writeAsString('[1, 2, 3]');

        final cache = MediaFingerprintCache(cacheFile: cacheFile);
        await cache.load();
        expect(cache.length, 0);
        expect(cache.isDirty, isTrue);

        await cacheFile.writeAsString(
          jsonEncode(<String, dynamic>{
            'version': 99,
            'entries': <String, dynamic>{},
          }),
        );
        await cache.load();
        expect(cache.length, 0);
        expect(cache.isDirty, isTrue);
        final warningLogs = logService.records
            .where(
              (r) =>
                  r.level == UnifiedLogLevel.warning &&
                  r.source == 'MediaFingerprintCache',
            )
            .toList();
        expect(warningLogs, hasLength(2));
        expect(warningLogs[0].message, contains('媒体指纹缓存损坏，已重置缓存'));
        expect(warningLogs[1].message, contains('媒体指纹缓存损坏，已重置缓存'));
      },
    );

    test(
      'skips individual malformed entries while keeping valid entries',
      () async {
        final logService = _RecordingLogService();
        AppLogger.serviceForTesting = logService;
        addTearDown(AppLogger.initialize);

        final cacheFile = File(p.join(tempDir.path, 'partial.json'));
        await cacheFile.writeAsString(
          jsonEncode({
            'version': 1,
            'entries': {
              'images/valid.jpg': {
                'fileSize': 128,
                'lastModifiedEpochMs': 1700000000000,
                'sha256': 'd' * 64,
              },
              'images/invalid_hash.jpg': {
                'fileSize': 128,
                'lastModifiedEpochMs': 1700000000000,
                'sha256': 'invalid',
              },
              'images/invalid_type.jpg': 'not-a-map',
            },
          }),
        );

        final cache = MediaFingerprintCache(cacheFile: cacheFile);
        await cache.load();

        expect(cache.length, 1);
        expect(cache.peek('images/valid.jpg'), isNotNull);
        expect(cache.peek('images/invalid_hash.jpg'), isNull);
        expect(cache.isDirty, isTrue);
        expect(
          logService.records
              .where(
                (r) =>
                    r.level == UnifiedLogLevel.warning &&
                    r.source == 'MediaFingerprintCache',
              )
              .length,
          2,
        );
      },
    );
  });

  group('MediaFingerprintCache pruneMissingFiles', () {
    test(
      'normalizes keys, removes missing files, and marks dirty only on removal',
      () async {
        final cache = MediaFingerprintCache(directory: tempDir);
        final entry = MediaFingerprintEntry(
          fileSize: 10,
          lastModifiedEpochMs: 1000,
          sha256: 'e' * 64,
        );
        cache.putEntry('images/keep.jpg', entry);
        cache.putEntry('audios\\remove_me.m4a', entry);
        await cache.save();
        expect(cache.isDirty, isFalse);

        // Nothing removed -> stays clean
        final zeroRemoved = cache.pruneMissingFiles([
          'images\\keep.jpg',
          'audios/remove_me.m4a',
        ]);
        expect(zeroRemoved, 0);
        expect(cache.isDirty, isFalse);
        expect(cache.length, 2);

        // Remove one missing entry
        final removedCount = cache.pruneMissingFiles(['images\\keep.jpg']);
        expect(removedCount, 1);
        expect(cache.isDirty, isTrue);
        expect(cache.length, 1);
        expect(cache.peek('images/keep.jpg'), isNotNull);
        expect(cache.peek('audios/remove_me.m4a'), isNull);
      },
    );
  });
}
