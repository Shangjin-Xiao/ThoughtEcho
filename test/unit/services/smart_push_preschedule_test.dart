import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/core/config/distribution_config.dart';
import 'package:thoughtecho/models/note_tag.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/models/smart_push_settings.dart';
import 'package:thoughtecho/services/app_preferences_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/smart_push_service.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../test_harness.dart';

class _ScheduledCall {
  final int id;
  final String? title;
  final String? body;
  final tz.TZDateTime scheduledDate;
  final AndroidScheduleMode androidScheduleMode;
  final String? payload;

  const _ScheduledCall({
    required this.id,
    required this.title,
    required this.body,
    required this.scheduledDate,
    required this.androidScheduleMode,
    required this.payload,
  });
}

class _RecordingNotificationsPlugin implements FlutterLocalNotificationsPlugin {
  final List<_ScheduledCall> scheduledCalls = [];
  final List<int> cancelledIds = [];
  int cancelAllCount = 0;

  @override
  Future<bool?> initialize(
    InitializationSettings initializationSettings, {
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
        onDidReceiveBackgroundNotificationResponse,
  }) async {
    return true;
  }

  @override
  T? resolvePlatformSpecificImplementation<
      T extends FlutterLocalNotificationsPlatform>() {
    return null;
  }

  @override
  Future<void> zonedSchedule(
    int id,
    String? title,
    String? body,
    tz.TZDateTime scheduledDate,
    NotificationDetails notificationDetails, {
    required AndroidScheduleMode androidScheduleMode,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    scheduledCalls.add(
      _ScheduledCall(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        androidScheduleMode: androidScheduleMode,
        payload: payload,
      ),
    );
  }

  @override
  Future<void> cancel(int id, {String? tag}) async {
    cancelledIds.add(id);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDatabaseService implements DatabaseService {
  List<Quote> notes;

  _FakeDatabaseService(this.notes);

  @override
  Future<List<Quote>> getAllQuotes({
    bool excludeHiddenNotes = true,
    bool includeDeleted = false,
  }) async {
    return List<Quote>.from(notes);
  }

  @override
  Future<List<Quote>> getQuotesForSmartPush({
    int limit = 200,
    String orderBy = 'q.date DESC',
    bool includeDeleted = false,
  }) async {
    return List<Quote>.from(notes);
  }

  @override
  Future<List<NoteTag>> getTags() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryPreferences implements AppPreferencesService {
  final Map<String, Object> values = {};

  @override
  String? getString(String key) => values[key] as String?;

  @override
  Future<bool> setString(String key, String value) async {
    values[key] = value;
    return true;
  }

  @override
  bool? getBool(String key) => values[key] as bool?;

  @override
  Future<bool> setBool(String key, bool value) async {
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await TestHarness.initialize();
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
  });

  tearDown(DistributionConfig.resetDebugOverrides);

  group('Android smart push 3-day local notification pre-scheduling', () {
    late _FakeDatabaseService databaseService;
    late _MemoryPreferences storage;
    late _RecordingNotificationsPlugin notificationsPlugin;
    late DateTime currentNow;
    late bool exactAlarmPermitted;

    SmartPushService createService() {
      return SmartPushService(
        databaseService: databaseService,
        locationService: LocationService(),
        mmkvService: storage,
        notificationsPlugin: notificationsPlugin,
        isAndroidOverride: true,
        isIOSOverride: false,
        canScheduleExactAlarmsOverride: () async => exactAlarmPermitted,
        nowProvider: () => currentNow,
      );
    }

    setUp(() {
      currentNow = DateTime(2026, 5, 10, 7, 30);
      exactAlarmPermitted = true;
      databaseService = _FakeDatabaseService([
        Quote(
          id: '11111111-1111-1111-1111-111111111111',
          content: '第一条回顾笔记',
          date: DateTime(2025, 5, 10, 9, 0).toIso8601String(),
        ),
        Quote(
          id: '22222222-2222-2222-2222-222222222222',
          content: '第二条回顾笔记',
          date: DateTime(2026, 4, 10, 9, 0).toIso8601String(),
        ),
        Quote(
          id: '33333333-3333-3333-3333-333333333333',
          content: '第三条回顾笔记',
          date: DateTime(2026, 5, 3, 9, 0).toIso8601String(),
        ),
      ]);
      storage = _MemoryPreferences();
      storage.values['smart_push_last_daily_quote'] = jsonEncode({
        'hitokoto': '日拱一卒，功不唐捐。',
        'from_who': '胡适',
        'from': '演讲',
      });
      storage.values['smart_push_last_daily_quote_date'] = '2026-05-10';
      notificationsPlugin = _RecordingNotificationsPlugin();
    });

    test(
      'Play Store build pre-schedules 3 days of regular and daily quote slots with exact mode when granted',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        exactAlarmPermitted = true;

        final service = createService();
        addTearDown(service.dispose);

        await service.saveSettings(
          SmartPushSettings(
            enabled: true,
            pushMode: PushMode.custom,
            enabledPastNoteTypes: const {
              PastNoteType.yearAgoToday,
              PastNoteType.monthAgoToday,
              PastNoteType.weekAgoToday,
              PastNoteType.randomMemory,
            },
            pushTimeSlots: const [
              PushTimeSlot(hour: 9, minute: 0, label: '早晨', enabled: true),
              PushTimeSlot(hour: 20, minute: 30, label: '晚间', enabled: true),
            ],
            dailyQuotePushEnabled: true,
            dailyQuotePushTime: const PushTimeSlot(
              hour: 8,
              minute: 0,
              label: '每日一言',
            ),
          ),
        );

        // 2 regular slots * 3 days + 1 daily quote * 3 days = 9 notifications
        expect(notificationsPlugin.scheduledCalls, hasLength(9));
        expect(
          notificationsPlugin.scheduledCalls.every(
            (c) =>
                c.androidScheduleMode ==
                AndroidScheduleMode.exactAllowWhileIdle,
          ),
          isTrue,
        );

        final uniqueIds =
            notificationsPlugin.scheduledCalls.map((c) => c.id).toSet();
        expect(uniqueIds, hasLength(9));

        final dailyQuoteCalls = notificationsPlugin.scheduledCalls
            .where((c) => c.payload == 'contentType:dailyQuote')
            .toList();
        expect(dailyQuoteCalls, hasLength(3));
        expect(dailyQuoteCalls.first.body, contains('日拱一卒'));

        final regularCalls = notificationsPlugin.scheduledCalls
            .where((c) => c.payload != 'contentType:dailyQuote')
            .toList();
        expect(regularCalls, hasLength(6));
        expect(
          regularCalls.every(
            (c) => (c.payload ?? '').contains('routeTarget:noteList'),
          ),
          isTrue,
        );
      },
    );

    test(
      'Standard build without exact alarm permission falls back to 3-day inexact pre-scheduling',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.standard;
        exactAlarmPermitted = false;

        final service = createService();
        addTearDown(service.dispose);

        await service.saveSettings(
          SmartPushSettings(
            enabled: true,
            pushMode: PushMode.custom,
            pushTimeSlots: const [
              PushTimeSlot(hour: 10, minute: 0, label: '上午', enabled: true),
            ],
            dailyQuotePushEnabled: false,
          ),
        );

        expect(notificationsPlugin.scheduledCalls, hasLength(3));
        expect(
          notificationsPlugin.scheduledCalls.every(
            (c) =>
                c.androidScheduleMode ==
                AndroidScheduleMode.inexactAllowWhileIdle,
          ),
          isTrue,
        );
      },
    );

    test(
      're-scheduling uses deterministic IDs and cancels disabled slots cleanly',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        final service = createService();
        addTearDown(service.dispose);

        await service.saveSettings(
          SmartPushSettings(
            enabled: true,
            pushMode: PushMode.custom,
            pushTimeSlots: const [
              PushTimeSlot(hour: 9, minute: 0, label: '早晨', enabled: true),
              PushTimeSlot(hour: 21, minute: 0, label: '夜间', enabled: true),
            ],
            dailyQuotePushEnabled: true,
            dailyQuotePushTime: const PushTimeSlot(hour: 8, minute: 0),
          ),
        );

        final initialIds =
            notificationsPlugin.scheduledCalls.map((c) => c.id).toSet();
        expect(initialIds, hasLength(9));

        // Re-run scheduleNextPush on same day -> identical deterministic IDs
        notificationsPlugin.scheduledCalls.clear();
        notificationsPlugin.cancelledIds.clear();
        await service.scheduleNextPush(preserveDeliveredNotifications: true);

        final secondIds =
            notificationsPlugin.scheduledCalls.map((c) => c.id).toSet();
        expect(secondIds, equals(initialIds));
        expect(notificationsPlugin.cancelledIds, isEmpty);
        expect(notificationsPlugin.cancelAllCount, equals(0));

        // Disable evening slot (slotIndex 1) and daily quote -> 6 removed IDs cancelled
        notificationsPlugin.scheduledCalls.clear();
        notificationsPlugin.cancelledIds.clear();
        await service.saveSettings(
          SmartPushSettings(
            enabled: true,
            pushMode: PushMode.custom,
            pushTimeSlots: const [
              PushTimeSlot(hour: 9, minute: 0, label: '早晨', enabled: true),
              PushTimeSlot(hour: 21, minute: 0, label: '夜间', enabled: false),
            ],
            dailyQuotePushEnabled: false,
          ),
        );

        final remainingIds =
            notificationsPlugin.scheduledCalls.map((c) => c.id).toSet();
        expect(remainingIds, hasLength(3));
        expect(notificationsPlugin.cancelledIds.toSet(), hasLength(6));
        expect(
          notificationsPlugin.cancelledIds.toSet().union(remainingIds),
          equals(initialIds),
        );
      },
    );

    test(
      'handleAppResumed refreshes queue when exact alarm permission changes or day rolls over',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        exactAlarmPermitted = false;

        storage.values['smart_push_settings_v2'] = jsonEncode(
          SmartPushSettings(
            enabled: true,
            pushMode: PushMode.custom,
            pushTimeSlots: const [
              PushTimeSlot(hour: 9, minute: 0, label: '早晨', enabled: true),
            ],
            dailyQuotePushEnabled: false,
          ).toJson(),
        );

        final service = createService();
        addTearDown(service.dispose);
        await service.initialize();
        expect(notificationsPlugin.scheduledCalls, hasLength(3));

        // 1 hour later, same day, same permission -> throttled (no reschedule)
        notificationsPlugin.scheduledCalls.clear();
        currentNow = DateTime(2026, 5, 10, 8, 30);
        await service.handleAppResumed();
        expect(notificationsPlugin.scheduledCalls, isEmpty);

        // 5 minutes later, user grants exact alarm permission -> refreshes immediately with exact mode
        exactAlarmPermitted = true;
        currentNow = DateTime(2026, 5, 10, 8, 35);
        await service.handleAppResumed();
        expect(notificationsPlugin.scheduledCalls, hasLength(3));
        expect(
          notificationsPlugin.scheduledCalls.every(
            (c) =>
                c.androidScheduleMode ==
                AndroidScheduleMode.exactAllowWhileIdle,
          ),
          isTrue,
        );

        // Next calendar day (< 6h across midnight) -> refreshes 3-day window
        notificationsPlugin.scheduledCalls.clear();
        currentNow = DateTime(2026, 5, 10, 22, 0);
        await service.scheduleNextPush(preserveDeliveredNotifications: true);
        notificationsPlugin.scheduledCalls.clear();

        currentNow = DateTime(2026, 5, 11, 0, 30);
        await service.handleAppResumed();
        expect(notificationsPlugin.scheduledCalls, hasLength(3));
        expect(
          notificationsPlugin.scheduledCalls.map((c) => c.scheduledDate.day),
          equals([11, 12, 13]),
        );
      },
    );
  });
}
