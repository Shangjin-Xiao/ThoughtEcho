import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
  final List<_ShownCall> shownCalls = [];
  final List<int> cancelledIds = [];
  int cancelAllCount = 0;
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
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCount++;
    _activeScheduledById.clear();
    delayedPendingIds.clear();
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
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
  });

  tearDown(DistributionConfig.resetDebugOverrides);

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
        timeZoneOverride: 'Asia/Shanghai',
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
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
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
      'Android manifests keep ScheduledNotificationReceiver registered across main and play flavors',
      () {
        final mainManifest = File(
          'android/app/src/main/AndroidManifest.xml',
        ).readAsStringSync();
        final playManifest = File(
          'android/app/src/play/AndroidManifest.xml',
        ).readAsStringSync();

        expect(
          mainManifest,
          contains(
            'com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver',
          ),
        );
        expect(
          playManifest.contains(
            'com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver',
          ),
          isFalse,
          reason:
              'Play overlay manifest must not strip ScheduledNotificationReceiver via tools:node="remove"',
        );
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
        currentNow = DateTime.fromMillisecondsSinceEpoch(
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
        currentNow = localTime(2026, 5, 10, 7, 30);

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

        // 模拟无精确闹钟下已过计划时间（08:35 > 08:00 / 08:30），但系统尚未送达这两条通知
        currentNow = localTime(2026, 5, 10, 8, 35);
        notificationsPlugin.delayedPendingIds
          ..add(todayDailyCall.id)
          ..add(todayRegularCall.id);
        notificationsPlugin.cancelledIds.clear();

        // 仅回到前台（futureOnly: true）时应保留待系统送达的延迟通知，且不提前误计入今日已送达配额
        await service.handleAppResumed();
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

        // 用户将提醒时间改到 07:00 / 07:15（新计划从次日开始，不再包含今日旧 ID）
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
  });
}
