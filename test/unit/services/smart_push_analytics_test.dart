import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/smart_push_settings.dart';
import 'package:thoughtecho/services/mmkv_service.dart';
import 'package:thoughtecho/services/smart_push_analytics.dart';

import '../../test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SmartPushAnalytics analytics;
  late MMKVService mmkvService;

  setUpAll(() async {
    await TestHarness.initialize();
    await MMKVService().init();
  });

  setUp(() async {
    mmkvService = MMKVService();
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
      expect(await analytics.getHabituationCooldown(),
          const Duration(hours: 2));

      await analytics.markSent('monthAgoToday');
      await analytics.settlePendingSend();
      expect(await analytics.getHabituationCooldown(),
          const Duration(hours: 8));
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
