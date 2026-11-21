import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/core/config/distribution_config.dart';
import 'package:thoughtecho/models/app_settings.dart';
import 'package:thoughtecho/models/note_tag.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/models/smart_push_settings.dart';
import 'package:thoughtecho/services/api_service.dart';
import 'package:thoughtecho/services/app_preferences_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/smart_push_service.dart';
import 'package:thoughtecho/utils/http_response.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:xml/xml.dart';

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

class _ShownCall {
  final int id;
  final String? title;
  final String? body;
  final String? payload;

  const _ShownCall({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
  });
}

class _RecordingNotificationsPlugin implements FlutterLocalNotificationsPlugin {
  final DateTime Function()? nowProvider;
  final List<_ScheduledCall> scheduledCalls = [];
  final Map<int, _ScheduledCall> _activeScheduledById = <int, _ScheduledCall>{};
  final Set<int> delayedPendingIds = <int>{};
  final Set<int> activeShadeIds = <int>{};
  bool throwOnGetActiveNotifications = false;
  final List<_ShownCall> shownCalls = [];
  final List<int> cancelledIds = [];
  int cancelAllCount = 0;
  Object? Function(_ScheduledCall call)? scheduleErrorBuilder;
  Future<void> Function(_ScheduledCall call)? onScheduleHook;

