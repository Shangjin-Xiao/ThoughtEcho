import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thoughtecho/services/app_preferences_service.dart';
import 'package:thoughtecho/services/draft_service.dart';
import 'package:thoughtecho/utils/mmkv_ffi_fix.dart';

import '../../test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DraftService draftService;
  late AppPreferencesService prefsService;

  setUpAll(() async {
    await TestHarness.initialize();
    await AppPreferencesService().init();
  });

  setUp(() async {
    draftService = DraftService();
    prefsService = AppPreferencesService();
    await draftService.resetForTesting();
    await prefsService.clear();
    await draftService.deleteAllDrafts();
  });

  tearDownAll(() async {
    await draftService.resetForTesting();
    await TestHarness.tearDown();
  });

  group('DraftService.getLatestDraft', () {
    test('ignores drafts without body text', () async {
      await draftService.saveDraft('metadata-only', {
        'plainText': '   ',
        'weather': 'sunny',
        'timestamp': '2026-03-29T10:00:00.000Z',
      });

      expect(await draftService.getLatestDraft(), isNull);
    });

    test('returns the newest draft that contains body text', () async {
      await draftService.saveDraft('metadata-only', {
        'plainText': '',
        'weather': 'sunny',
        'timestamp': '2026-03-29T10:00:00.000Z',
      });
      await draftService.saveDraft('body-draft', {
        'plainText': 'Meaningful content',
        'timestamp': '2026-03-29T09:00:00.000Z',
      });
      await draftService.saveDraft('newer-body-draft', {
        'plainText': 'Newer meaningful content',
        'timestamp': '2026-03-29T11:00:00.000Z',
      });

      final latestDraft = await draftService.getLatestDraft();

      expect(latestDraft, isNotNull);
      expect(latestDraft!['id'], 'newer-body-draft');
      expect(latestDraft['plainText'], 'Newer meaningful content');
    });

    test('handles non-string timestamps and non-string plainText gracefully',
        () async {
      await draftService.saveDraft('int-timestamp-draft', {
        'plainText': 'Content with int timestamp',
        'timestamp': 1711700000,
      });

      final draft = await draftService.getDraft('int-timestamp-draft');
      expect(draft, isNotNull);
      expect(draft!['plainText'], 'Content with int timestamp');

      final latest = await draftService.getLatestDraft();
      expect(latest, isNotNull);
      expect(latest!['id'], 'int-timestamp-draft');
    });

    test('hasDraft returns true for existing key and false for non-existing',
        () async {
      expect(await draftService.hasDraft('non-existent'), isFalse);
      await draftService.saveDraft('test-draft', {'plainText': 'hello'});
      expect(await draftService.hasDraft('test-draft'), isTrue);
    });
  });

  group('DraftService SQLite persistence & KV migration', () {
    test(
        'persists drafts in SQLite across service DB reset and supports delete',
        () async {
      await draftService.saveDraft('persist-1', {
        'plainText': 'Persisted draft text',
        'deltaContent': jsonEncode([
          {
            'insert': {'image': '/tmp/mock_image.png'}
          },
          {
            'insert': {'video': '/tmp/mock_video.mp4'}
          },
          {
            'insert': {
              'custom': {'audio': '/tmp/mock_audio.m4a'}
            }
          },
          {'insert': 'Persisted draft text\n'},
        ]),
        'timestamp': '2026-05-01T12:00:00.000Z',
      });

      // Drafts should NOT be written to KV storage anymore
      expect(prefsService.containsKey('draft_persist-1'), isFalse);

      // Reopen DB from disk
      await draftService.resetForTesting();

      final restored = await draftService.getDraft('persist-1');
      expect(restored, isNotNull);
      expect(restored!['plainText'], 'Persisted draft text');
      expect(await draftService.getAllDraftIds(), contains('persist-1'));

      final mediaPaths = await draftService.getAllMediaPathsInDrafts();
      expect(
        mediaPaths,
        containsAll([
          '/tmp/mock_image.png',
          '/tmp/mock_video.mp4',
          '/tmp/mock_audio.m4a',
        ]),
      );

      await draftService.deleteDraft('persist-1');
      expect(await draftService.hasDraft('persist-1'), isFalse);
      expect(await draftService.getDraft('persist-1'), isNull);
    });

    test('migrates legacy KV draft_* keys into drafts.db and removes old keys',
        () async {
      await draftService.resetForTesting();
      SharedPreferences.setMockInitialValues({
        kKvEngineMigratedKey: true,
        'draft_legacy_note_1': jsonEncode({
          'plainText': 'Legacy draft content',
          'timestamp': '2026-04-01T08:00:00.000Z',
        }),
        'draft_legacy_empty': jsonEncode({
          'plainText': '',
          'weather': 'cloudy',
          'timestamp': '2026-04-02T08:00:00.000Z',
        }),
        'unrelated_pref': 'keep_me',
      });
      prefsService.resetForTesting();
      await prefsService.init();

      final latest = await draftService.getLatestDraft();
      expect(latest, isNotNull);
      expect(latest!['id'], 'legacy_note_1');
      expect(latest['plainText'], 'Legacy draft content');

      final emptyDraft = await draftService.getDraft('legacy_empty');
      expect(emptyDraft, isNotNull);
      expect(emptyDraft!['weather'], 'cloudy');

      // Legacy KV keys must be cleaned up and migration flag set
      expect(prefsService.containsKey('draft_legacy_note_1'), isFalse);
      expect(prefsService.containsKey('draft_legacy_empty'), isFalse);
      expect(prefsService.getString('unrelated_pref'), 'keep_me');
      expect(prefsService.getBool(kDraftsSqliteMigratedKey), isTrue);

      // drafts.db must live under ApplicationSupport/drafts/drafts.db, not Documents
      final supportDir = await getApplicationSupportDirectory();
      final docsDir = await getApplicationDocumentsDirectory();
      expect(
        File(p.join(supportDir.path, 'drafts', 'drafts.db')).existsSync(),
        isTrue,
      );
      expect(File(p.join(docsDir.path, 'drafts.db')).existsSync(), isFalse);
    });

    test(
        'partial KV migration preserves unreadable or unparseable keys without setting migrated flag',
        () async {
      await draftService.resetForTesting();
      SharedPreferences.setMockInitialValues({
        kKvEngineMigratedKey: true,
        'draft_valid_1': jsonEncode({
          'plainText': 'Valid legacy draft',
          'timestamp': '2026-04-03T08:00:00.000Z',
        }),
        'draft_corrupt_json': '{not-valid-json',
        'draft_wrong_type': 42,
        'draft_': jsonEncode({'plainText': 'Empty normalized id'}),
      });
      prefsService.resetForTesting();
      await prefsService.init();

      final valid = await draftService.getDraft('valid_1');
      expect(valid, isNotNull);
      expect(valid!['plainText'], 'Valid legacy draft');

      // Valid key migrated & cleaned up; invalid/unreadable keys preserved; flag stays unset
      expect(prefsService.containsKey('draft_valid_1'), isFalse);
      expect(prefsService.containsKey('draft_corrupt_json'), isTrue);
      expect(prefsService.containsKey('draft_wrong_type'), isTrue);
      expect(prefsService.containsKey('draft_'), isTrue);
      expect(prefsService.getBool(kDraftsSqliteMigratedKey), isNot(isTrue));

      // Unreadable pending KV key must abort media scan instead of returning partial paths
      await expectLater(
        draftService.getAllMediaPathsInDrafts(),
        throwsStateError,
      );
    });
  });
}
