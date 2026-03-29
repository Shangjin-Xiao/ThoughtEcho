import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/draft_service.dart';
import 'package:thoughtecho/services/mmkv_service.dart';

import '../../test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DraftService draftService;
  late MMKVService mmkvService;

  setUpAll(() async {
    await TestSetup.setupUnitTest();
    await MMKVService().init();
  });

  setUp(() async {
    draftService = DraftService();
    mmkvService = MMKVService();
    await mmkvService.clear();
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
  });
}