  _RecordingNotificationsPlugin({this.nowProvider});

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
    final call = _ScheduledCall(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      androidScheduleMode: androidScheduleMode,
      payload: payload,
    );
    final error = scheduleErrorBuilder?.call(call);
    if (error != null) {
      throw error;
    }
    scheduledCalls.add(call);
    _activeScheduledById[id] = call;
    if (onScheduleHook != null) {
      await onScheduleHook!(call);
    }
  }

  @override
  Future<void> show(
    int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails, {
    String? payload,
  }) async {
    shownCalls.add(
      _ShownCall(
        id: id,
        title: title,
        body: body,
        payload: payload,
      ),
    );
  }

  @override
  Future<void> cancel(int id, {String? tag}) async {
    cancelledIds.add(id);
    _activeScheduledById.remove(id);
    delayedPendingIds.remove(id);
    activeShadeIds.remove(id);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCount++;
    _activeScheduledById.clear();
    delayedPendingIds.clear();
    activeShadeIds.clear();
  }

  @override
  Future<List<ActiveNotification>> getActiveNotifications() async {
    if (throwOnGetActiveNotifications) {
      throw PlatformException(code: 'UNAVAILABLE');
    }
    return <ActiveNotification>[
      for (final id in activeShadeIds) ActiveNotification(id: id),
    ];
  }

  @override
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() async {
    final nowMs = nowProvider?.call().millisecondsSinceEpoch;
    return <PendingNotificationRequest>[
      for (final call in _activeScheduledById.values)
        if (delayedPendingIds.contains(call.id) ||
            (nowMs != null &&
                call.scheduledDate.millisecondsSinceEpoch > nowMs))
          PendingNotificationRequest(
            call.id,
            call.title,
            call.body,
            call.payload,
          ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDatabaseService extends ChangeNotifier implements DatabaseService {
  List<Quote> notes;
  Map<String, dynamic>? localDailyQuoteResult;
  Completer<void>? pendingQueryBarrier;
  int queryCount = 0;
  int localDailyQuoteQueryCount = 0;

  _FakeDatabaseService(this.notes);

  void notifyChanged() {
    notifyListeners();
  }

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
    queryCount++;
    final barrier = pendingQueryBarrier;
    if (barrier != null && !barrier.isCompleted) {
      await barrier.future;
    }
    return List<Quote>.from(notes);
  }

  @override
  Future<List<int>> getHourDistributionForSmartPush() async {
    return List<int>.filled(24, 0);
  }

  @override
  Future<Set<String>> getVisibleQuoteIds(Iterable<String> ids) async {
    final requested = ids.toSet();
    return notes
        .map((n) => n.id)
        .whereType<String>()
        .where(requested.contains)
        .toSet();
  }

  @override
  Future<Map<String, dynamic>?> getLocalDailyQuote({
    String offlineQuoteSource = 'tagOnly',
  }) async {
    localDailyQuoteQueryCount++;
    return localDailyQuoteResult;
  }

  @override
  Future<List<NoteTag>> getTags() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryPreferences implements AppPreferencesService {
  final Map<String, Object> _backingDisk;
  final Map<String, Object> values;
  final bool isolatedCache;
  Future<void> Function(String key, String value)? onSetStringHook;

  _MemoryPreferences({
    Map<String, Object>? sharedDisk,
    this.isolatedCache = false,
  })  : _backingDisk = sharedDisk ?? <String, Object>{},
        values = isolatedCache
            ? Map<String, Object>.from(sharedDisk ?? const <String, Object>{})
            : (sharedDisk ?? <String, Object>{});

  @override
  Future<void> reload() async {
    if (isolatedCache) {
      values
        ..clear()
        ..addAll(_backingDisk);
    }
  }

  @override
  String? getString(String key) => values[key] as String?;

  @override
  Future<bool> setString(String key, String value) async {
    values[key] = value;
    _backingDisk[key] = value;
    if (onSetStringHook != null) {
      await onSetStringHook!(key, value);
    }
    return true;
  }

  @override
  bool? getBool(String key) => values[key] as bool?;

  @override
  Future<bool> setBool(String key, bool value) async {
    values[key] = value;
    _backingDisk[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    _backingDisk.remove(key);
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
    tz.timeZoneDatabase.add(
      tz.Location(
        'Etc/GMT-8',
        [tz.minTime],
        [0],
        const [
          tz.TimeZone(
            8 * Duration.millisecondsPerHour,
            isDst: false,
            abbreviation: '+08',
          ),
        ],
      ),
    );
    tz.setLocalLocation(tz.getLocation('Etc/GMT-8'));
  });

  tearDown(() {
    DistributionConfig.resetDebugOverrides();
    ApiService.resetDebugOverrides();
    tz.setLocalLocation(tz.getLocation('Etc/GMT-8'));
  });

  group('Android smart push 3-day local notification pre-scheduling', () {
    late _FakeDatabaseService databaseService;
    late _MemoryPreferences storage;
    late _RecordingNotificationsPlugin notificationsPlugin;
    late DateTime currentNow;
    late bool exactAlarmPermitted;
    late int renewalRegisterCount;
    late int renewalCancelCount;

    tz.TZDateTime localTime(
      int year,
      int month,
      int day, [
      int hour = 0,
      int minute = 0,
    ]) =>
        tz.TZDateTime(tz.local, year, month, day, hour, minute);

    SmartPushService createService() {
      return SmartPushService(
        databaseService: databaseService,
        locationService: LocationService(),
        mmkvService: storage,
        notificationsPlugin: notificationsPlugin,
        isAndroidOverride: true,
        isIOSOverride: false,
        timeZoneOverride: 'Etc/GMT-8',
        canScheduleExactAlarmsOverride: () async => exactAlarmPermitted,
        registerPreScheduleRenewalOverride: () async {
          renewalRegisterCount++;
        },
        cancelPreScheduleRenewalOverride: () async {
          renewalCancelCount++;
        },
        nowProvider: () => currentNow,
      );
    }

    setUp(() {
      tz.setLocalLocation(tz.getLocation('Etc/GMT-8'));
      currentNow = localTime(2026, 5, 10, 7, 30);
      exactAlarmPermitted = true;
      renewalRegisterCount = 0;
      renewalCancelCount = 0;
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
        'from_who': '示例作者',
        'from': '演讲',
      });
      storage.values['smart_push_last_daily_quote_date'] = '2026-05-10';
      notificationsPlugin = _RecordingNotificationsPlugin(
        nowProvider: () => currentNow,
      );
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
            .where(
              (c) => (c.payload ?? '').startsWith('contentType:dailyQuote'),
            )
            .toList();
        expect(dailyQuoteCalls, hasLength(3));
        expect(dailyQuoteCalls.first.body, contains('日拱一卒'));
        expect(
          dailyQuoteCalls.every(
            (c) => (c.payload ?? '').contains('notificationId:${c.id}'),
          ),
          isTrue,
        );

        final regularCalls = notificationsPlugin.scheduledCalls
            .where(
              (c) => !(c.payload ?? '').startsWith('contentType:dailyQuote'),
            )
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
        currentNow = localTime(2026, 5, 10, 8, 30);
        await service.handleAppResumed();
        expect(notificationsPlugin.scheduledCalls, isEmpty);

        // 5 minutes later, user grants exact alarm permission -> refreshes immediately with exact mode
        exactAlarmPermitted = true;
        currentNow = localTime(2026, 5, 10, 8, 35);
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
        currentNow = localTime(2026, 5, 10, 22, 0);
        await service.scheduleNextPush(preserveDeliveredNotifications: true);
        notificationsPlugin.scheduledCalls.clear();

        currentNow = localTime(2026, 5, 11, 0, 30);
        await service.handleAppResumed();
        expect(notificationsPlugin.scheduledCalls, hasLength(3));
        expect(
          notificationsPlugin.scheduledCalls.map((c) => c.scheduledDate.day),
          equals([11, 12, 13]),
        );
      },
    );

    test(
      'registers periodic background renewal task when pre-scheduling and cancels it when disabled',
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
            ],
            dailyQuotePushEnabled: false,
          ),
        );

        expect(renewalRegisterCount, equals(1));
        expect(renewalCancelCount, equals(0));

        await service.saveSettings(
          SmartPushSettings(
            enabled: false,
            dailyQuotePushEnabled: false,
          ),
        );

        expect(renewalCancelCount, greaterThanOrEqualTo(1));
      },
    );

    test(
      'editing, hiding, or deleting notes immediately reconciles pending and delivered notifications',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        databaseService.notes = [
          Quote(
            id: 'note-secret',
            content: '原始私密草稿内容',
            date: DateTime(2025, 5, 10, 9, 0).toIso8601String(),
          ),
        ];

        final service = createService();
        addTearDown(service.dispose);

        await service.saveSettings(
          SmartPushSettings(
            enabled: true,
            pushMode: PushMode.custom,
            enabledPastNoteTypes: const {PastNoteType.yearAgoToday},
            pushTimeSlots: const [
              PushTimeSlot(hour: 9, minute: 0, label: '早晨', enabled: true),
            ],
            dailyQuotePushEnabled: false,
          ),
        );

        final day10Id =
            SmartPushService.deterministicPreScheduledNotificationId(
          DateTime(2026, 5, 10, 9, 0),
          slotIndex: 0,
        );
        final initialDay10 = notificationsPlugin.scheduledCalls
            .firstWhere((c) => c.id == day10Id);
        expect(initialDay10.body, contains('原始私密草稿内容'));

        // 1. Edit note within 6h throttle window -> updates pending notification body immediately
        notificationsPlugin.scheduledCalls.clear();
        currentNow = localTime(2026, 5, 10, 8, 0);
        databaseService.notes = [
          Quote(
            id: 'note-secret',
            content: '修改后的公开笔记内容',
            date: DateTime(2025, 5, 10, 9, 0).toIso8601String(),
          ),
        ];
        databaseService.notifyChanged();
        await service.waitForPendingScheduleForTest();

        final updatedDay10 = notificationsPlugin.scheduledCalls
            .firstWhere((c) => c.id == day10Id);
        expect(updatedDay10.body, contains('修改后的公开笔记内容'));

        // 2. Time advances past 09:00 delivery, an intermediate foreground refresh runs,
        //    and then the user hides/deletes the note -> delivered notification is still cancelled!
        currentNow = localTime(2026, 5, 10, 9, 30);
        await service.scheduleNextPush(preserveDeliveredNotifications: true);
        expect(notificationsPlugin.cancelledIds, isNot(contains(day10Id)));

        notificationsPlugin.scheduledCalls.clear();
        notificationsPlugin.cancelledIds.clear();
        currentNow = localTime(2026, 5, 10, 10, 0);
        databaseService.notes = [];
        databaseService.notifyChanged();
        await service.waitForPendingScheduleForTest();

        expect(notificationsPlugin.cancelledIds, contains(day10Id));
        expect(notificationsPlugin.scheduledCalls, isEmpty);
      },
    );

    test(
      'disabling reminders while an async refresh is in flight prevents stale notifications from being scheduled',
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
            ],
            dailyQuotePushEnabled: false,
          ),
        );
        notificationsPlugin.scheduledCalls.clear();
        notificationsPlugin.cancelAllCount = 0;

        // Start a background/resume refresh that pauses mid-flight on DB query
        final barrier = Completer<void>();
        databaseService.pendingQueryBarrier = barrier;
        final inflightRefresh =
            service.scheduleNextPush(preserveDeliveredNotifications: true);
        await Future<void>.delayed(Duration.zero);

        // User disables reminders while inflightRefresh is suspended
        final disableFuture = service.saveSettings(
          SmartPushSettings(
            enabled: false,
            dailyQuotePushEnabled: false,
          ),
        );

        // Release DB query so the stale refresh resumes
        barrier.complete();
        await Future.wait([inflightRefresh, disableFuture]);

        expect(notificationsPlugin.scheduledCalls, isEmpty);
        expect(notificationsPlugin.cancelAllCount, greaterThanOrEqualTo(1));
      },
    );

    test(
      'saving daily quote push with empty local cache and empty database does not make external HTTP requests',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        storage.values.clear();
        databaseService.notes = [];

        final service = createService();
        addTearDown(service.dispose);

        var httpClientCreated = false;
        await HttpOverrides.runZoned(
          () async {
            await service.saveSettings(
              SmartPushSettings(
                enabled: false,
                dailyQuotePushEnabled: true,
                dailyQuotePushTime: const PushTimeSlot(hour: 8, minute: 0),
              ),
            );
          },
          createHttpClient: (_) {
            httpClientCreated = true;
            throw StateError(
              'Unexpected external HTTP request during saveSettings',
            );
          },
        );

        expect(httpClientCreated, isFalse);
        expect(notificationsPlugin.scheduledCalls, hasLength(3));
        expect(
          notificationsPlugin.scheduledCalls.every(
            (c) => (c.payload ?? '').startsWith('contentType:dailyQuote'),
          ),
          isTrue,
        );
      },
    );

    test(
      'PushMode.smart respects pushIntensity dailyCap, minGapDays, quality floor, and elapsed delivery accounting',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        // Mark user as active with two balanced daily windows (09:00 & 20:00)
        await storage.setString(
          'smart_push_app_open_times',
          [
            localTime(2026, 5, 6, 9, 0).toIso8601String(),
            localTime(2026, 5, 7, 20, 0).toIso8601String(),
            localTime(2026, 5, 8, 9, 0).toIso8601String(),
            localTime(2026, 5, 9, 20, 0).toIso8601String(),
          ].join(','),
        );

        final service = createService();
        addTearDown(service.dispose);

        // 1. PushIntensity.rare + EngagementTier.active => dailyCap: 1, minGapDays: 2
        // Across 3 days (May 10, 11, 12), only May 10 (first slot) and May 12 (first slot) qualify!
        await service.saveSettings(
          const SmartPushSettings(
            enabled: true,
            pushMode: PushMode.smart,
            pushIntensity: PushIntensity.rare,
            dailyQuotePushEnabled: false,
          ),
        );

        expect(notificationsPlugin.scheduledCalls, hasLength(2));
        expect(
          notificationsPlugin.scheduledCalls.map((c) => c.scheduledDate.day),
          equals([10, 12]),
        );

        // Advance past Day 10 delivery (e.g. May 10 12:00) and refresh:
        // Day 10 delivery is accounted into todayCount/lastPushTime, so May 10 evening and May 11 remain skipped!
        notificationsPlugin.scheduledCalls.clear();
        currentNow = localTime(2026, 5, 10, 12, 0);
        await service.scheduleNextPush(preserveDeliveredNotifications: true);
        expect(notificationsPlugin.scheduledCalls, hasLength(1));
        expect(notificationsPlugin.scheduledCalls.single.scheduledDate.day, 12);
      },
    );

    test(
      'empty smart fallback slots memoize getLocalDailyQuote to at most one database lookup per schedule run',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        await storage.remove('smart_push_last_daily_quote');
        await storage.remove('smart_push_last_daily_quote_date');
        // One recent note from yesterday (matches neither year/month/week-ago nor randomMemory >7d)
        databaseService.notes = [
          Quote(
            id: 'recent-only-note',
            content: '昨天刚记下的随笔',
            date: DateTime(2026, 5, 9, 14, 0).toIso8601String(),
          ),
        ];
        databaseService.localDailyQuoteResult = null;

        await storage.setString(
          'smart_push_app_open_times',
          [
            localTime(2026, 5, 6, 9, 0).toIso8601String(),
            localTime(2026, 5, 7, 9, 0).toIso8601String(),
            localTime(2026, 5, 8, 9, 0).toIso8601String(),
            localTime(2026, 5, 9, 21, 0).toIso8601String(),
          ].join(','),
        );

        final service = createService();
        addTearDown(service.dispose);

        await service.saveSettings(
          const SmartPushSettings(
            enabled: true,
            pushMode: PushMode.smart,
            pushIntensity: PushIntensity.frequent,
            dailyQuotePushEnabled: true,
            dailyQuotePushTime: PushTimeSlot(hour: 8, minute: 0),
          ),
        );

        expect(databaseService.localDailyQuoteQueryCount, equals(1));
      },
    );

    test(
      'hiding a local note used as daily quote cancels tracked daily quote notification and purges cache',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        await storage.remove('smart_push_last_daily_quote');
        await storage.remove('smart_push_last_daily_quote_date');
        await storage.setString(
          'app_settings',
          jsonEncode({'useLocalQuotesOnly': true}),
        );

        const localQuoteId = '44444444-4444-4444-4444-444444444444';
        databaseService.notes = [
          Quote(
            id: localQuoteId,
            content: '本地私密摘录一言',
            date: DateTime(2026, 5, 1, 9, 0).toIso8601String(),
          ),
        ];
        databaseService.localDailyQuoteResult = {
          'content': '本地私密摘录一言',
          'type': 'local',
          'local_quote_id': localQuoteId,
          'from_who': '示例作者',
          'from': '示例出处',
        };

        final service = createService();
        addTearDown(service.dispose);

        await service.saveSettings(
          const SmartPushSettings(
            enabled: false,
            dailyQuotePushEnabled: true,
            dailyQuotePushTime: PushTimeSlot(hour: 8, minute: 0),
          ),
        );

        final day10DailyId =
            SmartPushService.deterministicPreScheduledNotificationId(
          DateTime(2026, 5, 10, 8, 0),
          isDailyQuote: true,
        );
        expect(notificationsPlugin.scheduledCalls, hasLength(3));
        expect(
          notificationsPlugin.scheduledCalls.first.body,
          contains('本地私密摘录一言'),
        );

        // Advance past 08:00 delivery, then hide/delete the backing local note
        currentNow = localTime(2026, 5, 10, 8, 30);
        notificationsPlugin.scheduledCalls.clear();
        notificationsPlugin.cancelledIds.clear();
        databaseService.notes = [];
        databaseService.localDailyQuoteResult = null;
        databaseService.notifyChanged();
        await service.waitForPendingScheduleForTest();

        // Both delivered (May 10) and pending (May 11, May 12) notifications with hidden local quote are cancelled
        expect(notificationsPlugin.cancelledIds, contains(day10DailyId));
        expect(notificationsPlugin.cancelledIds.toSet(), hasLength(3));
        expect(notificationsPlugin.scheduledCalls, isEmpty);
      },
    );

    test(
      'interrupting partial notification writes mid-loop still tracks written IDs so disabling one slot cancels them',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        final service = createService();
        addTearDown(service.dispose);

        final day10EveningId =
            SmartPushService.deterministicPreScheduledNotificationId(
          DateTime(2026, 5, 10, 21, 0),
          slotIndex: 1,
        );

        Future<void>? concurrentSlotDisable;
        var hookTriggered = false;
        notificationsPlugin.onScheduleHook = (call) async {
          if (!hookTriggered && call.id == day10EveningId) {
            hookTriggered = true;
            // User disables ONLY the evening slot right after day 10 evening is written!
            concurrentSlotDisable = service.saveSettings(
              const SmartPushSettings(
                enabled: true,
                pushMode: PushMode.custom,
                pushTimeSlots: [
                  PushTimeSlot(hour: 9, minute: 0, label: '早晨', enabled: true),
                  PushTimeSlot(
                      hour: 21, minute: 0, label: '晚间', enabled: false),
                ],
                dailyQuotePushEnabled: false,
              ),
            );
          }
        };

        await service.saveSettings(
          const SmartPushSettings(
            enabled: true,
            pushMode: PushMode.custom,
            pushTimeSlots: [
              PushTimeSlot(hour: 9, minute: 0, label: '早晨', enabled: true),
              PushTimeSlot(hour: 21, minute: 0, label: '晚间', enabled: true),
            ],
            dailyQuotePushEnabled: false,
          ),
        );
        notificationsPlugin.onScheduleHook = null;
        await concurrentSlotDisable;

        expect(hookTriggered, isTrue);
        expect(notificationsPlugin.cancelledIds, contains(day10EveningId));
      },
    );

    test(
      'cross-isolate background renewal aborts and does not re-enable notifications when foreground disables reminders',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        final sharedDisk = <String, Object>{};
        final foregroundStorage = _MemoryPreferences(
          sharedDisk: sharedDisk,
          isolatedCache: true,
        );
        final backgroundStorage = _MemoryPreferences(
          sharedDisk: sharedDisk,
          isolatedCache: true,
        );

        var bgRenewalRegisters = 0;
        var bgRenewalCancels = 0;

        final foregroundService = SmartPushService(
          databaseService: databaseService,
          locationService: LocationService(),
          mmkvService: foregroundStorage,
          notificationsPlugin: notificationsPlugin,
          isAndroidOverride: true,
          isIOSOverride: false,
          canScheduleExactAlarmsOverride: () async => true,
          registerPreScheduleRenewalOverride: () async {},
          cancelPreScheduleRenewalOverride: () async {},
          nowProvider: () => currentNow,
        );
        addTearDown(foregroundService.dispose);

        await foregroundService.saveSettings(
          const SmartPushSettings(
            enabled: true,
            pushMode: PushMode.custom,
            pushTimeSlots: [
              PushTimeSlot(hour: 9, minute: 0, label: '早晨', enabled: true),
            ],
            dailyQuotePushEnabled: false,
          ),
        );
        notificationsPlugin.scheduledCalls.clear();
        notificationsPlugin.cancelAllCount = 0;

        final backgroundService = SmartPushService(
          databaseService: databaseService,
          locationService: LocationService(),
          mmkvService: backgroundStorage,
          notificationsPlugin: notificationsPlugin,
          isAndroidOverride: true,
          isIOSOverride: false,
          canScheduleExactAlarmsOverride: () async => true,
          registerPreScheduleRenewalOverride: () async {
            bgRenewalRegisters++;
          },
          cancelPreScheduleRenewalOverride: () async {
            bgRenewalCancels++;
          },
          nowProvider: () => currentNow,
        );
        addTearDown(backgroundService.dispose);
        await backgroundStorage.reload();
        await backgroundService.loadSettingsForBackground();

        // Pause background renewal on DB query while foreground disables reminders
        final barrier = Completer<void>();
        databaseService.pendingQueryBarrier = barrier;
        final bgFuture = backgroundService.scheduleNextPush(
          fromBackground: true,
          preserveDeliveredNotifications: true,
        );
        await Future<void>.delayed(Duration.zero);

        await foregroundService.saveSettings(
          const SmartPushSettings(
            enabled: false,
            dailyQuotePushEnabled: false,
          ),
        );

        barrier.complete();
        await bgFuture;

        expect(notificationsPlugin.scheduledCalls, isEmpty);
        expect(bgRenewalRegisters, equals(0));
        expect(bgRenewalCancels, greaterThanOrEqualTo(1));
      },
    );

    test(
      'XML-parsed merged Play manifest preserves ScheduledNotificationReceiver and strips transitive permissions/services',
      () {
        const androidNs = 'http://schemas.android.com/apk/res/android';
        const toolsNs = 'http://schemas.android.com/tools';

        final mainDoc = XmlDocument.parse(
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        );
        final playDoc = XmlDocument.parse(
          File('android/app/src/play/AndroidManifest.xml').readAsStringSync(),
        );

        // Load real Android plugin manifests from .flutter-plugins-dependencies when present,
        // plus transitive AAR manifests contributed by Gradle dependencies (e.g. WorkManager & Geolocator).
        final dependencyDocs = <XmlDocument>[];
        final pluginDepsFile = File('.flutter-plugins-dependencies');
        if (pluginDepsFile.existsSync()) {
          final parsed = jsonDecode(pluginDepsFile.readAsStringSync());
          final androidPlugins = ((parsed as Map<String, dynamic>)['plugins']
              as Map<String, dynamic>?)?['android'];
          if (androidPlugins is List) {
            for (final plugin in androidPlugins) {
              if (plugin is! Map<String, dynamic>) continue;
              final pluginPath = plugin['path'] as String?;
              if (pluginPath == null || pluginPath.isEmpty) continue;
              final manifestFile = File(
                '$pluginPath/android/src/main/AndroidManifest.xml',
              );
              if (manifestFile.existsSync()) {
                dependencyDocs.add(
                  XmlDocument.parse(manifestFile.readAsStringSync()),
                );
              }
            }
          }
        }
        // Represent transitive Maven/Gradle AAR manifests (androidx.work:work-runtime, geolocator, record)
        // so the merger test exercises real transitive service/permission removal even in offline CI.
        dependencyDocs.add(
          XmlDocument.parse('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
  <uses-permission android:name="android.permission.RECORD_AUDIO" />
  <application>
    <service
      android:name="com.baseflow.geolocator.GeolocatorLocationService"
      android:enabled="true"
      android:exported="false"
      android:foregroundServiceType="location" />
    <service
      android:name="androidx.work.impl.foreground.SystemForegroundService"
      android:exported="false" />
  </application>
</manifest>
'''),
        );

        String? attrName(XmlElement el) =>
            el.getAttribute('name', namespace: androidNs);
        String? toolsNode(XmlElement el) =>
            el.getAttribute('node', namespace: toolsNs);

        Map<String, XmlElement> mergePermissions(
          List<XmlDocument> baseDocs, [
          XmlDocument? overlayDoc,
        ]) {
          final merged = <String, XmlElement>{};
          for (final doc in baseDocs) {
            for (final perm
                in doc.rootElement.findElements('uses-permission')) {
              final name = attrName(perm);
              if (name != null) merged[name] = perm;
            }
          }
          if (overlayDoc != null) {
            for (final overlayPerm
                in overlayDoc.rootElement.findElements('uses-permission')) {
              final name = attrName(overlayPerm);
              if (name == null) continue;
              if (toolsNode(overlayPerm) == 'remove') {
                merged.remove(name);
              } else {
                merged[name] = overlayPerm;
              }
            }
          }
          return merged;
        }

        Map<String, XmlElement> mergeAppComponents(
          String tag,
          List<XmlDocument> baseDocs, [
          XmlDocument? overlayDoc,
        ]) {
          final map = <String, XmlElement>{};
          for (final doc in baseDocs) {
            final app = doc.rootElement.getElement('application');
            if (app == null) continue;
            for (final el in app.findElements(tag)) {
              final name = attrName(el);
              if (name != null) map[name] = el;
            }
          }
          final overlayApp = overlayDoc?.rootElement.getElement('application');
          if (overlayApp != null) {
            for (final overlayEl in overlayApp.findElements(tag)) {
              final name = attrName(overlayEl);
              if (name == null) continue;
              if (toolsNode(overlayEl) == 'remove') {
                map.remove(name);
              } else {
                map[name] = overlayEl;
              }
            }
          }
          return map;
        }

        final baseDocs = <XmlDocument>[...dependencyDocs, mainDoc];
        const removedPermissions = <String>[
          'android.permission.REQUEST_INSTALL_PACKAGES',
          'android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
          'android.permission.RECORD_AUDIO',
          'android.permission.READ_MEDIA_IMAGES',
          'android.permission.READ_MEDIA_VIDEO',
          'android.permission.READ_MEDIA_AUDIO',
          'android.permission.READ_EXTERNAL_STORAGE',
          'android.permission.FOREGROUND_SERVICE',
          'android.permission.FOREGROUND_SERVICE_DATA_SYNC',
        ];
        const removedServices = <String>[
          'com.baseflow.geolocator.GeolocatorLocationService',
          'androidx.work.impl.foreground.SystemForegroundService',
        ];

        // 1. Pre-overlay baseline: confirm transitive services and permissions ARE present before Play overlay
        final prePlayPermissions = mergePermissions(baseDocs);
        final prePlayServices = mergeAppComponents('service', baseDocs);
        for (final svc in removedServices) {
          expect(
            prePlayServices.containsKey(svc),
            isTrue,
            reason: 'Expected $svc in pre-Play merged manifest baseline',
          );
        }
        for (final perm in removedPermissions) {
          expect(
            prePlayPermissions.containsKey(perm),
            isTrue,
            reason: 'Expected $perm in pre-Play merged manifest baseline',
          );
        }

        // 2. Post-Play overlay: confirm Play manifest strips all prohibited services and permissions
        final mergedPermissions = mergePermissions(baseDocs, playDoc);
        final mergedReceivers =
            mergeAppComponents('receiver', baseDocs, playDoc);
        final mergedServices = mergeAppComponents('service', baseDocs, playDoc);

        final scheduledReceiver = mergedReceivers[
            'com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver'];
        expect(scheduledReceiver, isNotNull);
        expect(
          scheduledReceiver!.getAttribute('exported', namespace: androidNs),
          equals('false'),
        );
        expect(
          scheduledReceiver.getAttribute('enabled', namespace: androidNs),
          isNot(equals('false')),
        );

        final bootReceiver = mergedReceivers[
            'com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver'];
        expect(bootReceiver, isNotNull);
        expect(
          bootReceiver!.getAttribute('exported', namespace: androidNs),
          equals('false'),
        );

        for (final svc in removedServices) {
          expect(mergedServices.containsKey(svc), isFalse);
        }
        for (final removedPerm in removedPermissions) {
          expect(mergedPermissions.containsKey(removedPerm), isFalse);
        }
        expect(
          mergedPermissions
              .containsKey('android.permission.POST_NOTIFICATIONS'),
          isTrue,
        );
        expect(
          mergedPermissions.containsKey(
            'android.permission.RECEIVE_BOOT_COMPLETED',
          ),
          isTrue,
        );

        // 3. Negative mutation check: stripping tools:node="remove" from Play overlay causes leak detection
        final mutatedPlayDoc = XmlDocument.parse(playDoc.toXmlString());
        for (final el in mutatedPlayDoc.descendants.whereType<XmlElement>()) {
          if (toolsNode(el) == 'remove') {
            el.removeAttribute('node', namespace: toolsNs);
          }
        }
        final leakedServices =
            mergeAppComponents('service', baseDocs, mutatedPlayDoc);
        final leakedPermissions = mergePermissions(baseDocs, mutatedPlayDoc);
        for (final svc in removedServices) {
          expect(leakedServices.containsKey(svc), isTrue);
        }
        for (final perm in removedPermissions) {
          expect(leakedPermissions.containsKey(perm), isTrue);
        }
      },
    );

    test(
      'PushMode.smart suppresses regular slots during dismissal cooldown while preserving independent daily quote',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        await storage.setString(
          'smart_push_app_open_times',
          [
            localTime(2026, 5, 6, 9, 0).toIso8601String(),
            localTime(2026, 5, 7, 20, 0).toIso8601String(),
            localTime(2026, 5, 8, 9, 0).toIso8601String(),
            localTime(2026, 5, 9, 20, 0).toIso8601String(),
          ].join(','),
        );
        // Active 8h dismissal cooldown from May 10 07:00 -> suppresses May 10 morning slot (before 15:00)
        await storage.setString(
          'smart_push_last_dismissal',
          localTime(2026, 5, 10, 7, 0).toIso8601String(),
        );

        final service = createService();
        addTearDown(service.dispose);

        await service.saveSettings(
          const SmartPushSettings(
            enabled: true,
            pushMode: PushMode.smart,
            pushIntensity: PushIntensity.balanced,
            dailyQuotePushEnabled: true,
            dailyQuotePushTime: PushTimeSlot(hour: 8, minute: 0),
          ),
        );

        final dailyQuoteCalls = notificationsPlugin.scheduledCalls
            .where(
                (c) => (c.payload ?? '').startsWith('contentType:dailyQuote'))
            .toList();
        final regularCalls = notificationsPlugin.scheduledCalls
            .where(
              (c) => !(c.payload ?? '').startsWith('contentType:dailyQuote'),
            )
            .toList();

        // Independent Daily Quote still schedules all 3 days (May 10, 11, 12)
        expect(dailyQuoteCalls, hasLength(3));
        // Regular slots before May 10 15:00 are suppressed by dismissal cooldown
        expect(
          regularCalls.every(
            (c) => !c.scheduledDate.isBefore(localTime(2026, 5, 10, 15, 0)),
          ),
          isTrue,
        );
        expect(regularCalls, isNotEmpty);
      },
    );

    test(
      'custom yearAgoToday mode skips empty future days and cancels previously scheduled empty slots',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        databaseService.notes = [
          Quote(
            id: '55555555-5555-5555-5555-555555555555',
            content: '仅限五月十日的那年今日笔记',
            date: DateTime(2025, 5, 10, 9, 0).toIso8601String(),
          ),
        ];

        final service = createService();
        addTearDown(service.dispose);

        // First schedule with randomMemory enabled -> all 3 days match
        await service.saveSettings(
          const SmartPushSettings(
            enabled: true,
            pushMode: PushMode.custom,
            enabledPastNoteTypes: {
              PastNoteType.yearAgoToday,
              PastNoteType.randomMemory,
            },
            pushTimeSlots: [
              PushTimeSlot(hour: 9, minute: 0, label: '早晨', enabled: true),
            ],
            dailyQuotePushEnabled: false,
          ),
        );
        expect(notificationsPlugin.scheduledCalls, hasLength(3));
        final day11Id =
            SmartPushService.deterministicPreScheduledNotificationId(
          DateTime(2026, 5, 11, 9, 0),
          slotIndex: 0,
        );
        final day12Id =
            SmartPushService.deterministicPreScheduledNotificationId(
          DateTime(2026, 5, 12, 9, 0),
          slotIndex: 0,
        );

        // Now restrict to yearAgoToday only -> May 11 & May 12 have no matching notes,
        // so they must be cancelled and NOT replaced with placeholders or May 10's note!
        notificationsPlugin.scheduledCalls.clear();
        notificationsPlugin.cancelledIds.clear();
        await service.saveSettings(
          const SmartPushSettings(
            enabled: true,
            pushMode: PushMode.custom,
            enabledPastNoteTypes: {PastNoteType.yearAgoToday},
            pushTimeSlots: [
              PushTimeSlot(hour: 9, minute: 0, label: '早晨', enabled: true),
            ],
            dailyQuotePushEnabled: false,
          ),
        );

        expect(notificationsPlugin.scheduledCalls, hasLength(1));
        expect(notificationsPlugin.scheduledCalls.single.scheduledDate.day, 10);
        expect(
          notificationsPlugin.scheduledCalls.single.body,
          contains('仅限五月十日的那年今日笔记'),
        );
        expect(
          notificationsPlugin.cancelledIds,
          containsAll(<int>[day11Id, day12Id]),
        );
      },
    );

    test(
      'PushMode.smart never repeats the same anniversary note across two slots on the same day or after midday refresh',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        const yearAgoId = '66666666-6666-6666-6666-666666666666';
        const monthAgoId = '77777777-7777-7777-7777-777777777777';
        databaseService.notes = [
          Quote(
            id: yearAgoId,
            content: '去年今日的高优先级长篇纪念回顾笔记，确保得分充裕且内容完整清晰。',
            date: DateTime(2025, 5, 10, 9, 0).toIso8601String(),
          ),
          Quote(
            id: monthAgoId,
            content:
                '上月今日的次优先级深度回顾长笔记，包含足够字数以满足智能模式同日第二条推送的质量门槛要求，确保在首条推送已选用那年今日后能够平滑接棒而不重复。',
            date: DateTime(2026, 4, 10, 9, 0).toIso8601String(),
          ),
        ];

        await storage.setString(
          'smart_push_app_open_times',
          [
            localTime(2026, 5, 6, 9, 0).toIso8601String(),
            localTime(2026, 5, 7, 20, 0).toIso8601String(),
            localTime(2026, 5, 8, 9, 0).toIso8601String(),
            localTime(2026, 5, 9, 20, 0).toIso8601String(),
          ].join(','),
        );

        final service = createService();
        addTearDown(service.dispose);

        await service.saveSettings(
          const SmartPushSettings(
            enabled: true,
            pushMode: PushMode.smart,
            pushIntensity: PushIntensity.frequent,
            dailyQuotePushEnabled: false,
          ),
        );

        final may10Calls = notificationsPlugin.scheduledCalls
            .where((c) => c.scheduledDate.day == 10)
            .toList();
        expect(may10Calls, hasLength(2));
        expect(may10Calls[0].payload, contains('noteId:$yearAgoId'));
        expect(may10Calls[1].payload, contains('noteId:$monthAgoId'));

        // Refresh at 12:00 after morning slot (08:30) has delivered -> evening slot (20:00) still excludes yearAgoId!
        notificationsPlugin.scheduledCalls.clear();
        currentNow = localTime(2026, 5, 10, 12, 0);
        await service.scheduleNextPush(preserveDeliveredNotifications: true);

        final remainingMay10Calls = notificationsPlugin.scheduledCalls
            .where((c) => c.scheduledDate.day == 10)
            .toList();
        expect(remainingMay10Calls, hasLength(1));
        expect(
          remainingMay10Calls.single.payload,
          contains('noteId:$monthAgoId'),
        );
      },
    );

    test(
      'regular smart daily-quote fallback routes taps to dailyQuote and preserves exact local quote until hidden',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        await storage.remove('smart_push_last_daily_quote');
        await storage.remove('smart_push_last_daily_quote_date');
        await storage.setString(
          'smart_push_app_open_times',
          [
            localTime(2026, 5, 6, 9, 0).toIso8601String(),
            localTime(2026, 5, 7, 9, 0).toIso8601String(),
            localTime(2026, 5, 8, 9, 0).toIso8601String(),
            localTime(2026, 5, 9, 21, 0).toIso8601String(),
          ].join(','),
        );

        const scheduledLocalId = '88888888-8888-8888-8888-888888888888';
        const otherLocalId = '99999999-9999-9999-9999-999999999999';
        // Empty regular candidate pool (note from 2 hours ago on same day is excluded by all past-note filters),
        // wait: keep backing local quotes visible in getVisibleQuoteIds via databaseService.notes from today!
        databaseService.notes = [
          Quote(
            id: scheduledLocalId,
            content: '通知栏上实际展示的专属本地一言',
            date: localTime(2026, 5, 10, 7, 0).toIso8601String(),
          ),
          Quote(
            id: otherLocalId,
            content: '数据库随机抽到的另一条本地一言',
            date: localTime(2026, 5, 10, 7, 10).toIso8601String(),
          ),
        ];
        databaseService.localDailyQuoteResult = {
          'content': '通知栏上实际展示的专属本地一言',
          'type': 'local',
          'local_quote_id': scheduledLocalId,
          'from_who': '示例作者甲',
          'from': '示例文集',
        };

        final service = createService();
        addTearDown(service.dispose);

        await service.saveSettings(
          const SmartPushSettings(
            enabled: true,
            pushMode: PushMode.smart,
            pushIntensity: PushIntensity.rare,
            dailyQuotePushEnabled: false,
          ),
        );

        // Regular slot fell back to local daily quote -> must emit contentType:dailyQuote|notificationId:...
        expect(notificationsPlugin.scheduledCalls, isNotEmpty);
        final fallbackCall = notificationsPlugin.scheduledCalls.first;
        expect(fallbackCall.title, equals('📖 每日一言'));
        expect(fallbackCall.body, contains('通知栏上实际展示的专属本地一言'));
        expect(
          fallbackCall.payload,
          equals(
            'contentType:dailyQuote|notificationId:${fallbackCall.id}',
          ),
        );

        // Simulate tapping next day / when daily cache is empty and DB random query would return a DIFFERENT quote
        currentNow = localTime(2026, 5, 10, 9, 0);
        databaseService.localDailyQuoteResult = {
          'content': '数据库随机抽到的另一条本地一言',
          'type': 'local',
          'local_quote_id': otherLocalId,
          'from_who': '示例作者乙',
          'from': '示例随笔',
        };

        await service.handleNotificationTapForTest(
          NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            id: fallbackCall.id,
            payload: fallbackCall.payload,
          ),
        );

        final pendingQuote =
            await service.consumePendingDailyQuoteForHomeDisplay();
        expect(pendingQuote, isNotNull);
        expect(pendingQuote!['hitokoto'], equals('通知栏上实际展示的专属本地一言'));
        expect(pendingQuote['local_quote_id'], equals(scheduledLocalId));

        // Now hide/delete the backing local note without waiting for reschedule, and tap again -> must NOT leak!
        databaseService.notes = [];
        await service.handleNotificationTapForTest(
          NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            id: fallbackCall.id,
            payload: fallbackCall.payload,
          ),
        );
        expect(
          await service.consumePendingDailyQuoteForHomeDisplay(),
          isNull,
        );
      },
    );

    test(
      'keeps periodic renewal task alive when 7-day dormant cooldown empties 3-day window and resumes reminders automatically',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        // Dormant user: last opened 20 days ago -> PushIntensity.rare requires minGapDays: 7
        await storage.setString(
          'smart_push_app_open_times',
          localTime(2026, 4, 20, 9, 0).toIso8601String(),
        );
        databaseService.notes = [
          Quote(
            id: 'aaaa1111-1111-1111-1111-111111111111',
            content: '沉睡档位恢复验证的长回顾笔记，用于验证七天间隔期满后后台续期自动恢复。',
            date: localTime(2025, 5, 1, 9, 0).toIso8601String(),
          ),
        ];

        final service = createService();
        addTearDown(service.dispose);

        await service.saveSettings(
          const SmartPushSettings(
            enabled: true,
            pushMode: PushMode.smart,
            pushIntensity: PushIntensity.rare,
            dailyQuotePushEnabled: false,
          ),
        );

        // Day 0 (May 10): schedules May 10 only (May 11 & 12 filtered by minGapDays: 7)
        expect(notificationsPlugin.scheduledCalls, hasLength(1));
        expect(notificationsPlugin.scheduledCalls.single.scheduledDate.day, 10);
        expect(renewalRegisterCount, equals(1));
        expect(renewalCancelCount, equals(0));

        // Day 1 (May 11): background renewal settles May 10 delivery;
        // next 3 days (May 11, 12, 13) are all inside the 7-day gap -> 0 notifications scheduled,
        // BUT renewal task MUST remain registered (never cancelled)!
        notificationsPlugin.scheduledCalls.clear();
        currentNow = localTime(2026, 5, 11, 9, 0);
        await service.renewPreScheduledQueueFromBackground();

        expect(notificationsPlugin.scheduledCalls, isEmpty);
        expect(renewalCancelCount, equals(0));
        expect(renewalRegisterCount, equals(2));

        // Day 5 (May 15): 3-day lookahead [May 15, 16, 17] reaches May 17 (7 days after May 10) ->
        // background renewal automatically schedules May 17 without user opening the app!
        notificationsPlugin.scheduledCalls.clear();
        currentNow = localTime(2026, 5, 15, 7, 30);
        await service.renewPreScheduledQueueFromBackground();

        expect(notificationsPlugin.scheduledCalls, hasLength(1));
        expect(notificationsPlugin.scheduledCalls.single.scheduledDate.day, 17);
        expect(renewalCancelCount, equals(0));
      },
    );

    test(
      'tapping an unaccounted pre-scheduled notification records positive engagement and is never overwritten as ignored',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        const yearAgoId = 'bbbb2222-2222-2222-2222-222222222222';
        const monthAgoId = 'cccc3333-3333-3333-3333-333333333333';
        databaseService.notes = [
          Quote(
            id: yearAgoId,
            content: '那年今日高优先级长篇回顾笔记，包含充裕内容以验证点击正向计分不被覆盖。',
            date: localTime(2025, 5, 10, 9, 0).toIso8601String(),
          ),
          Quote(
            id: monthAgoId,
            content: '上月今日第二优先级长篇回顾笔记，字数充足可通过同日第二条智能推送的质量门槛，验证多条通知补记时点击状态精确匹配。',
            date: localTime(2026, 4, 10, 9, 0).toIso8601String(),
          ),
        ];
        await storage.setString(
          'smart_push_app_open_times',
          [
            localTime(2026, 5, 6, 9, 0).toIso8601String(),
            localTime(2026, 5, 7, 20, 0).toIso8601String(),
            localTime(2026, 5, 8, 9, 0).toIso8601String(),
            localTime(2026, 5, 9, 20, 0).toIso8601String(),
          ].join(','),
        );

        final service = createService();
        addTearDown(service.dispose);

        await service.saveSettings(
          const SmartPushSettings(
            enabled: true,
            pushMode: PushMode.smart,
            pushIntensity: PushIntensity.frequent,
            dailyQuotePushEnabled: false,
          ),
        );

        final may10Calls = notificationsPlugin.scheduledCalls
            .where((c) => c.scheduledDate.day == 10)
            .toList();
        expect(may10Calls, hasLength(2));
        final morningCall = may10Calls[0];
        final eveningCall = may10Calls[1];

        // Seed an existing unengaged streak of 2 before user taps morning notification
        await storage.setString('smart_push_unengaged_streak', '2');

        // Advance past BOTH May 10 slots (20:05) and tap ONLY the morning notification before accounting runs:
        // Morning must settle as engaged (score > 0.5, streak = 0) while evening stays pending (not settled as ignored yet)
        currentNow = localTime(2026, 5, 10, 20, 5);
        await service.handleNotificationTapForTest(
          NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            id: morningCall.id,
            payload: morningCall.payload,
          ),
        );

        // Subsequent reschedule must NOT overwrite morning click or prematurely penalize evening
        await service.scheduleNextPush(preserveDeliveredNotifications: true);

        expect(await service.analytics.getUnengagedStreak(), equals(0));
        expect(
          await service.analytics.getHabituationCooldown(),
          equals(Duration.zero),
        );
        final scoresAfterMorningTap =
            await service.analytics.getContentTypeScores();
        expect(scoresAfterMorningTap['yearAgoToday']!, greaterThan(0.5));
        expect(scoresAfterMorningTap.containsKey('monthAgoToday'), isFalse);

        // Now user ALSO taps the pending evening notification -> settles cleanly on next settlePendingSend() with streak still 0!
        await service.handleNotificationTapForTest(
          NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            id: eveningCall.id,
            payload: eveningCall.payload,
          ),
        );
        await service.analytics.settlePendingSend();

        expect(await service.analytics.getUnengagedStreak(), equals(0));
        final scoresAfterBoth = await service.analytics.getContentTypeScores();
        expect(scoresAfterBoth['yearAgoToday']!, greaterThan(0.5));
        expect(scoresAfterBoth['monthAgoToday']!, greaterThan(0.5));
      },
    );

    test(
      'background renewal rolls back written notifications and renewal task if foreground disables reminders mid-write',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        final sharedDisk = <String, Object>{};
        final foregroundStorage = _MemoryPreferences(
          sharedDisk: sharedDisk,
          isolatedCache: true,
        );
        final backgroundStorage = _MemoryPreferences(
          sharedDisk: sharedDisk,
          isolatedCache: true,
        );

        var bgRenewalCancels = 0;

        final foregroundService = SmartPushService(
          databaseService: databaseService,
          locationService: LocationService(),
          mmkvService: foregroundStorage,
          notificationsPlugin: notificationsPlugin,
          isAndroidOverride: true,
          isIOSOverride: false,
          canScheduleExactAlarmsOverride: () async => true,
          registerPreScheduleRenewalOverride: () async {},
          cancelPreScheduleRenewalOverride: () async {},
          nowProvider: () => currentNow,
        );
        addTearDown(foregroundService.dispose);

        await foregroundService.saveSettings(
          const SmartPushSettings(
            enabled: true,
            pushMode: PushMode.custom,
            pushTimeSlots: [
              PushTimeSlot(hour: 9, minute: 0, label: '早晨', enabled: true),
            ],
            dailyQuotePushEnabled: false,
          ),
        );
        notificationsPlugin.scheduledCalls.clear();
        notificationsPlugin.cancelledIds.clear();
        notificationsPlugin.cancelAllCount = 0;

        final backgroundService = SmartPushService(
          databaseService: databaseService,
          locationService: LocationService(),
          mmkvService: backgroundStorage,
          notificationsPlugin: notificationsPlugin,
          isAndroidOverride: true,
          isIOSOverride: false,
          canScheduleExactAlarmsOverride: () async => true,
          registerPreScheduleRenewalOverride: () async {},
          cancelPreScheduleRenewalOverride: () async {
            bgRenewalCancels++;
          },
          nowProvider: () => currentNow,
        );
        addTearDown(backgroundService.dispose);
        await backgroundStorage.reload();
        await backgroundService.loadSettingsForBackground();

        // Trigger foreground disable right AFTER background writes its last zonedSchedule!
        var writeCount = 0;
        notificationsPlugin.onScheduleHook = (call) async {
          writeCount++;
          if (writeCount == 3) {
            await foregroundService.saveSettings(
              const SmartPushSettings(
                enabled: false,
                dailyQuotePushEnabled: false,
              ),
            );
          }
        };

        await backgroundService.renewPreScheduledQueueFromBackground();
        notificationsPlugin.onScheduleHook = null;

        await foregroundStorage.reload();
        final finalSettingsJson =
            foregroundStorage.getString('smart_push_settings_v2');
        expect(finalSettingsJson, isNotNull);
        final finalSettings = SmartPushSettings.fromJson(
          jsonDecode(finalSettingsJson!) as Map<String, dynamic>,
        );
        expect(finalSettings.enabled, isFalse);
        expect(finalSettings.dailyQuotePushEnabled, isFalse);
        expect(
          foregroundStorage.getString('smart_push_prescheduled_entries_v1'),
          isNull,
        );
        expect(notificationsPlugin.cancelledIds, isNotEmpty);
        expect(bgRenewalCancels, greaterThanOrEqualTo(1));
      },
    );

    test(
      'standard exact-alarm checkAndPush binds shown notificationId to markSent and settles tap as engaged once',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.standard;
        exactAlarmPermitted = true;
        final wallNow = DateTime.now();
        databaseService.notes = [
          Quote(
            id: 'dddd4444-4444-4444-4444-444444444444',
            content: '标准渠道精确闹钟直发通知点击回归验证笔记，确保点击后不会被二次结算成忽略。',
            date: DateTime(
              wallNow.year - 1,
              wallNow.month,
              wallNow.day,
              9,
              0,
            ).toIso8601String(),
          ),
        ];
        await storage.setString(
          'smart_push_app_open_times',
          List.generate(
            4,
            (i) =>
                wallNow.subtract(Duration(days: i, hours: 6)).toIso8601String(),
          ).join(','),
        );
        await storage.setString('smart_push_unengaged_streak', '2');

        final service = createService();
        addTearDown(service.dispose);

        await service.saveSettings(
          const SmartPushSettings(
            enabled: true,
            pushMode: PushMode.smart,
            pushIntensity: PushIntensity.frequent,
            dailyQuotePushEnabled: false,
          ),
        );

        await service.checkAndPush();
        expect(notificationsPlugin.shownCalls, hasLength(1));
        final shown = notificationsPlugin.shownCalls.single;
        expect(shown.id, greaterThan(0));
        expect(shown.payload, contains('notificationId:${shown.id}'));

        await service.handleNotificationTapForTest(
          NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            id: shown.id,
            payload: shown.payload,
          ),
        );
        await service.analytics.settlePendingSend();

        expect(await service.analytics.getUnengagedStreak(), equals(0));
        expect(
          await service.analytics.getHabituationCooldown(),
          equals(Duration.zero),
        );
        final scores = await service.analytics.getContentTypeScores();
        expect(scores['yearAgoToday'], closeTo(2 / 3, 1e-6));
      },
    );

    test(
      'disabling reminders while notification tap accounting is in flight never overwrites disabled settings',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        databaseService.notes = [
          Quote(
            id: 'eeee5555-5555-5555-5555-555555555555',
            content: '验证点击补记与关闭提醒并发交错时，旧快照静默保存不会覆盖用户关闭状态的回归笔记。',
            date: localTime(2025, 5, 10, 9, 0).toIso8601String(),
          ),
        ];
        await storage.setString(
          'smart_push_app_open_times',
          [
            localTime(2026, 5, 6, 9, 0).toIso8601String(),
            localTime(2026, 5, 7, 9, 0).toIso8601String(),
            localTime(2026, 5, 8, 9, 0).toIso8601String(),
            localTime(2026, 5, 9, 20, 0).toIso8601String(),
          ].join(','),
        );

        final service = createService();
        addTearDown(service.dispose);

        await service.saveSettings(
          const SmartPushSettings(
            enabled: true,
            pushMode: PushMode.smart,
            pushIntensity: PushIntensity.balanced,
            dailyQuotePushEnabled: false,
          ),
        );

        final deliveredCall = notificationsPlugin.scheduledCalls.first;
        currentNow = localTime(2026, 5, 10, 9, 30);

        Future<void>? concurrentDisableFuture;
        storage.onSetStringHook = (key, value) async {
          if (key == 'smart_push_daily_count' &&
              concurrentDisableFuture == null) {
            storage.onSetStringHook = null;
            concurrentDisableFuture = service.saveSettings(
              const SmartPushSettings(
                enabled: false,
                dailyQuotePushEnabled: false,
              ),
            );
            // Yield microtasks so saveSettings writes disabled state and bumps epoch
            // before in-flight tap accounting reaches _saveSettingsQuietly.
            await Future<void>.delayed(Duration.zero);
          }
        };

        await service.handleNotificationTapForTest(
          NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            id: deliveredCall.id,
            payload: deliveredCall.payload,
          ),
        );
        expect(concurrentDisableFuture, isNotNull);
        await concurrentDisableFuture;

        expect(service.settings.enabled, isFalse);
        expect(service.settings.dailyQuotePushEnabled, isFalse);
        final storedJson = storage.getString('smart_push_settings_v2');
        expect(storedJson, isNotNull);
        final storedSettings = SmartPushSettings.fromJson(
          jsonDecode(storedJson!) as Map<String, dynamic>,
        );
        expect(storedSettings.enabled, isFalse);
        expect(storedSettings.dailyQuotePushEnabled, isFalse);
        expect(
          storage.getString('smart_push_prescheduled_entries_v1'),
          isNull,
        );
      },
    );

    test(
      'database change or enabled settings update during accounting never double-counts delivered notification',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        databaseService.notes = [
          Quote(
            id: 'ffff6666-6666-6666-6666-666666666666',
            content: '验证补记期间发生数据库变更或保持开启的设置更新时不会重复计数的第一条笔记。',
            date: localTime(2025, 5, 10, 9, 0).toIso8601String(),
          ),
          Quote(
            id: 'aaaa7777-7777-7777-7777-777777777777',
            content: '验证补记期间发生保持开启的设置更新时不会把同一通知结算两次的第二条笔记。',
            date: localTime(2025, 5, 11, 9, 0).toIso8601String(),
          ),
        ];
        await storage.setString(
          'smart_push_app_open_times',
          [
            localTime(2026, 5, 6, 9, 0).toIso8601String(),
            localTime(2026, 5, 7, 9, 0).toIso8601String(),
            localTime(2026, 5, 8, 9, 0).toIso8601String(),
            localTime(2026, 5, 9, 20, 0).toIso8601String(),
          ].join(','),
        );

        final service = createService();
        addTearDown(service.dispose);

        await service.saveSettings(
          const SmartPushSettings(
            enabled: true,
            pushMode: PushMode.smart,
            pushIntensity: PushIntensity.balanced,
            dailyQuotePushEnabled: false,
          ),
        );

        final firstCall = notificationsPlugin.scheduledCalls.first;
        currentNow = localTime(2026, 5, 10, 9, 30);

        var triggeredDbChange = false;
        storage.onSetStringHook = (key, value) async {
          if (key == 'smart_push_daily_count' && !triggeredDbChange) {
            triggeredDbChange = true;
            storage.onSetStringHook = null;
            databaseService.notifyChanged();
            await Future<void>.delayed(Duration.zero);
          }
        };

        await service.handleNotificationTapForTest(
          NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            id: firstCall.id,
            payload: firstCall.payload,
          ),
        );
        await service.waitForPendingScheduleForTest();

        expect(triggeredDbChange, isTrue);
        expect(
          await service.analytics.getTodayPushCount(now: currentNow),
          equals(1),
        );
        final statsAfterTap = await service.analytics.getAnalyticsStats();
        expect(statsAfterTap['totalNotificationsSent'], equals(1));
        expect(statsAfterTap['totalEngagements'], equals(1));

        // 推进到次日已送达未点击通知，在补记中途修改设置（保持 enabled: true）
        final nextDayCall = notificationsPlugin.scheduledCalls.firstWhere(
          (call) => call.scheduledDate.isAfter(currentNow),
        );
        currentNow = tz.TZDateTime.fromMillisecondsSinceEpoch(
          tz.local,
          nextDayCall.scheduledDate.millisecondsSinceEpoch + 30 * 60 * 1000,
        );

        Future<void>? concurrentSettingsUpdate;
        storage.onSetStringHook = (key, value) async {
          if (key == 'smart_push_daily_count' &&
              concurrentSettingsUpdate == null) {
            storage.onSetStringHook = null;
            concurrentSettingsUpdate = service.saveSettings(
              const SmartPushSettings(
                enabled: true,
                pushMode: PushMode.smart,
                pushIntensity: PushIntensity.frequent,
                dailyQuotePushEnabled: false,
              ),
            );
            await Future<void>.delayed(Duration.zero);
          }
        };

        await service.scheduleNextPush(preserveDeliveredNotifications: true);
        expect(concurrentSettingsUpdate, isNotNull);
        await concurrentSettingsUpdate;
        await service.waitForPendingScheduleForTest();

        expect(service.settings.pushIntensity, equals(PushIntensity.frequent));
        expect(
          await service.analytics.getTodayPushCount(now: currentNow),
          equals(1),
        );
        // 同一条未点击通知不应在中断重试时自己把自己提前结算为未点击
        expect(await service.analytics.getUnengagedStreak(), equals(0));
        final trackedRaw =
            storage.getString('smart_push_prescheduled_entries_v1');
        expect(trackedRaw, isNotNull);
        final trackedList =
            (jsonDecode(trackedRaw!) as List).cast<Map<String, dynamic>>();
        final accountedEntry = trackedList.firstWhere(
          (item) => item['id'] == nextDayCall.id,
        );
        expect(accountedEntry['accounted'], isTrue);
      },
    );

    test(
      'immediate notifications allocate monotonic 31-bit IDs without colliding at fixed clock',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.standard;
        exactAlarmPermitted = true;
        final wallNow = DateTime.now();
        databaseService.notes = [
          Quote(
            id: 'bbbb8888-8888-8888-8888-888888888888',
            content: '验证立即推送通知在固定时钟下仍单调递增且落入独立 31 位正整数区间的回归笔记。',
            date: DateTime(
              wallNow.year - 1,
              wallNow.month,
              wallNow.day,
              9,
              0,
            ).toIso8601String(),
          ),
        ];

        final service = createService();
        addTearDown(service.dispose);

        await service.triggerPush();
        await service.triggerPush();

        expect(notificationsPlugin.shownCalls, hasLength(2));
        final firstId = notificationsPlugin.shownCalls[0].id;
        final secondId = notificationsPlugin.shownCalls[1].id;
        expect(firstId, greaterThanOrEqualTo(300000000));
        expect(firstId, lessThanOrEqualTo(1999999999));
        expect(secondId, equals(firstId + 1));
      },
    );

    test(
      'changing reminder times after scheduled minute passes cancels delayed inexact pending notifications without false quota accounting',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        exactAlarmPermitted = false;
        currentNow = localTime(2026, 5, 9, 22, 0);

        final service = createService();
        addTearDown(service.dispose);
        await service.initialize();

        await service.saveSettings(
          const SmartPushSettings(
            enabled: true,
            pushMode: PushMode.smart,
            pushIntensity: PushIntensity.balanced,
            dailyQuotePushEnabled: true,
            dailyQuotePushTime: PushTimeSlot(
              hour: 8,
              minute: 0,
              label: '每日一言',
            ),
          ),
        );

        final todayDailyCall = notificationsPlugin.scheduledCalls.firstWhere(
          (call) =>
              call.scheduledDate.year == 2026 &&
              call.scheduledDate.month == 5 &&
              call.scheduledDate.day == 10 &&
              call.title == '📖 每日一言',
        );
        final todayRegularCall = notificationsPlugin.scheduledCalls.firstWhere(
          (call) =>
              call.scheduledDate.year == 2026 &&
              call.scheduledDate.month == 5 &&
              call.scheduledDate.day == 10 &&
              call.title != '📖 每日一言',
        );

        // 模拟跨天且无精确闹钟下已过计划时间（08:35 > 08:00 / 08:30），但系统尚未送达这两条通知
        currentNow = localTime(2026, 5, 10, 8, 35);
        notificationsPlugin.delayedPendingIds
          ..add(todayDailyCall.id)
          ..add(todayRegularCall.id);
        notificationsPlugin.cancelledIds.clear();
        final queriesBeforeResume = databaseService.queryCount;

        // 回到前台触发真实对账刷新（futureOnly: true）时应保留待系统送达的延迟通知，且不提前误计入今日已送达配额
        await service.handleAppResumed();
        expect(databaseService.queryCount, greaterThan(queriesBeforeResume));
        expect(
          notificationsPlugin.cancelledIds,
          isNot(contains(todayDailyCall.id)),
        );
        expect(
          notificationsPlugin.cancelledIds,
          isNot(contains(todayRegularCall.id)),
        );
        expect(
          await service.analytics.getTodayPushCount(now: currentNow),
          equals(0),
        );

        // 用户直接点击保存但未改变提醒时间（futureOnly: false）时，仍有效的等待中通知不应被取消而漏发
        await service.saveSettings(
          const SmartPushSettings(
            enabled: true,
            pushMode: PushMode.smart,
            pushIntensity: PushIntensity.balanced,
            dailyQuotePushEnabled: true,
            dailyQuotePushTime: PushTimeSlot(
              hour: 8,
              minute: 0,
              label: '每日一言',
            ),
          ),
        );
        expect(
          notificationsPlugin.cancelledIds,
          isNot(contains(todayDailyCall.id)),
        );
        expect(
          notificationsPlugin.cancelledIds,
          isNot(contains(todayRegularCall.id)),
        );

        // 用户将提醒时间改到 07:00 / 07:15（新计划从次日开始，旧提醒已不符合新设置）
        await service.saveSettings(
          const SmartPushSettings(
            enabled: true,
            pushMode: PushMode.custom,
            pushTimeSlots: [
              PushTimeSlot(hour: 7, minute: 15, label: '晨间回顾'),
            ],
            dailyQuotePushEnabled: true,
            dailyQuotePushTime: PushTimeSlot(
              hour: 7,
              minute: 0,
              label: '每日一言',
            ),
          ),
        );

        expect(
          notificationsPlugin.cancelledIds,
          containsAll(<int>[todayDailyCall.id, todayRegularCall.id]),
        );
        final remainingPendingIds =
            (await notificationsPlugin.pendingNotificationRequests())
                .map((r) => r.id)
                .toSet();
        expect(remainingPendingIds, isNot(contains(todayDailyCall.id)));
        expect(remainingPendingIds, isNot(contains(todayRegularCall.id)));
        expect(
          await service.analytics.getTodayPushCount(now: currentNow),
          equals(0),
        );
      },
    );

    test(
      'overdue pending regular dailyQuote fallback reserves smart quota and prevents duplicate evening or gap-violating push',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        exactAlarmPermitted = false;
        databaseService.notes.clear();
        currentNow = localTime(2026, 5, 9, 22, 0);

        final service = createService();
        addTearDown(service.dispose);
        await service.initialize();

        await service.saveSettings(
          const SmartPushSettings(
            enabled: true,
            pushMode: PushMode.smart,
            pushIntensity: PushIntensity.rare,
            dailyQuotePushEnabled: false,
          ),
        );

        // 2026-05-09 22:00 仅应调度次日（5月10日）早晨一条回退通知（5月10日晚间受 dailyCap=1 抑制，5月11-12日受 minGapDays 抑制）
        final initialMay10Calls = notificationsPlugin.scheduledCalls
            .where(
              (c) =>
                  c.scheduledDate.year == 2026 &&
                  c.scheduledDate.month == 5 &&
                  c.scheduledDate.day == 10,
            )
            .toList();
        expect(initialMay10Calls, hasLength(1));
        final morningFallbackCall = initialMay10Calls.single;
        expect(morningFallbackCall.scheduledDate.hour, equals(8));

        // 推进到 5月10日 08:40（跨天超过节流窗口），早间回退通知仍等待系统送达
        currentNow = localTime(2026, 5, 10, 8, 40);
        notificationsPlugin.delayedPendingIds.add(morningFallbackCall.id);
        notificationsPlugin.scheduledCalls.clear();
        notificationsPlugin.cancelledIds.clear();
        final queriesBeforeResume = databaseService.queryCount;

        // 前台恢复真正执行对账（queryCount 递增），保留早间待送达回退通知并为其预留配额，绝不安排 5月10日 20:00 或违反最小间隔的 5月11日通知
        await service.handleAppResumed();
        expect(databaseService.queryCount, greaterThan(queriesBeforeResume));
        expect(
          notificationsPlugin.cancelledIds,
          isNot(contains(morningFallbackCall.id)),
        );
        expect(
          notificationsPlugin.scheduledCalls.where(
            (c) =>
                c.scheduledDate.year == 2026 &&
                c.scheduledDate.month == 5 &&
                (c.scheduledDate.day == 10 || c.scheduledDate.day == 11),
          ),
          isEmpty,
        );

        notificationsPlugin.scheduledCalls.clear();
        await service.saveSettings(service.settings);
        expect(
          notificationsPlugin.cancelledIds,
          isNot(contains(morningFallbackCall.id)),
        );
        expect(
          notificationsPlugin.scheduledCalls.where(
            (c) =>
                c.scheduledDate.year == 2026 &&
                c.scheduledDate.month == 5 &&
                (c.scheduledDate.day == 10 || c.scheduledDate.day == 11),
          ),
          isEmpty,
        );
      },
    );

    test(
      'headless background renewal resolves EDT daylight-saving zone instead of falling back to fixed UTC+8',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        final nyLocation = tz.getLocation('America/New_York');
        tz.setLocalLocation(nyLocation);
        currentNow = tz.TZDateTime(nyLocation, 2026, 7, 15, 7, 0);

        // Simulate headless WorkManager isolate: MethodChannel is unregistered (throws MissingPluginException)
        const tzChannel = MethodChannel('com.shangjin.thoughtecho/timezone');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(tzChannel, (call) async {
          throw MissingPluginException('No implementation in headless engine');
        });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(tzChannel, null);
        });

        await storage.setString(
          'smart_push_settings_v2',
          jsonEncode(
            const SmartPushSettings(
              enabled: false,
              dailyQuotePushEnabled: true,
              dailyQuotePushTime: PushTimeSlot(
                hour: 8,
                minute: 0,
                label: '每日一言',
              ),
            ).toJson(),
          ),
        );

        // Without any pre-synced storage key, EDT (-04:00) resolves to America/New_York (08:00 EDT == 12:00 UTC)
        final headlessService = SmartPushService(
          databaseService: databaseService,
          locationService: LocationService(),
          mmkvService: storage,
          notificationsPlugin: notificationsPlugin,
          isAndroidOverride: true,
          isIOSOverride: false,
          timeZoneOverride: null,
          localTimeZoneProbeOverride: () => (
            name: 'EDT',
            offset: const Duration(hours: -4),
          ),
          canScheduleExactAlarmsOverride: () async => true,
          registerPreScheduleRenewalOverride: () async {},
          cancelPreScheduleRenewalOverride: () async {},
          nowProvider: () => currentNow,
        );
        addTearDown(headlessService.dispose);

        await headlessService.loadSettingsForBackground();
        await headlessService.renewPreScheduledQueueFromBackground();

        expect(notificationsPlugin.scheduledCalls, hasLength(3));
        final first = notificationsPlugin.scheduledCalls.first;
        expect(first.scheduledDate.location.name, equals('America/New_York'));
        expect(first.scheduledDate.hour, equals(8));
        expect(first.scheduledDate.toUtc().hour, equals(12));
      },
    );

    test(
      'background delivery accounting paused between foreground settings write and epoch bump never overwrites disabled settings',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        final sharedDisk = <String, Object>{};
        final foregroundStorage = _MemoryPreferences(
          sharedDisk: sharedDisk,
          isolatedCache: true,
        );
        final backgroundStorage = _MemoryPreferences(
          sharedDisk: sharedDisk,
          isolatedCache: true,
        );

        final foregroundService = SmartPushService(
          databaseService: databaseService,
          locationService: LocationService(),
          mmkvService: foregroundStorage,
          notificationsPlugin: notificationsPlugin,
          isAndroidOverride: true,
          isIOSOverride: false,
          timeZoneOverride: 'Etc/GMT-8',
          canScheduleExactAlarmsOverride: () async => true,
          registerPreScheduleRenewalOverride: () async {},
          cancelPreScheduleRenewalOverride: () async {},
          nowProvider: () => currentNow,
        );
        addTearDown(foregroundService.dispose);

        await foregroundService.saveSettings(
          const SmartPushSettings(
            enabled: true,
            pushMode: PushMode.smart,
            pushIntensity: PushIntensity.balanced,
            dailyQuotePushEnabled: true,
          ),
        );
        expect(notificationsPlugin.scheduledCalls, isNotEmpty);

        // Advance past morning delivery so background renewal has an unaccounted due entry
        currentNow = localTime(2026, 5, 10, 10, 0);
        final backgroundService = SmartPushService(
          databaseService: databaseService,
          locationService: LocationService(),
          mmkvService: backgroundStorage,
          notificationsPlugin: notificationsPlugin,
          isAndroidOverride: true,
          isIOSOverride: false,
          timeZoneOverride: 'Etc/GMT-8',
          canScheduleExactAlarmsOverride: () async => true,
          registerPreScheduleRenewalOverride: () async {},
          cancelPreScheduleRenewalOverride: () async {},
          nowProvider: () => currentNow,
        );
        addTearDown(backgroundService.dispose);
        await backgroundStorage.reload();
        await backgroundService.loadSettingsForBackground();

        // 1. Pause foreground saveSettings immediately AFTER writing smart_push_settings_v2
        //    (turning off dailyQuotePushEnabled and switching pushMode to custom) and BEFORE
        //    _bumpSettingsEpoch() updates smart_push_settings_epoch_v1: background accounting
        //    actually executes and records lastPushTime into smart_push_delivery_history_v1
        //    without overwriting smart_push_settings_v2!
        var interceptedModifyWrite = false;
        foregroundStorage.onSetStringHook = (key, value) async {
          if (key == 'smart_push_settings_v2' &&
              value.contains('"dailyQuotePushEnabled":false') &&
              !interceptedModifyWrite) {
            interceptedModifyWrite = true;
            foregroundStorage.onSetStringHook = null;
            await backgroundService.renewPreScheduledQueueFromBackground();
          }
        };

        await foregroundService.saveSettings(
          const SmartPushSettings(
            enabled: true,
            pushMode: PushMode.custom,
            dailyQuotePushEnabled: false,
          ),
        );
        expect(interceptedModifyWrite, isTrue);

        // 2. Also disable all reminders on foreground while delivery history already exists
        await foregroundService.saveSettings(
          const SmartPushSettings(
            enabled: false,
            pushMode: PushMode.custom,
            dailyQuotePushEnabled: false,
          ),
        );

        // Next cold launch must read the foreground user settings intact plus merged delivery history
        final nextLaunchStorage = _MemoryPreferences(
          sharedDisk: sharedDisk,
          isolatedCache: true,
        );
        final nextLaunchService = SmartPushService(
          databaseService: databaseService,
          locationService: LocationService(),
          mmkvService: nextLaunchStorage,
          notificationsPlugin: notificationsPlugin,
          isAndroidOverride: true,
          isIOSOverride: false,
          timeZoneOverride: 'Etc/GMT-8',
          canScheduleExactAlarmsOverride: () async => true,
          registerPreScheduleRenewalOverride: () async {},
          cancelPreScheduleRenewalOverride: () async {},
          nowProvider: () => currentNow,
        );
        addTearDown(nextLaunchService.dispose);
        await nextLaunchService.initialize();

        expect(nextLaunchService.settings.enabled, isFalse);
        expect(nextLaunchService.settings.pushMode, equals(PushMode.custom));
        expect(nextLaunchService.settings.dailyQuotePushEnabled, isFalse);
        expect(nextLaunchService.settings.lastPushTime, isNotNull);
      },
    );

    test(
      'iOS standalone daily quote schedule fetches from configured online provider when local store is empty',
      () async {
        await storage.remove('smart_push_last_daily_quote');
        await storage.remove('smart_push_last_daily_quote_date');
        databaseService.notes.clear();
        databaseService.localDailyQuoteResult = null;
        await storage.setString(
          'app_settings',
          jsonEncode(
            AppSettings(
              useLocalQuotesOnly: false,
              dailyQuoteProvider: ApiService.hitokotoProvider,
            ).toJson(),
          ),
        );

        var providerCalls = 0;
        ApiService.debugIsConnectedOverride = true;
        ApiService.debugHttpGetOverride = (
          url, {
          headers,
          timeoutSeconds,
        }) async {
          providerCalls++;
          return HttpResponse(
            jsonEncode(<String, dynamic>{
              'hitokoto': '山高月小，水落石出。',
              'from_who': '古典文学作者',
              'from': '古典散文选',
              'type': 'i',
            }),
            200,
          );
        };

        final iosService = SmartPushService(
          databaseService: databaseService,
          locationService: LocationService(),
          mmkvService: storage,
          notificationsPlugin: notificationsPlugin,
          isAndroidOverride: false,
          isIOSOverride: true,
          timeZoneOverride: 'Etc/GMT-8',
          canScheduleExactAlarmsOverride: () async => true,
          registerPreScheduleRenewalOverride: () async {},
          cancelPreScheduleRenewalOverride: () async {},
          nowProvider: () => currentNow,
        );
        addTearDown(iosService.dispose);

        await iosService.saveSettings(
          const SmartPushSettings(
            enabled: false,
            dailyQuotePushEnabled: true,
            dailyQuotePushTime: PushTimeSlot(
              hour: 8,
              minute: 0,
              label: '每日一言',
            ),
          ),
        );

        expect(providerCalls, equals(1));
        expect(notificationsPlugin.scheduledCalls, hasLength(1));
        final iosCall = notificationsPlugin.scheduledCalls.single;
        expect(iosCall.id, equals(100));
        expect(iosCall.body, contains('山高月小，水落石出。'));
      },
    );

    test(
      'foreground handleAppResumed merges background-accounted delivery history and honors minGapDays',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        final sharedDisk = <String, Object>{};
        final foregroundStorage = _MemoryPreferences(
          sharedDisk: sharedDisk,
          isolatedCache: true,
        );
        final backgroundStorage = _MemoryPreferences(
          sharedDisk: sharedDisk,
          isolatedCache: true,
        );
        databaseService.notes = [
          Quote(
            id: '10101010-1111-2222-3333-444444444444',
            content: '跨进程投递历史同步验证第一条回顾笔记内容。',
            date: localTime(2025, 5, 10, 9, 0).toIso8601String(),
          ),
          Quote(
            id: '20202020-1111-2222-3333-444444444444',
            content: '跨进程投递历史同步验证第二条回顾笔记内容。',
            date: localTime(2025, 5, 11, 9, 0).toIso8601String(),
          ),
        ];

        final foregroundService = SmartPushService(
          databaseService: databaseService,
          locationService: LocationService(),
          mmkvService: foregroundStorage,
          notificationsPlugin: notificationsPlugin,
          isAndroidOverride: true,
          isIOSOverride: false,
          timeZoneOverride: 'Etc/GMT-8',
          canScheduleExactAlarmsOverride: () async => true,
          registerPreScheduleRenewalOverride: () async {},
          cancelPreScheduleRenewalOverride: () async {},
          nowProvider: () => currentNow,
        );
        addTearDown(foregroundService.dispose);
        await foregroundService.initialize();

        await foregroundService.saveSettings(
          const SmartPushSettings(
            enabled: true,
            pushMode: PushMode.smart,
            pushIntensity: PushIntensity.rare,
            dailyQuotePushEnabled: false,
          ),
        );
        expect(foregroundService.settings.lastPushTime, isNull);

        // Background worker runs on May 11 07:00, accounting for May 10's delivered reminder
        currentNow = localTime(2026, 5, 11, 7, 0);
        final backgroundService = SmartPushService(
          databaseService: databaseService,
          locationService: LocationService(),
          mmkvService: backgroundStorage,
          notificationsPlugin: notificationsPlugin,
          isAndroidOverride: true,
          isIOSOverride: false,
          timeZoneOverride: 'Etc/GMT-8',
          canScheduleExactAlarmsOverride: () async => true,
          registerPreScheduleRenewalOverride: () async {},
          cancelPreScheduleRenewalOverride: () async {},
          nowProvider: () => currentNow,
        );
        addTearDown(backgroundService.dispose);
        await backgroundStorage.reload();
        await backgroundService.loadSettingsForBackground();
        await backgroundService.renewPreScheduledQueueFromBackground();

        // Still-alive foreground instance resumes on May 11 07:05 without restarting
        notificationsPlugin.scheduledCalls.clear();
        currentNow = localTime(2026, 5, 11, 7, 5);
        await foregroundService.handleAppResumed();

        expect(foregroundService.settings.lastPushTime, isNotNull);
        expect(
          notificationsPlugin.scheduledCalls.where(
            (c) =>
                c.scheduledDate.year == 2026 &&
                c.scheduledDate.month == 5 &&
                c.scheduledDate.day == 11,
          ),
          isEmpty,
        );
      },
    );

    test(
      'independent daily quote and Smart Push fallback never deliver duplicate quote content on the same day',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        await storage.setString(
          'app_settings',
          jsonEncode(
            AppSettings(
              useLocalQuotesOnly: true,
              offlineQuoteSource: 'allNotes',
            ).toJson(),
          ),
        );

        // Case 1: Only a single today-created short quote exists (no past notes match) ->
        // independent daily quote claims it, and regular Smart Push fallback skips the duplicate.
        final singleQuote = Quote(
          id: '30303030-1111-2222-3333-444444444444',
          content: '今日新录入的唯一短句语录。',
          date: localTime(2026, 5, 10, 6, 0).toIso8601String(),
        );
        databaseService.notes = [singleQuote];
        databaseService.localDailyQuoteResult = <String, dynamic>{
          'content': singleQuote.content,
          'type': 'local',
          'local_quote_id': singleQuote.id,
        };
        databaseService.queryCount = 0;
        databaseService.localDailyQuoteQueryCount = 0;

        final service = createService();
        addTearDown(service.dispose);

        await service.saveSettings(
          const SmartPushSettings(
            enabled: true,
            pushMode: PushMode.smart,
            pushIntensity: PushIntensity.balanced,
            dailyQuotePushEnabled: true,
            dailyQuotePushTime: PushTimeSlot(
              hour: 8,
              minute: 0,
              label: '每日一言',
            ),
          ),
        );

        expect(databaseService.queryCount, lessThanOrEqualTo(1));
        expect(databaseService.localDailyQuoteQueryCount, lessThanOrEqualTo(1));
        final may10SingleCalls = notificationsPlugin.scheduledCalls
            .where(
              (c) =>
                  c.scheduledDate.year == 2026 &&
                  c.scheduledDate.month == 5 &&
                  c.scheduledDate.day == 10,
            )
            .toList();
        expect(may10SingleCalls, hasLength(1));
        expect(may10SingleCalls.single.body, contains(singleQuote.content));

        // Case 2: Two distinct short quotes exist -> independent daily quote and regular fallback pick distinct quotes!
        final secondQuote = Quote(
          id: '40404040-1111-2222-3333-444444444444',
          content: '今日新录入的第二条不同短句语录。',
          date: localTime(2026, 5, 10, 6, 5).toIso8601String(),
        );
        databaseService.notes = [singleQuote, secondQuote];
        notificationsPlugin.scheduledCalls.clear();
        databaseService.queryCount = 0;
        databaseService.localDailyQuoteQueryCount = 0;

        await service.scheduleNextPush();

        expect(databaseService.queryCount, lessThanOrEqualTo(1));
        expect(databaseService.localDailyQuoteQueryCount, lessThanOrEqualTo(1));
        final may10DualCalls = notificationsPlugin.scheduledCalls
            .where(
              (c) =>
                  c.scheduledDate.year == 2026 &&
                  c.scheduledDate.month == 5 &&
                  c.scheduledDate.day == 10,
            )
            .toList();
        expect(may10DualCalls, hasLength(2));
        expect(
          may10DualCalls.map((c) => c.body).toSet(),
          hasLength(2),
        );
      },
    );

    test(
      'DST fall-back 25-hour Sunday advances strictly by calendar date without repeating early reminders',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        final nyLocation = tz.getLocation('America/New_York');
        tz.setLocalLocation(nyLocation);
        // 2026-11-01 is US DST fall-back Sunday (25 hours). Start at 00:45 EDT after 00:30 reminder passed.
        currentNow = tz.TZDateTime(nyLocation, 2026, 11, 1, 0, 45);

        final dstService = SmartPushService(
          databaseService: databaseService,
          locationService: LocationService(),
          mmkvService: storage,
          notificationsPlugin: notificationsPlugin,
          isAndroidOverride: true,
          isIOSOverride: false,
          timeZoneOverride: 'America/New_York',
          canScheduleExactAlarmsOverride: () async => true,
          registerPreScheduleRenewalOverride: () async {},
          cancelPreScheduleRenewalOverride: () async {},
          nowProvider: () => currentNow,
        );
        addTearDown(dstService.dispose);

        await dstService.saveSettings(
          const SmartPushSettings(
            enabled: false,
            dailyQuotePushEnabled: true,
            dailyQuotePushTime: PushTimeSlot(
              hour: 0,
              minute: 30,
              label: '每日一言',
            ),
          ),
        );

        final dates = notificationsPlugin.scheduledCalls
            .map((c) => c.scheduledDate)
            .toList();
        expect(dates, hasLength(3));
        expect(
          dates
              .map(
                (d) =>
                    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
              )
              .toList(),
          equals(<String>['2026-11-02', '2026-11-03', '2026-11-04']),
        );
        expect(notificationsPlugin.scheduledCalls.map((c) => c.id).toSet(),
            hasLength(3));
      },
    );

    test(
      'active notification kept in shade past 7-day retention window is still cancelled when its note is hidden',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        final secretNote = Quote(
          id: '50505050-1111-2222-3333-444444444444',
          content: '超过七天仍停留在通知栏中的私密回顾笔记预览文本。',
          date: localTime(2025, 5, 10, 9, 0).toIso8601String(),
        );
        databaseService.notes = [secretNote];

        final service = createService();
        addTearDown(service.dispose);
        await service.initialize();

        await service.saveSettings(
          const SmartPushSettings(
            enabled: true,
            pushMode: PushMode.custom,
            pushTimeSlots: [
              PushTimeSlot(hour: 9, minute: 0, label: '晨间回顾'),
            ],
            dailyQuotePushEnabled: false,
          ),
        );

        final may10Call = notificationsPlugin.scheduledCalls.firstWhere(
          (c) =>
              c.scheduledDate.year == 2026 &&
              c.scheduledDate.month == 5 &&
              c.scheduledDate.day == 10,
        );

        // Simulate May 10 notification delivered and left unread in Android notification shade for 9 days
        notificationsPlugin.activeShadeIds.add(may10Call.id);
        currentNow = localTime(2026, 5, 19, 10, 0);
        await service.scheduleNextPush(preserveDeliveredNotifications: true);
        expect(
          notificationsPlugin.cancelledIds,
          isNot(contains(may10Call.id)),
        );
        expect(notificationsPlugin.activeShadeIds, contains(may10Call.id));

        // User now hides/deletes the note on Day 9 -> active notification must be cancelled from shade!
        databaseService.notes = [];
        databaseService.notifyChanged();
        await service.waitForPendingScheduleForTest();

        expect(notificationsPlugin.cancelledIds, contains(may10Call.id));
        expect(
          notificationsPlugin.activeShadeIds,
          isNot(contains(may10Call.id)),
        );
      },
    );

    test(
      'smart pre-schedule projects pending unread delivery into habituation cooldown without double-settling on refresh and resets on late click',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        currentNow = localTime(2026, 5, 10, 7, 30);

        // Seed active engagement tier (>= 4 open days in past week, all > 4h ago)
        storage.values['smart_push_app_open_times'] = <String>[
          localTime(2026, 5, 5, 9, 0).toIso8601String(),
          localTime(2026, 5, 6, 9, 0).toIso8601String(),
          localTime(2026, 5, 7, 9, 0).toIso8601String(),
          localTime(2026, 5, 8, 9, 0).toIso8601String(),
        ].join(',');

        // Simulate 3 settled unengaged deliveries + 1 unsettled pending delivery (4 unread total -> 72h cooldown)
        final fourthDeliveryTime = localTime(2026, 5, 9, 9, 0);
        const fourthNotificationId = 326050900;
        storage.values['smart_push_unengaged_streak'] = '3';
        storage.values['smart_push_pending_send'] =
            'yearAgoToday|0|$fourthNotificationId';

        final service = createService();
        addTearDown(service.dispose);
        await service.initialize();

        await service.saveSettings(
          SmartPushSettings(
            enabled: true,
            pushMode: PushMode.smart,
            pushIntensity: PushIntensity.frequent,
            dailyQuotePushEnabled: false,
            lastPushTime: fourthDeliveryTime,
          ),
        );

        // May 10 (23.5h-35h after May 9 09:00) and May 11 (47.5h-59h) are both inside the 72h 4-unread cooldown;
        // only May 12 (>= 72h after May 9 09:00) is eligible!
        expect(notificationsPlugin.scheduledCalls, isNotEmpty);
        for (final call in notificationsPlugin.scheduledCalls) {
          expect(
            call.scheduledDate.difference(fourthDeliveryTime),
            greaterThanOrEqualTo(const Duration(hours: 72)),
          );
        }

        // Refreshing again does NOT prematurely settle or double-increment the stored streak
        expect(await service.analytics.getUnengagedStreak(), equals(3));
        await service.scheduleNextPush(preserveDeliveredNotifications: true);
        expect(await service.analytics.getUnengagedStreak(), equals(3));

        // User late-clicks the 4th notification -> projected cooldown resets to 0h so May 10 slots are scheduled!
        await service.analytics.recordInteraction(
          'yearAgoToday',
          notificationId: fourthNotificationId,
        );
        notificationsPlugin.scheduledCalls.clear();
        await service.scheduleNextPush(preserveDeliveredNotifications: true);
        expect(
          notificationsPlugin.scheduledCalls.any(
            (c) =>
                c.scheduledDate.year == 2026 &&
                c.scheduledDate.month == 5 &&
                c.scheduledDate.day == 10,
          ),
          isTrue,
        );
      },
    );

    test(
      'cold launch with recordAppOpenOnLaunch records fresh visit before first smart schedule and suppresses slots inside 4-hour window',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        currentNow = localTime(2026, 5, 10, 7, 30);

        // Pre-populate active open days with both morning (08:xx) and evening (20:xx) activity
        storage.values['smart_push_app_open_times'] = <String>[
          localTime(2026, 5, 6, 8, 30).toIso8601String(),
          localTime(2026, 5, 6, 20, 0).toIso8601String(),
          localTime(2026, 5, 7, 8, 30).toIso8601String(),
          localTime(2026, 5, 7, 20, 0).toIso8601String(),
          localTime(2026, 5, 8, 8, 30).toIso8601String(),
          localTime(2026, 5, 8, 20, 0).toIso8601String(),
          localTime(2026, 5, 9, 20, 0).toIso8601String(),
        ].join(',');
        storage.values['smart_push_settings_v2'] = jsonEncode(
          const SmartPushSettings(
            enabled: true,
            pushMode: PushMode.smart,
            pushIntensity: PushIntensity.frequent,
            dailyQuotePushEnabled: false,
          ).toJson(),
        );

        final service = createService();
        addTearDown(service.dispose);
        await service.initialize(recordAppOpenOnLaunch: true);

        // Cold launch happened at May 10 07:30 -> any May 10 slot before 11:30 (4h window) MUST be suppressed,
        // while May 10 evening (>= 11:30) and May 11-12 morning slots ARE scheduled!
        final may10Calls = notificationsPlugin.scheduledCalls
            .where(
              (c) =>
                  c.scheduledDate.year == 2026 &&
                  c.scheduledDate.month == 5 &&
                  c.scheduledDate.day == 10,
            )
            .toList();
        expect(
          may10Calls.every(
            (c) =>
                c.scheduledDate.difference(currentNow) >=
                const Duration(hours: 4),
          ),
          isTrue,
        );
        expect(may10Calls, isNotEmpty);
      },
    );

    test(
      'smart pre-schedule ranks candidates by adjusted score before extraQualityFloor check while preserving base priority in custom mode',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        currentNow = localTime(2026, 5, 10, 7, 30);

        // Light engagement tier (1 open day > 4h ago, both morning & evening windows) + PushIntensity.frequent -> dailyCap: 2, extraQualityFloor: 70
        storage.values['smart_push_app_open_times'] = <String>[
          localTime(2026, 5, 8, 9, 0).toIso8601String(),
          localTime(2026, 5, 8, 20, 0).toIso8601String(),
        ].join(',');
        // Low engagement score on monthAgoToday (base 70 -> adjusted 64 < 70),
        // high engagement + favorites on weekAgoToday (base 55 + 8 + 16 = 79 >= 70)
        storage.values['smart_push_content_scores'] =
            'yearAgoToday:0.5;monthAgoToday:0.2;weekAgoToday:0.9';

        databaseService.notes = [
          Quote(
            id: '60606060-1111-2222-3333-444444444444',
            content: '一年前今日的晨间首发回顾笔记。',
            date: localTime(2025, 5, 10, 9, 0).toIso8601String(),
          ),
          Quote(
            id: '70707070-1111-2222-3333-444444444444',
            content: '一个月前今日但历史点击率较低的笔记。',
            date: localTime(2026, 4, 10, 9, 0).toIso8601String(),
            favoriteCount: 0,
          ),
          Quote(
            id: '80808080-1111-2222-3333-444444444444',
            content: '一周前今日且多次收藏与高互动的精选笔记。',
            date: localTime(2026, 5, 3, 9, 0).toIso8601String(),
            favoriteCount: 15,
          ),
        ];

        final service = createService();
        addTearDown(service.dispose);
        await service.initialize();

        await service.saveSettings(
          const SmartPushSettings(
            enabled: true,
            pushMode: PushMode.smart,
            pushIntensity: PushIntensity.frequent,
            dailyQuotePushEnabled: false,
          ),
        );

        final smartMay10Calls = notificationsPlugin.scheduledCalls
            .where(
              (c) =>
                  c.scheduledDate.year == 2026 &&
                  c.scheduledDate.month == 5 &&
                  c.scheduledDate.day == 10,
            )
            .toList();
        expect(smartMay10Calls, hasLength(2));
        expect(
          smartMay10Calls[0].payload,
          contains('noteId:60606060-1111-2222-3333-444444444444'),
        );
        expect(
          smartMay10Calls[1].payload,
          contains('noteId:80808080-1111-2222-3333-444444444444'),
        );

        // Switch to custom mode with only monthAgoToday + weekAgoToday -> base priority (70 > 55) still wins
        databaseService.notes = databaseService.notes.sublist(1);
        notificationsPlugin.scheduledCalls.clear();
        await service.saveSettings(
          const SmartPushSettings(
            enabled: true,
            pushMode: PushMode.custom,
            enabledPastNoteTypes: {
              PastNoteType.monthAgoToday,
              PastNoteType.weekAgoToday,
            },
            pushTimeSlots: [
              PushTimeSlot(hour: 9, minute: 0, label: '晨间'),
            ],
            dailyQuotePushEnabled: false,
          ),
        );
        final customMay10Call = notificationsPlugin.scheduledCalls.firstWhere(
          (c) =>
              c.scheduledDate.year == 2026 &&
              c.scheduledDate.month == 5 &&
              c.scheduledDate.day == 10,
        );
        expect(
          customMay10Call.payload,
          contains('noteId:70707070-1111-2222-3333-444444444444'),
        );
      },
    );

    test(
      'concurrent saveSettings never lets slower earlier enable overwrite newer disable or reschedule reminders',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        final service = createService();
        addTearDown(service.dispose);
        await service.initialize();

        final pauseFirstSave = Completer<void>();
        final firstSaveIntercepted = Completer<void>();
        var hookedOnce = false;
        storage.onSetStringHook = (key, value) async {
          if (!hookedOnce &&
              key == 'smart_push_settings_v2' &&
              value.contains('"enabled":true')) {
            hookedOnce = true;
            firstSaveIntercepted.complete();
            await pauseFirstSave.future;
          }
        };

        final firstSaveFuture = service.saveSettings(
          const SmartPushSettings(
            enabled: true,
            pushMode: PushMode.smart,
            pushIntensity: PushIntensity.balanced,
            dailyQuotePushEnabled: true,
          ),
        );

        await firstSaveIntercepted.future;
        storage.onSetStringHook = null;

        await service.saveSettings(
          const SmartPushSettings(
            enabled: false,
            pushMode: PushMode.smart,
            dailyQuotePushEnabled: false,
          ),
        );

        pauseFirstSave.complete();
        await firstSaveFuture;

        expect(service.settings.enabled, isFalse);
        expect(service.settings.dailyQuotePushEnabled, isFalse);
        final persisted = jsonDecode(
          storage.getString('smart_push_settings_v2')!,
        ) as Map<String, dynamic>;
        expect(persisted['enabled'], isFalse);
        expect(persisted['dailyQuotePushEnabled'], isFalse);
        expect(
            await notificationsPlugin.pendingNotificationRequests(), isEmpty);
        expect(renewalCancelCount, greaterThanOrEqualTo(1));
      },
    );

    test(
      'real SQLite DatabaseService.getQuotesForSmartPush loads quote_tags so tagOnly secondary quote schedules without duplication',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        final db = await databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(singleInstance: false),
        );
        await db.execute('''
          CREATE TABLE categories (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            is_default INTEGER DEFAULT 0,
            icon_name TEXT,
            last_modified TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE quotes (
            id TEXT PRIMARY KEY,
            content TEXT,
            date TEXT,
            source TEXT,
            source_author TEXT,
            source_work TEXT,
            category_id TEXT,
            color_hex TEXT,
            location TEXT,
            poi_name TEXT,
            latitude REAL,
            longitude REAL,
            weather TEXT,
            temperature REAL,
            edit_source TEXT,
            day_period TEXT,
            last_modified TEXT,
            favorite_count INTEGER,
            is_deleted INTEGER DEFAULT 0,
            deleted_at TEXT,
            delta_content TEXT,
            ai_analysis TEXT,
            summary TEXT,
            keywords TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE quote_tags (
            quote_id TEXT NOT NULL,
            tag_id TEXT NOT NULL,
            PRIMARY KEY (quote_id, tag_id)
          )
        ''');
        DatabaseService.setTestDatabase(db);
        final realDbService = DatabaseService.forTesting();
        await realDbService.init();
        addTearDown(() async {
          realDbService.dispose();
          if (db.isOpen) {
            await db.close();
          }
          DatabaseService.clearTestDatabase();
        });

        await db.insert('categories', <String, Object?>{
          'id': 'tag-daily-quote',
          'name': '每日一言',
          'is_default': 0,
        });
        await db.insert('quotes', <String, Object?>{
          'id': 'tagged-quote-1',
          'content': '带每日一言标签的第一条本地语录。',
          'date': localTime(2026, 5, 10, 6, 0).toIso8601String(),
          'is_deleted': 0,
        });
        await db.insert('quotes', <String, Object?>{
          'id': 'tagged-quote-2',
          'content': '带每日一言标签的第二条备选本地语录。',
          'date': localTime(2026, 5, 10, 6, 10).toIso8601String(),
          'is_deleted': 0,
        });
        await db.insert('quotes', <String, Object?>{
          'id': 'untagged-quote-3',
          'content': '未打标签的普通今日短句不应在tagOnly模式被选中。',
          'date': localTime(2026, 5, 10, 6, 20).toIso8601String(),
          'is_deleted': 0,
        });
        await db.insert('quote_tags', <String, Object?>{
          'quote_id': 'tagged-quote-1',
          'tag_id': 'tag-daily-quote',
        });
        await db.insert('quote_tags', <String, Object?>{
          'quote_id': 'tagged-quote-2',
          'tag_id': 'tag-daily-quote',
        });

        await storage.remove('smart_push_last_daily_quote');
        await storage.remove('smart_push_last_daily_quote_date');
        await storage.setString(
          'app_settings',
          jsonEncode(
            AppSettings(
              useLocalQuotesOnly: true,
              offlineQuoteSource: 'tagOnly',
            ).toJson(),
          ),
        );

        final loadedQuotes = await realDbService.getQuotesForSmartPush();
        final byId = <String, Quote>{
          for (final q in loadedQuotes)
            if (q.id != null) q.id!: q,
        };
        expect(byId['tagged-quote-1']?.tagIds, contains('tag-daily-quote'));
        expect(byId['tagged-quote-2']?.tagIds, contains('tag-daily-quote'));
        expect(byId['untagged-quote-3']?.tagIds, isEmpty);

        final service = SmartPushService(
          databaseService: realDbService,
          locationService: LocationService(),
          mmkvService: storage,
          notificationsPlugin: notificationsPlugin,
          isAndroidOverride: true,
          isIOSOverride: false,
          timeZoneOverride: 'Etc/GMT-8',
          canScheduleExactAlarmsOverride: () async => true,
          registerPreScheduleRenewalOverride: () async {},
          cancelPreScheduleRenewalOverride: () async {},
          nowProvider: () => currentNow,
        );
        addTearDown(service.dispose);

        await service.saveSettings(
          const SmartPushSettings(
            enabled: true,
            pushMode: PushMode.smart,
            pushIntensity: PushIntensity.balanced,
            dailyQuotePushEnabled: true,
            dailyQuotePushTime: PushTimeSlot(
              hour: 8,
              minute: 0,
              label: '每日一言',
            ),
          ),
        );

        final may10Calls = notificationsPlugin.scheduledCalls
            .where(
              (c) =>
                  c.scheduledDate.year == 2026 &&
                  c.scheduledDate.month == 5 &&
                  c.scheduledDate.day == 10,
            )
            .toList();
        expect(may10Calls, hasLength(2));
        expect(may10Calls.map((c) => c.body).toSet(), hasLength(2));
        for (final call in may10Calls) {
          expect(call.body, isNot(contains('未打标签的普通今日短句')));
        }
      },
    );

    test(
      'failed zonedSchedule does not record phantom tracked entries or consume quota and falls back from exact alarm exception',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        currentNow = localTime(2026, 5, 10, 7, 30);

        notificationsPlugin.scheduleErrorBuilder = (_) => PlatformException(
              code: 'NOTIFICATION_BLOCKED',
              message: 'OS rejected schedule request',
            );

        final service = createService();
        addTearDown(service.dispose);
        await service.initialize();

        await service.saveSettings(
          const SmartPushSettings(
            enabled: true,
            pushMode: PushMode.smart,
            pushIntensity: PushIntensity.balanced,
            dailyQuotePushEnabled: false,
          ),
        );

        expect(notificationsPlugin.scheduledCalls, isEmpty);
        final rawEntriesAfterFailure =
            storage.getString('smart_push_prescheduled_entries_v1');
        expect(
          rawEntriesAfterFailure == null
              ? const <Object?>[]
              : (jsonDecode(rawEntriesAfterFailure) as List<Object?>),
          isEmpty,
        );

        // Advance past morning slot time, restore OS scheduling, and verify zero phantom quota/cooldown was consumed
        currentNow = localTime(2026, 5, 10, 10, 0);
        notificationsPlugin.scheduleErrorBuilder = null;
        await service.scheduleNextPush();

        expect(service.settings.lastPushTime, isNull);
        expect(service.settings.recentlyPushedNoteIds, isEmpty);
        expect(storage.getString('smart_push_today_count'), isNull);
        expect(await service.analytics.getUnengagedStreak(), equals(0));
        expect(
          notificationsPlugin.scheduledCalls.any(
            (c) =>
                c.scheduledDate.year == 2026 &&
                c.scheduledDate.month == 5 &&
                c.scheduledDate.day == 10,
          ),
          isTrue,
        );

        // Exact alarm race: canScheduleExactAlarmsOverride returned true, but zonedSchedule throws exact_alarms_not_permitted
        notificationsPlugin.scheduledCalls.clear();
        await notificationsPlugin.cancelAll();
        exactAlarmPermitted = true;
        notificationsPlugin.scheduleErrorBuilder = (call) {
          if (call.androidScheduleMode ==
              AndroidScheduleMode.exactAllowWhileIdle) {
            return PlatformException(
              code: 'exact_alarms_not_permitted',
              message: 'Exact alarms revoked concurrently',
            );
          }
          return null;
        };

        await service.scheduleNextPush();
        expect(notificationsPlugin.scheduledCalls, isNotEmpty);
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
      'smart 3-day planner advances projected habituation cooldown across future unclicked slots and unlocks after interaction',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        currentNow = localTime(2026, 5, 10, 7, 30);

        // Active engagement tier (>= 4 open days in past week, all > 4h ago) with morning & evening habits
        storage.values['smart_push_app_open_times'] = <String>[
          localTime(2026, 5, 5, 8, 30).toIso8601String(),
          localTime(2026, 5, 5, 20, 0).toIso8601String(),
          localTime(2026, 5, 6, 8, 30).toIso8601String(),
          localTime(2026, 5, 6, 20, 0).toIso8601String(),
          localTime(2026, 5, 7, 8, 30).toIso8601String(),
          localTime(2026, 5, 7, 20, 0).toIso8601String(),
          localTime(2026, 5, 8, 8, 30).toIso8601String(),
          localTime(2026, 5, 8, 20, 0).toIso8601String(),
        ].join(',');
        storage.values['smart_push_unengaged_streak'] = '2';

        databaseService.notes = <Quote>[
          Quote(
            id: '91000000-1111-2222-3333-444444444444',
            content: '五月十日第一条高分历史回顾笔记。',
            date: localTime(2025, 5, 10, 9, 0).toIso8601String(),
            favoriteCount: 12,
          ),
          Quote(
            id: '92000000-1111-2222-3333-444444444444',
            content: '五月十日第二条高分月度回顾笔记。',
            date: localTime(2026, 4, 10, 20, 0).toIso8601String(),
            favoriteCount: 15,
          ),
          Quote(
            id: '93000000-1111-2222-3333-444444444444',
            content: '五月十一日第一条高分历史回顾笔记。',
            date: localTime(2025, 5, 11, 9, 0).toIso8601String(),
            favoriteCount: 12,
          ),
          Quote(
            id: '94000000-1111-2222-3333-444444444444',
            content: '五月十一日第二条高分月度回顾笔记。',
            date: localTime(2026, 4, 11, 20, 0).toIso8601String(),
            favoriteCount: 15,
          ),
          Quote(
            id: '95000000-1111-2222-3333-444444444444',
            content: '五月十二日第一条高分历史回顾笔记。',
            date: localTime(2025, 5, 12, 9, 0).toIso8601String(),
            favoriteCount: 12,
          ),
        ];

        final prevDelivery = localTime(2026, 5, 9, 20, 0);
        final service = createService();
        addTearDown(service.dispose);
        await service.initialize();

        await service.saveSettings(
          SmartPushSettings(
            enabled: true,
            pushMode: PushMode.smart,
            pushIntensity: PushIntensity.frequent,
            dailyQuotePushEnabled: false,
            lastPushTime: prevDelivery,
          ),
        );

        final initialCalls = List<_ScheduledCall>.from(
          notificationsPlugin.scheduledCalls,
        )..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));

        // 1. Streak=2 (8h cooldown): May 10 morning (>8h after May 9 20:00) is accepted -> projected streak becomes 3 (24h cooldown)
        // 2. May 10 evening (~11.5h after May 10 morning < 24h) MUST be skipped!
        final may10Calls = initialCalls
            .where(
              (c) =>
                  c.scheduledDate.year == 2026 &&
                  c.scheduledDate.month == 5 &&
                  c.scheduledDate.day == 10,
            )
            .toList();
        expect(may10Calls, hasLength(1));

        // 3. If a second slot is scheduled in the 3-day window, it must respect >= 24h after May 10 morning,
        //    and any third slot would require >= 72h (projected streak=4), so at most 2 slots fit in 3 days!
        expect(initialCalls.length, inInclusiveRange(1, 2));
        if (initialCalls.length == 2) {
          expect(
            initialCalls[1]
                .scheduledDate
                .difference(initialCalls[0].scheduledDate),
            greaterThanOrEqualTo(const Duration(hours: 24)),
          );
        }

        // Simulate May 10 morning firing and user clicking it -> streak resets to 0 so May 10 evening is unlocked!
        currentNow = may10Calls.single.scheduledDate.add(
          const Duration(minutes: 15),
        );
        await service.analytics.recordInteraction(
          'yearAgoToday',
          notificationId: may10Calls.single.id,
        );
        notificationsPlugin.scheduledCalls.clear();
        await service.scheduleNextPush(preserveDeliveredNotifications: true);

        expect(
          notificationsPlugin.scheduledCalls.any(
            (c) =>
                c.scheduledDate.year == 2026 &&
                c.scheduledDate.month == 5 &&
                c.scheduledDate.day == 10 &&
                c.scheduledDate.isAfter(currentNow),
          ),
          isTrue,
        );
      },
    );

    test(
      'background renewal racing with foreground hiding a note rolls back hidden content and keeps replacement visible note',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        currentNow = localTime(2026, 5, 10, 7, 30);

        final sharedDisk = <String, Object>{};
        final fgStorage = _MemoryPreferences(
          sharedDisk: sharedDisk,
          isolatedCache: true,
        );
        final bgStorage = _MemoryPreferences(
          sharedDisk: sharedDisk,
          isolatedCache: true,
        );

        final secretNote = Quote(
          id: 'a1a1a1a1-1111-2222-3333-444444444444',
          content: '已被用户设为私密隐藏、绝不允许被后台续期写入通知栏的正文。',
          date: localTime(2025, 5, 10, 9, 0).toIso8601String(),
        );
        final replacementNote = Quote(
          id: 'b2b2b2b2-1111-2222-3333-444444444444',
          content: '隐藏私密笔记后仍保持公开可见的替代回顾笔记正文。',
          date: localTime(2026, 4, 10, 9, 0).toIso8601String(),
        );
        databaseService.notes = <Quote>[secretNote, replacementNote];

        SmartPushService buildIsolatedService(_MemoryPreferences prefs) {
          return SmartPushService(
            databaseService: databaseService,
            locationService: LocationService(),
            mmkvService: prefs,
            notificationsPlugin: notificationsPlugin,
            isAndroidOverride: true,
            isIOSOverride: false,
            timeZoneOverride: 'Etc/GMT-8',
            canScheduleExactAlarmsOverride: () async => true,
            registerPreScheduleRenewalOverride: () async {},
            cancelPreScheduleRenewalOverride: () async {},
            nowProvider: () => currentNow,
          );
        }

        final fgService = buildIsolatedService(fgStorage);
        final bgService = buildIsolatedService(bgStorage);
        addTearDown(fgService.dispose);
        addTearDown(bgService.dispose);

        await fgService.initialize();
        await fgService.saveSettings(
          const SmartPushSettings(
            enabled: true,
            pushMode: PushMode.custom,
            enabledPastNoteTypes: {
              PastNoteType.yearAgoToday,
              PastNoteType.monthAgoToday,
              PastNoteType.randomMemory,
            },
            pushTimeSlots: [
              PushTimeSlot(hour: 9, minute: 0, label: '晨间回顾'),
            ],
            dailyQuotePushEnabled: false,
          ),
        );

        await bgService.loadSettingsForBackground();

        // 当后台刚把包含旧 secretNote 正文的预计算通知写入系统队列时，前台将 secretNote 隐藏并完成重排
        var hidDuringBackgroundWrite = false;
        notificationsPlugin.onScheduleHook = (call) async {
          if (!hidDuringBackgroundWrite &&
              (call.body?.contains(secretNote.content) ?? false)) {
            hidDuringBackgroundWrite = true;
            notificationsPlugin.onScheduleHook = null;
            databaseService.notes = <Quote>[replacementNote];
            databaseService.notifyChanged();
            await fgService.waitForPendingScheduleForTest();
          }
        };

        await bgService.renewPreScheduledQueueFromBackground();
        expect(hidDuringBackgroundWrite, isTrue);

        final pendingAfterRace =
            await notificationsPlugin.pendingNotificationRequests();
        expect(pendingAfterRace, isNotEmpty);
        for (final req in pendingAfterRace) {
          expect(req.body, isNot(contains(secretNote.content)));
          expect(req.payload, isNot(contains(secretNote.id!)));
        }
        expect(
          pendingAfterRace.any(
            (req) => req.body?.contains(replacementNote.content) ?? false,
          ),
          isTrue,
        );

        // 若隐藏后已无任何可见笔记，后台并发续期同样必须彻底撤回，不留任何隐藏正文
        databaseService.notes = <Quote>[secretNote];
        databaseService.notifyChanged();
        await fgService.waitForPendingScheduleForTest();

        var hidLastNoteDuringWrite = false;
        notificationsPlugin.onScheduleHook = (call) async {
          if (!hidLastNoteDuringWrite &&
              (call.body?.contains(secretNote.content) ?? false)) {
            hidLastNoteDuringWrite = true;
            notificationsPlugin.onScheduleHook = null;
            databaseService.notes = const <Quote>[];
            databaseService.notifyChanged();
            await fgService.waitForPendingScheduleForTest();
          }
        };

        await bgService.renewPreScheduledQueueFromBackground();
        expect(hidLastNoteDuringWrite, isTrue);
        expect(
          await notificationsPlugin.pendingNotificationRequests(),
          isEmpty,
        );
      },
    );

    test(
      'warm-start notification tap bypasses 6-hour resume throttle and immediately restores skipped evening reminder',
      () async {
        DistributionConfig.debugChannelOverride = DistributionChannel.play;
        currentNow = localTime(2026, 5, 10, 7, 30);

        storage.values['smart_push_app_open_times'] = <String>[
          localTime(2026, 5, 5, 8, 30).toIso8601String(),
          localTime(2026, 5, 5, 20, 0).toIso8601String(),
          localTime(2026, 5, 6, 8, 30).toIso8601String(),
          localTime(2026, 5, 6, 20, 0).toIso8601String(),
          localTime(2026, 5, 7, 8, 30).toIso8601String(),
          localTime(2026, 5, 7, 20, 0).toIso8601String(),
          localTime(2026, 5, 8, 8, 30).toIso8601String(),
          localTime(2026, 5, 8, 20, 0).toIso8601String(),
        ].join(',');
        storage.values['smart_push_unengaged_streak'] = '2';

        databaseService.notes = <Quote>[
          Quote(
            id: 'c1000000-1111-2222-3333-444444444444',
            content: '五月十日早间待点击的高分历史回顾笔记。',
            date: localTime(2025, 5, 10, 9, 0).toIso8601String(),
            favoriteCount: 12,
          ),
          Quote(
            id: 'c2000000-1111-2222-3333-444444444444',
            content: '五月十日晚间在点击早间提醒后应自动恢复的高分笔记。',
            date: localTime(2026, 4, 10, 20, 0).toIso8601String(),
            favoriteCount: 15,
          ),
          Quote(
            id: 'c3000000-1111-2222-3333-444444444444',
            content: '五月十一日备用高分历史回顾笔记。',
            date: localTime(2025, 5, 11, 9, 0).toIso8601String(),
            favoriteCount: 12,
          ),
        ];

        final service = createService();
        addTearDown(service.dispose);
        await service.initialize();

        await service.saveSettings(
          SmartPushSettings(
            enabled: true,
            pushMode: PushMode.smart,
            pushIntensity: PushIntensity.frequent,
            dailyQuotePushEnabled: false,
            lastPushTime: localTime(2026, 5, 9, 20, 0),
          ),
        );

        final may10BeforeTap = notificationsPlugin.scheduledCalls
            .where(
              (c) =>
                  c.scheduledDate.year == 2026 &&
                  c.scheduledDate.month == 5 &&
                  c.scheduledDate.day == 10,
            )
            .toList();
        // 因预计第 3 次未点击触发 24h 冷却，当晚槽位最初被跳过，当天仅排入早间 1 条
        expect(may10BeforeTap, hasLength(1));
        final morningCall = may10BeforeTap.single;
        expect(morningCall.scheduledDate.hour, lessThan(12));

        // 推进到早间通知送达后 15 分钟（距上次刷新不足 2 小时，处于 handleAppResumed 6 小时节流窗口内）
        currentNow = morningCall.scheduledDate.add(
          const Duration(minutes: 15),
        );
        notificationsPlugin.scheduledCalls.clear();
        await service.handleAppResumed();
        expect(notificationsPlugin.scheduledCalls, isEmpty);

        // 用户暖启动点击早间通知 -> 应突破 6 小时节流立即重排并恢复当晚提醒槽位
        await service.handleNotificationTapForTest(
          NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            id: morningCall.id,
            payload: morningCall.payload,
          ),
        );

        expect(await service.analytics.getUnengagedStreak(), equals(0));
        final restoredTonightCalls = notificationsPlugin.scheduledCalls
            .where(
              (c) =>
                  c.scheduledDate.year == 2026 &&
                  c.scheduledDate.month == 5 &&
                  c.scheduledDate.day == 10 &&
                  c.scheduledDate.isAfter(currentNow),
            )
            .toList();
        expect(restoredTonightCalls, hasLength(1));
        expect(restoredTonightCalls.single.scheduledDate.hour,
            greaterThanOrEqualTo(18));
      },
    );
  });
}
