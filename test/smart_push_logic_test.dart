import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:thoughtecho/services/smart_push_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/mmkv_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:thoughtecho/models/smart_push_settings.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'smart_push_logic_test.mocks.dart';

// Mock Generation
@GenerateMocks([
  DatabaseService,
  LocationService,
  MMKVService,
  FlutterLocalNotificationsPlugin
])
void main() {
  late MockDatabaseService mockDatabaseService;
  late MockLocationService mockLocationService;
  late MockMMKVService mockMMKVService;
  late MockFlutterLocalNotificationsPlugin mockNotificationsPlugin;
  late SmartPushService smartPushService;

  setUp(() {
    mockDatabaseService = MockDatabaseService();
    mockLocationService = MockLocationService();
    mockMMKVService = MockMMKVService();
    mockNotificationsPlugin = MockFlutterLocalNotificationsPlugin();

    // Stubbing required calls
    when(mockMMKVService.getString(any)).thenReturn(null); // Default settings

    smartPushService = SmartPushService(
      databaseService: mockDatabaseService,
      locationService: mockLocationService,
      mmkvService: mockMMKVService,
      notificationsPlugin: mockNotificationsPlugin,
    );
  });

  test('Filtering Year Ago Today works correctly', () async {
    final now = DateTime.now();
    final lastYear = now.subtract(const Duration(days: 365));

    final note1 = Quote(
      id: '1',
      content: 'Old Note',
      date: lastYear.toIso8601String(),
      createdAt: lastYear.millisecondsSinceEpoch,
      updatedAt: lastYear.millisecondsSinceEpoch,
    );

    final note2 = Quote(
      id: '2',
      content: 'Recent Note',
      date: now.toIso8601String(),
      createdAt: now.millisecondsSinceEpoch,
      updatedAt: now.millisecondsSinceEpoch,
    );

    when(mockDatabaseService.getUserQuotes()).thenAnswer((_) async => [note1, note2]);

    // Enable Year Ago setting
    final settings = SmartPushSettings.defaultSettings().copyWith(
      enabled: true,
      enabledContentTypes: {PushContentType.pastNotes},
      enabledPastNoteTypes: {PastNoteType.yearAgoToday},
    );
    // Inject settings (mocking save/load is harder without full logic, so we access private if needed or just trust the filter logic which is public via getCandidateNotes)
    // Actually getCandidateNotes reads from private _settings. We need to set it.
    // SmartPushService exposes getter 'settings'.
    // We can simulate load by mocking mmkv.

    // Instead of full integration test, we can verify the logic logic by exposing it or making it testable.
    // Since we can't easily set private _settings, we might just test the logic if we made it public.
    // However, `getCandidateNotes` IS public. But it relies on `_settings`.
    // Let's use `saveSettings` to update `_settings`.

    await smartPushService.saveSettings(settings);

    final candidates = await smartPushService.getCandidateNotes();

    expect(candidates.length, 1);
    expect(candidates.first.content, 'Old Note');
  });
}
