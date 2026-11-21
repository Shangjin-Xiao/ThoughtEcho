import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/smart_push_settings.dart';
import 'package:thoughtecho/services/app_preferences_service.dart';
import 'package:thoughtecho/services/smart_push_analytics.dart';
import 'package:thoughtecho/utils/platform_helper.dart';

import '../../test_harness.dart';

class _IsolatedAnalyticsPreferences implements AppPreferencesService {
  final Map<String, Object> _sharedDisk;
  final Map<String, Object> _cache;
  Future<void> Function(String key, String value)? onBeforeSetString;

  _IsolatedAnalyticsPreferences(this._sharedDisk)
      : _cache = Map<String, Object>.from(_sharedDisk);

  @override
  Future<void> reload() async {
    _cache
      ..clear()
      ..addAll(_sharedDisk);
  }

  @override
  String? getString(String key) => _cache[key] as String?;

  @override
  Future<bool> setString(String key, String value) async {
    if (onBeforeSetString != null) {
      await onBeforeSetString!(key, value);
    }
    _cache[key] = value;
    _sharedDisk[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    _cache.remove(key);
    _sharedDisk.remove(key);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SmartPushAnalytics analytics;
  late AppPreferencesService mmkvService;

  setUpAll(() async {
    await TestHarness.initialize();
    await AppPreferencesService().init();
  });

  setUp(() async {
    mmkvService = AppPreferencesService();
    await mmkvService.clear();
    analytics = SmartPushAnalytics(mmkvService: mmkvService);
  });

  group('SmartPushAnalytics.recordAppOpen', () {
    test('appends new record representing current time to MMKV storage',
        () async {
      await analytics.recordAppOpen();

      final recordsStr = mmkvService.getString('smart_push_app_open_times');
      expect(recordsStr, isNotNull);
      expect(recordsStr, isNotEmpty);

      final records =
          recordsStr!.split(',').where((s) => s.isNotEmpty).toList();
      expect(records.length, 1);

      // Should be parseable as DateTime
      final parsedDate = DateTime.tryParse(records.first);
      expect(parsedDate, isNotNull);
    });

    test('maintains max limit of records by removing oldest', () async {
      final maxRecords = SmartPushAnalytics.maxAppOpenRecords;

      // Create max number of fake records
      final fakeRecords = List.generate(maxRecords,
          (i) => DateTime(2023, 1, 1).add(Duration(days: i)).toIso8601String());
      await mmkvService.setString(
          'smart_push_app_open_times', fakeRecords.join(','));

      await analytics.recordAppOpen();

      final updatedRecordsStr =
          mmkvService.getString('smart_push_app_open_times');
      final updatedRecords =
          updatedRecordsStr!.split(',').where((s) => s.isNotEmpty).toList();

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
          'smart_push_app_open_times', 'corrupted_data_without_datetime');

      await analytics.recordAppOpen();

      final updatedRecordsStr =
          mmkvService.getString('smart_push_app_open_times');
      final updatedRecords =
          updatedRecordsStr!.split(',').where((s) => s.isNotEmpty).toList();

      // Currently, _getAppOpenRecords simply returns the split strings, so 'corrupted_data_without_datetime' will still be there.
      // And the new DateTime string will be added.
      expect(updatedRecords.length, 2);
      expect(updatedRecords.first, 'corrupted_data_without_datetime');

      final parsedDate = DateTime.tryParse(updatedRecords.last);
      expect(parsedDate, isNotNull);
    });
  });

  /// 把最近 [days] 天里的 [openDays] 天写成 App 打开记录
  Future<void> seedAppOpens(int openDays) async {
    final now = DateTime.now();
    final records = <String>[];
    for (int i = 0; i < openDays; i++) {
      // 往回铺，且减 1 小时避免落在未来
      records.add(now.subtract(Duration(days: i, hours: 1)).toIso8601String());
    }
    await mmkvService.setString('smart_push_app_open_times', records.join(','));
  }

  group('参与度分档', () {
    test('7 天内打开过 4 天算活跃', () async {
      await seedAppOpens(4);
      expect(await analytics.getEngagementTier(), EngagementTier.active);
    });

    test('7 天内打开过 1-3 天算轻度', () async {
      await seedAppOpens(2);
      expect(await analytics.getEngagementTier(), EngagementTier.light);
    });

    test('7 天内一次没开算沉睡', () async {
      final old = DateTime.now().subtract(const Duration(days: 20));
      await mmkvService.setString(
          'smart_push_app_open_times', old.toIso8601String());
      expect(await analytics.getEngagementTier(), EngagementTier.dormant);
    });

    test('同一天开很多次只算一天，不会被刷成活跃', () async {
      final now = DateTime.now().subtract(const Duration(hours: 6));
      final records = List.generate(
        10,
        (i) => now.subtract(Duration(minutes: i * 5)).toIso8601String(),
      );
      await mmkvService.setString(
          'smart_push_app_open_times', records.join(','));
      expect(await analytics.getEngagementTier(), EngagementTier.light);
    });
  });

  group('配额闸门', () {
    /// 造一个「沉睡且很久没打开」的基线，免得撞上刚打开 App 的抑制
    Future<void> seedDormant() async {
      final old = DateTime.now().subtract(const Duration(days: 30));
      await mmkvService.setString(
          'smart_push_app_open_times', old.toIso8601String());
    }

    test('沉睡用户在最小间隔内被拦下', () async {
      await seedDormant();
      final allowance = await analytics.checkPushAllowance(
        intensity: PushIntensity.balanced,
        lastPushTime: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(allowance.allowed, isFalse);
      expect(allowance.tier, EngagementTier.dormant);
      expect(allowance.reason, contains('最小间隔'));
    });

    test('沉睡用户过了 3 天间隔后放行', () async {
      await seedDormant();
      final allowance = await analytics.checkPushAllowance(
        intensity: PushIntensity.balanced,
        lastPushTime: DateTime.now().subtract(const Duration(days: 4)),
      );
      expect(allowance.allowed, isTrue);
      expect(allowance.profile.dailyCap, 1);
    });

    test('今日配额用尽后拦下', () async {
      await seedDormant();
      await analytics.markSent('yearAgoToday');

      final allowance = await analytics.checkPushAllowance(
        intensity: PushIntensity.balanced,
        lastPushTime: DateTime.now().subtract(const Duration(days: 10)),
      );
      expect(allowance.allowed, isFalse);
      expect(allowance.reason, contains('配额已用尽'));
    });

    test('刚打开过 App 就跳过本次推送', () async {
      await analytics.recordAppOpen();
      final allowance = await analytics.checkPushAllowance(
        intensity: PushIntensity.frequent,
        lastPushTime: DateTime.now().subtract(const Duration(days: 10)),
      );
      expect(allowance.allowed, isFalse);
      expect(allowance.reason, contains('刚用过 App'));
    });

    test('活跃 + 适中档：第一条无门槛，第二条要过质量门槛', () async {
      // 活跃但最近 5 小时没开，绕开刚打开抑制
      final now = DateTime.now();
      final records = List.generate(
        4,
        (i) => now.subtract(Duration(days: i, hours: 6)).toIso8601String(),
      );
      await mmkvService.setString(
          'smart_push_app_open_times', records.join(','));

      final first = await analytics.checkPushAllowance(
        intensity: PushIntensity.balanced,
        lastPushTime: now.subtract(const Duration(days: 1)),
      );
      expect(first.tier, EngagementTier.active);
      expect(first.allowed, isTrue);
      expect(first.qualityFloor, 0);

      await analytics.markSent('yearAgoToday');

      final second = await analytics.checkPushAllowance(
        intensity: PushIntensity.balanced,
        lastPushTime: now.subtract(const Duration(days: 1)),
      );
      expect(second.allowed, isTrue);
      expect(second.qualityFloor, 85);
    });

    test('拨盘只放宽上限，不会突破连续未点击的降级', () async {
      // 用活跃档：沉睡档的最小间隔会先拦下，测不到这里想验的降级。
      // 打开记录都放在 6 小时前，绕开「刚用过 App」抑制。
      final now = DateTime.now();
      final records = List.generate(
        4,
        (i) => now.subtract(Duration(days: i, hours: 6)).toIso8601String(),
      );
      await mmkvService.setString(
          'smart_push_app_open_times', records.join(','));

      // 连续 3 次未点击 → 24 小时冷却。
      // 直接种计数：走 markSent 会把当日配额一并吃掉，
      // 那样先命中的是配额闸门。
      await mmkvService.setString('smart_push_unengaged_streak', '3');
      expect(await analytics.getUnengagedStreak(), 3);

      final allowance = await analytics.checkPushAllowance(
        intensity: PushIntensity.frequent, // 拨到最右
        lastPushTime: DateTime.now().subtract(const Duration(hours: 2)),
      );
      expect(allowance.allowed, isFalse);
      expect(allowance.reason, contains('未点击'));
    });
  });

  group('结算闭环', () {
    test('未点击时连续计数累加，冷却阶梯跟着抬高', () async {
      expect(await analytics.getHabituationCooldown(), Duration.zero);

      await analytics.markSent('monthAgoToday');
      await analytics.settlePendingSend();
      expect(await analytics.getUnengagedStreak(), 1);
      expect(
          await analytics.getHabituationCooldown(), const Duration(hours: 2));

      await analytics.markSent('monthAgoToday');
      await analytics.settlePendingSend();
      expect(
          await analytics.getHabituationCooldown(), const Duration(hours: 8));
    });

    test('点一次立刻复位', () async {
      await analytics.markSent('monthAgoToday');
      await analytics.settlePendingSend();
      await analytics.markSent('monthAgoToday');
      await analytics.settlePendingSend();
      expect(await analytics.getUnengagedStreak(), 2);

      await analytics.markSent('yearAgoToday');
      await analytics.recordInteraction('yearAgoToday');
      await analytics.settlePendingSend();

      expect(await analytics.getUnengagedStreak(), 0);
      expect(await analytics.getHabituationCooldown(), Duration.zero);
    });

    test('点击过的内容类型分数上升，没点的下降', () async {
      await analytics.markSent('yearAgoToday');
      await analytics.recordInteraction('yearAgoToday');
      await analytics.settlePendingSend();

      await analytics.markSent('sameTimeOfDay');
      await analytics.settlePendingSend();

      final scores = await analytics.getContentTypeScores();
      expect(scores['yearAgoToday']! > 0.5, isTrue);
      expect(scores['sameTimeOfDay']! < 0.5, isTrue);
    });

    test('结算只消费一次，重复调用不会继续累加', () async {
      await analytics.markSent('monthAgoToday');
      await analytics.settlePendingSend();
      await analytics.settlePendingSend();
      await analytics.settlePendingSend();

      expect(await analytics.getUnengagedStreak(), 1);
    });

    test('今日推送计数跨天归零', () async {
      await analytics.markSent('yearAgoToday');
      expect(await analytics.getTodayPushCount(), 1);

      await mmkvService.setString('smart_push_daily_count', '2020-01-01|3');
      expect(await analytics.getTodayPushCount(), 0);
    });

    test('无 notificationId 的待结算记录在收到带 response.id 的点击时仍正确结算为已点击', () async {
      await mmkvService.setString('smart_push_unengaged_streak', '2');

      await analytics.markSent('yearAgoToday');
      await analytics.recordInteraction(
        'yearAgoToday',
        notificationId: 43210,
      );
      await analytics.settlePendingSend();

      expect(await analytics.getUnengagedStreak(), 0);
      expect(await analytics.getHabituationCooldown(), Duration.zero);
      final scores = await analytics.getContentTypeScores();
      expect(scores['yearAgoToday'], closeTo(2 / 3, 1e-6));
    });

    test('同一通知发送实例重复调用 markSent 保持幂等，不重复累加今日配额', () async {
      final sentAt = DateTime(2026, 5, 10, 9, 0);
      await analytics.markSent(
        'yearAgoToday',
        sentAt: sentAt,
        notificationId: 126051000,
      );
      await analytics.markSent(
        'yearAgoToday',
        sentAt: sentAt,
        notificationId: 126051000,
      );

      expect(await analytics.getTodayPushCount(now: sentAt), 1);

      // 重试期间若发生预点击补记，同样只计 1 次发送并升级为已点击
      await analytics.recordInteraction(
        'yearAgoToday',
        notificationId: 126051000,
        deferScoreUntilAccounted: true,
      );
      await analytics.markSent(
        'yearAgoToday',
        sentAt: sentAt,
        notificationId: 126051000,
      );
      await analytics.settlePendingSend();

      expect(await analytics.getTodayPushCount(now: sentAt), 1);
      expect(await analytics.getUnengagedStreak(), 0);
      final stats = await analytics.getAnalyticsStats();
      expect(stats['totalNotificationsSent'], 1);
      expect(stats['totalEngagements'], 1);
    });

    test('新通知复用历史已点击通知 ID 时不会继承旧点击状态', () async {
      final t1 = DateTime(2026, 5, 10, 9, 0);
      final t2 = DateTime(2026, 5, 10, 15, 0);

      await analytics.markSent(
        'yearAgoToday',
        sentAt: t1,
        notificationId: 77777,
      );
      await analytics.recordInteraction(
        'yearAgoToday',
        notificationId: 77777,
      );
      await analytics.settlePendingSend();
      expect(await analytics.getUnengagedStreak(), 0);

      // 新一轮发送即使落到同一通知 ID，未点击时也必须按未点击结算
      await analytics.markSent(
        'pastNote',
        sentAt: t2,
        notificationId: 77777,
      );
      expect(await analytics.getTodayPushCount(now: t2), 2);
      await analytics.settlePendingSend();

      expect(await analytics.getUnengagedStreak(), 1);
      final scores = await analytics.getContentTypeScores();
      expect(scores['pastNote'], closeTo(1 / 3, 1e-6));
    });

    test('前台点击结算与后台补记在独立缓存实例上并发交错时不会把真实点击覆盖为未点击', () async {
      final sharedDisk = <String, Object>{
        'smart_push_unengaged_streak': '2',
      };
      final fgPrefs = _IsolatedAnalyticsPreferences(sharedDisk);
      final bgPrefs = _IsolatedAnalyticsPreferences(sharedDisk);
      final tempDir = await Directory.systemTemp.createTemp(
        'smart_push_analytics_lock_test_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });
      final lockPath = '${tempDir.path}/analytics.lock';

      final fgAnalytics = SmartPushAnalytics(
        mmkvService: fgPrefs,
        lockFilePathOverride: lockPath,
      );
      final bgAnalytics = SmartPushAnalytics(
        mmkvService: bgPrefs,
        lockFilePathOverride: lockPath,
      );

      final sentAt = DateTime(2026, 5, 10, 9, 0);
      const notificationId = 126051000;

      // 模拟后台先发起补记并在首次写入计数时产生异步延迟，期间前台并发发起点击记录与补记结算
      var delayedOnce = false;
      bgPrefs.onBeforeSetString = (key, value) async {
        if (key == 'smart_push_daily_count' && !delayedOnce) {
          delayedOnce = true;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      };

      final bgFuture = bgAnalytics.recordDeliveredNotification(
        'yearAgoToday',
        notificationId: notificationId,
        sentAt: sentAt,
      );
      final fgFuture = () async {
        await fgAnalytics.recordInteraction(
          'yearAgoToday',
          notificationId: notificationId,
          deferScoreUntilAccounted: true,
        );
        await fgAnalytics.recordDeliveredNotification(
          'yearAgoToday',
          notificationId: notificationId,
          sentAt: sentAt,
        );
      }();

      await Future.wait(<Future<void>>[bgFuture, fgFuture]);

      // 下一次结算绝不能把本次真实点击当作忽略惩罚
      await fgAnalytics.settlePendingSend();
      await bgPrefs.reload();
      await fgPrefs.reload();

      expect(await fgAnalytics.getTodayPushCount(now: sentAt), equals(1));
      expect(await fgAnalytics.getUnengagedStreak(), equals(0));
      expect(await bgAnalytics.getUnengagedStreak(), equals(0));
      final scores = await fgAnalytics.getContentTypeScores();
      expect(scores['yearAgoToday']!, greaterThan(0.5));
      final stats = await fgAnalytics.getAnalyticsStats();
      expect(stats['totalNotificationsSent'], equals(1));
      expect(stats['totalEngagements'], equals(1));
    });

    test('真实跨 Isolate 文件互斥锁严格串行执行，避免两个 Isolate 并发读写覆盖', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cross_isolate_lock_test_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });
      final lockPath = '${tempDir.path}/shared.lock';
      final counterFile = File('${tempDir.path}/counter.txt')
        ..writeAsStringSync('0');

      Future<void> incrementInWorker() {
        return Isolate.run(() async {
          await PlatformHelper.withCrossIsolateLock(
            'test_lock',
            () async {
              final current = int.parse(counterFile.readAsStringSync());
              sleep(const Duration(milliseconds: 15));
              counterFile.writeAsStringSync('${current + 1}');
            },
            customLockFilePath: lockPath,
          );
        });
      }

      await Future.wait(<Future<void>>[
        incrementInWorker(),
        PlatformHelper.withCrossIsolateLock(
          'test_lock',
          () async {
            final current = int.parse(counterFile.readAsStringSync());
            sleep(const Duration(milliseconds: 10));
            counterFile.writeAsStringSync('${current + 1}');
          },
          customLockFilePath: lockPath,
        ),
      ]);

      expect(int.parse(counterFile.readAsStringSync()), equals(2));
    });
  });

  group('PushIntensity 配额矩阵', () {
    test('档位越靠右，活跃档上限越高', () async {
      final caps = PushIntensity.values
          .map((i) => i.quotaFor(EngagementTier.active).dailyCap)
          .toList();
      expect(caps, [1, 1, 2, 3]);
    });

    test('沉睡档间隔随档位收紧，且各档都只有 1 条', () async {
      for (final intensity in PushIntensity.values) {
        final profile = intensity.quotaFor(EngagementTier.dormant);
        expect(profile.dailyCap, 1, reason: '${intensity.name} 沉睡档应只推 1 条');
        expect(profile.minGapDays, greaterThanOrEqualTo(2),
            reason: '${intensity.name} 沉睡档间隔应至少 2 天');
      }
    });
  });
}
