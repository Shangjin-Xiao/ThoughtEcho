import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/mmkv_service.dart';
import 'package:thoughtecho/services/smart_push_analytics.dart';

import '../../test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SmartPushAnalytics analytics;
  late MMKVService mmkvService;

  setUpAll(() async {
    await TestSetup.setupUnitTest();
    await MMKVService().init();
  });

  setUp(() async {
    mmkvService = MMKVService();
    await mmkvService.clear();
    analytics = SmartPushAnalytics(mmkvService: mmkvService);
  });

  group('SmartPushAnalytics.recordAppOpen', () {
    test(
      'appends new record representing current time to MMKV storage',
      () async {
        await analytics.recordAppOpen();

        final recordsStr = mmkvService.getString('smart_push_app_open_times');
        expect(recordsStr, isNotNull);
        expect(recordsStr, isNotEmpty);

        final records = recordsStr!
            .split(',')
            .where((s) => s.isNotEmpty)
            .toList();
        expect(records.length, 1);

        // Should be parseable as DateTime
        final parsedDate = DateTime.tryParse(records.first);
        expect(parsedDate, isNotNull);
      },
    );

    test('maintains max limit of records by removing oldest', () async {
      final maxRecords = SmartPushAnalytics.maxAppOpenRecords;

      // Create max number of fake records
      final fakeRecords = List.generate(
        maxRecords,
        (i) => DateTime(2023, 1, 1).add(Duration(days: i)).toIso8601String(),
      );
      await mmkvService.setString(
        'smart_push_app_open_times',
        fakeRecords.join(','),
      );

      await analytics.recordAppOpen();

      final updatedRecordsStr = mmkvService.getString(
        'smart_push_app_open_times',
      );
      final updatedRecords = updatedRecordsStr!
          .split(',')
          .where((s) => s.isNotEmpty)
          .toList();

      expect(updatedRecords.length, maxRecords);
      // The oldest one should be removed (the one from index 0 of fakeRecords)
      expect(updatedRecords.first, fakeRecords[1]);

      // The newest one should be near current time
      final parsedLastDate = DateTime.tryParse(updatedRecords.last);
      expect(parsedLastDate, isNotNull);
      expect(parsedLastDate!.isAfter(DateTime.parse(fakeRecords.last)), isTrue);
    });

    test('handles corrupted data gracefully by appending anyway', () async {
      // Set corrupted data
      await mmkvService.setString(
        'smart_push_app_open_times',
        'corrupted_data_without_datetime',
      );

      await analytics.recordAppOpen();

      final updatedRecordsStr = mmkvService.getString(
        'smart_push_app_open_times',
      );
      final updatedRecords = updatedRecordsStr!
          .split(',')
          .where((s) => s.isNotEmpty)
          .toList();

      // Currently, _getAppOpenRecords simply returns the split strings, so 'corrupted_data_without_datetime' will still be there.
      // And the new DateTime string will be added.
      expect(updatedRecords.length, 2);
      expect(updatedRecords.first, 'corrupted_data_without_datetime');

      final parsedDate = DateTime.tryParse(updatedRecords.last);
      expect(parsedDate, isNotNull);
    });
  });
}
