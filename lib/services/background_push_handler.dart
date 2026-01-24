import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/mmkv_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/smart_push_service.dart';
import 'package:thoughtecho/utils/app_logger.dart';

// WorkManager 任务名称常量
const String kBackgroundPushTask = 'com.shangjin.thoughtecho.backgroundPush';
const String kPeriodicCheckTask = 'com.shangjin.thoughtecho.periodicCheck';

/// WorkManager 回调分发器
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // 1. 初始化 Flutter 绑定
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    // 2. 初始化日志
    AppLogger.initialize();
    AppLogger.w('WorkManager 任务启动: $task'); // 改为 warning 以便在非开发者模式下也能记录到数据库

    try {
      // 3. 初始化基础服务
      final mmkvService = MMKVService();
      await mmkvService.init();

      final databaseService = DatabaseService();
      await databaseService.init();

      final locationService = LocationService();
      try {
        await locationService.init();
      } catch (e) {
        AppLogger.w('后台初始化位置服务失败: $e');
      }

      // 4. 创建服务实例
      final pushService = SmartPushService(
        databaseService: databaseService,
        locationService: locationService,
        mmkvService: mmkvService,
      );

      // 加载设置
      await pushService.loadSettingsForBackground();

      // 5. 根据任务类型执行
      switch (task) {
        case kBackgroundPushTask:
        case Workmanager.iOSBackgroundTask: // iOS 后台处理通用入口
          AppLogger.i('执行一次性推送检查...');
          await pushService.checkAndPush(isBackground: true);
          break;

        case kPeriodicCheckTask:
          // 周期性检查逻辑
          AppLogger.i('执行周期性推送检查...');
          await pushService.checkAndPush(isBackground: true);
          break;

        default:
          AppLogger.w('未知的 WorkManager 任务: $task');
      }

      AppLogger.w('WorkManager 任务完成: $task');
      return true;
    } catch (e, stack) {
      AppLogger.e('WorkManager 任务失败', error: e, stackTrace: stack);
      return false;
    }
  });
}

/// 后台推送入口
///
/// 当 Android AlarmManager 触发时，会在独立的 isolate 中运行此函数。
/// 这里必须初始化最小的必要环境。
@pragma('vm:entry-point')
void backgroundPushCallback([int? id]) async {
  // 1. 初始化 Flutter 绑定
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  // 2. 初始化日志
  AppLogger.initialize();
  AppLogger.w('后台推送任务启动 (AlarmId: $id)'); // 改为 warning 以便记录

  try {
    // 3. 初始化基础服务
    final mmkvService = MMKVService();
    await mmkvService.init();

    final databaseService = DatabaseService();
    await databaseService.init();

    final locationService = LocationService();
    try {
      await locationService.init();
    } catch (e) {
      AppLogger.w('后台初始化位置服务失败: $e');
    }

    // 4. 创建并运行 SmartPushService 的一次性检查
    final pushService = SmartPushService(
      databaseService: databaseService,
      locationService: locationService,
      mmkvService: mmkvService,
    );

    // 加载设置
    await pushService.loadSettingsForBackground();

    // 5. 执行检查和推送
    AppLogger.i('执行检查和推送 (isBackground: true)');
    await pushService.checkAndPush(isBackground: true);

    // 6. 重新调度下一次推送（关键步骤！）
    // 因为 oneShotAt 是一次性的，需要在执行完后重新调度
    await pushService.scheduleNextPush();

    AppLogger.w('后台推送任务完成，已重新调度下次推送');
  } catch (e, stack) {
    AppLogger.e('后台推送任务发生严重错误', error: e, stackTrace: stack);
  } finally {
    AppLogger.i('后台推送任务结束');
  }
}

/// 后台定时检查入口（周期性任务）
/// 用于定期检查是否需要推送，而不是依赖精确的闹钟
///
/// 这是 Android 12+ 精确闹钟权限被拒绝时的备用方案
/// 每15分钟检查一次是否有遗漏的推送
@pragma('vm:entry-point')
void backgroundPeriodicCheck() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  AppLogger.initialize();
  AppLogger.i('后台周期性检查启动');

  try {
    final mmkvService = MMKVService();
    await mmkvService.init();

    final databaseService = DatabaseService();
    await databaseService.init();

    final locationService = LocationService();
    try {
      await locationService.init();
    } catch (e) {
      AppLogger.w('后台初始化位置服务失败: $e');
    }

    final pushService = SmartPushService(
      databaseService: databaseService,
      locationService: locationService,
      mmkvService: mmkvService,
    );

    await pushService.loadSettingsForBackground();

    final now = DateTime.now();
    final settings = pushService.settings;

    if (!settings.enabled) {
      AppLogger.d('推送未启用，跳过检查');
      return;
    }

    // 检查常规推送时间槽（扩大窗口到±10分钟，因为周期性任务不精确）
    bool pushedRegular = false;
    if (settings.shouldPushToday()) {
      for (final slot in settings.pushTimeSlots) {
        if (!slot.enabled) continue;

        final slotTime =
            DateTime(now.year, now.month, now.day, slot.hour, slot.minute);
        final diff = now.difference(slotTime).inMinutes;

        // 在时间槽之后0-10分钟内触发（避免重复推送）
        if (diff >= 0 && diff <= 10) {
          AppLogger.i('周期性检查：当前时间接近推送时间槽 ${slot.formattedTime}，触发推送');
          await pushService.checkAndPush(isBackground: true);
          pushedRegular = true;
          break;
        }
      }
    }

    // 检查每日一言推送
    if (settings.dailyQuotePushEnabled && !pushedRegular) {
      final dailySlot = settings.dailyQuotePushTime;
      final dailyTime = DateTime(
          now.year, now.month, now.day, dailySlot.hour, dailySlot.minute);
      final dailyDiff = now.difference(dailyTime).inMinutes;

      if (dailyDiff >= 0 && dailyDiff <= 10) {
        AppLogger.i('周期性检查：当前时间接近每日一言时间 ${dailySlot.formattedTime}，触发推送');
        await pushService.checkAndPush(isBackground: true);
      }
    }

    AppLogger.i('后台周期性检查完成');
  } catch (e, stack) {
    AppLogger.e('后台周期性检查失败', error: e, stackTrace: stack);
  }
}
