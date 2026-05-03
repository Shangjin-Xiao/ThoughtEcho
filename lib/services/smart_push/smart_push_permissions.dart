part of '../smart_push_service.dart';

/// 权限管理 — 通知、精确闹钟、电池优化、厂商自启动
extension SmartPushPermissions on SmartPushService {
  /// 请求通知权限
  Future<bool> requestNotificationPermission() async {
    try {
      if (PlatformHelper.isAndroid) {
        final androidPlugin = _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        if (androidPlugin != null) {
          final granted = await androidPlugin.requestNotificationsPermission();
          return granted ?? false;
        }
      }

      if (PlatformHelper.isIOS) {
        final iosPlugin = _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        if (iosPlugin != null) {
          final granted = await iosPlugin.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
          return granted ?? false;
        }
      }

      return true;
    } catch (e) {
      AppLogger.e('请求通知权限失败', error: e);
      return false;
    }
  }

  /// 检查是否有精确闹钟权限（Android 12+）
  ///
  /// 注意：SCHEDULE_EXACT_ALARM 不是运行时权限，需要用户在设置中手动开启
  /// Android 14+ 默认拒绝此权限
  Future<bool> checkExactAlarmPermission() async {
    if (!PlatformHelper.isAndroid) return true;

    try {
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (androidPlugin != null) {
        // 1. 首先检查通知权限
        final notificationsEnabled =
            await androidPlugin.areNotificationsEnabled() ?? false;
        if (!notificationsEnabled) {
          AppLogger.w('通知权限未授予');
          return false;
        }

        // 2. 检查精确闹钟权限 (Android 12+)
        // 使用 canScheduleExactNotifications() 检查
        final canScheduleExact =
            await androidPlugin.canScheduleExactNotifications() ?? false;
        if (!canScheduleExact) {
          AppLogger.w('精确闹钟权限未授予 (SCHEDULE_EXACT_ALARM)');
          // 返回 true 但记录警告 - 我们仍会尝试调度，系统会降级处理
          // 用户可以手动在设置中开启
        }

        // 精确闹钟权限需要通知权限作为前提
        return canScheduleExact && notificationsEnabled;
      }
      return true;
    } catch (e) {
      AppLogger.w('检查精确闹钟权限失败', error: e);
      return false;
    }
  }

  /// 请求精确闹钟权限（引导用户到设置页面）
  Future<bool> requestExactAlarmPermission() async {
    if (!PlatformHelper.isAndroid) return true;

    try {
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (androidPlugin != null) {
        // 检查是否已有权限
        final canSchedule =
            await androidPlugin.canScheduleExactNotifications() ?? false;
        if (canSchedule) return true;

        // 尝试请求权限（会打开系统设置页面）
        await androidPlugin.requestExactAlarmsPermission();

        // 再次检查
        return await androidPlugin.canScheduleExactNotifications() ?? false;
      }
      return true;
    } catch (e) {
      AppLogger.e('请求精确闹钟权限失败', error: e);
      return false;
    }
  }

  /// 检查电池优化是否已豁免
  ///
  /// 返回 true 表示已豁免电池优化（推送可以正常工作）
  /// 返回 false 表示未豁免（可能导致推送被系统杀死）
  Future<bool> checkBatteryOptimizationExempted() async {
    if (!PlatformHelper.isAndroid) return true;

    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      final isExempted = status.isGranted;
      AppLogger.d('电池优化豁免状态: $isExempted');
      return isExempted;
    } catch (e) {
      AppLogger.w('检查电池优化状态失败', error: e);
      return false;
    }
  }

  /// 请求电池优化豁免
  ///
  /// 会弹出系统对话框让用户确认
  Future<bool> requestBatteryOptimizationExemption() async {
    if (!PlatformHelper.isAndroid) return true;

    try {
      final status = await Permission.ignoreBatteryOptimizations.request();
      final isExempted = status.isGranted;
      AppLogger.i('请求电池优化豁免结果: $isExempted');
      return isExempted;
    } catch (e) {
      AppLogger.e('请求电池优化豁免失败', error: e);
      return false;
    }
  }

  /// 获取设备制造商
  Future<String> getDeviceManufacturer() async {
    if (!PlatformHelper.isAndroid) return '';

    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.manufacturer.toLowerCase();
    } catch (e) {
      AppLogger.w('获取设备制造商失败', error: e);
      return '';
    }
  }

  /// 获取 Android SDK 版本
  Future<int> getAndroidSdkVersion() async {
    if (!PlatformHelper.isAndroid) return 0;

    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.version.sdkInt;
    } catch (e) {
      AppLogger.w('获取 Android SDK 版本失败', error: e);
      return 0;
    }
  }

  /// 打开应用设置页面（用于手动设置自启动等）
  Future<void> openSystemAppSettings() async {
    try {
      await openAppSettings();
    } catch (e) {
      AppLogger.w('打开应用设置失败', error: e);
    }
  }

  /// 检查通知权限
  Future<bool> checkNotificationPermission() async {
    if (!PlatformHelper.isAndroid) return true;

    try {
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (androidPlugin != null) {
        return await androidPlugin.areNotificationsEnabled() ?? false;
      }
      return true;
    } catch (e) {
      AppLogger.w('检查通知权限失败', error: e);
      return false;
    }
  }

  /// 获取完整的推送权限状态
  ///
  /// 返回一个包含所有权限状态的 Map，用于 UI 展示
  Future<PushPermissionStatus> getPushPermissionStatus() async {
    if (kIsWeb) {
      return PushPermissionStatus(
        notificationEnabled: true,
        exactAlarmEnabled: true,
        batteryOptimizationExempted: true,
        manufacturer: '',
        sdkVersion: 0,
        needsAutoStartPermission: false,
        autoStartGranted: true,
      );
    }

    final notificationEnabled = await checkNotificationPermission();
    final exactAlarmEnabled = await checkExactAlarmPermission();
    final batteryExempted = await checkBatteryOptimizationExempted();
    final manufacturer = await getDeviceManufacturer();
    final sdkVersion = await getAndroidSdkVersion();
    final autoStartGranted = await getAutoStartGranted();

    // 这些厂商的 ROM 通常需要额外的自启动权限
    final autoStartManufacturers = [
      'xiaomi',
      'redmi',
      'oppo',
      'realme',
      'vivo',
      'huawei',
      'honor',
      'oneplus',
      'meizu',
      'samsung',
      'asus',
      'letv',
      'leeco',
    ];

    final needsAutoStart = autoStartManufacturers.any(
      (m) => manufacturer.contains(m),
    );

    return PushPermissionStatus(
      notificationEnabled: notificationEnabled,
      exactAlarmEnabled: exactAlarmEnabled,
      batteryOptimizationExempted: batteryExempted,
      manufacturer: manufacturer,
      sdkVersion: sdkVersion,
      needsAutoStartPermission: needsAutoStart,
      autoStartGranted: autoStartGranted,
    );
  }

  /// 获取厂商特定的自启动设置指引
  String getAutoStartInstructions(String manufacturer) {
    final m = manufacturer.toLowerCase();

    if (m.contains('xiaomi') || m.contains('redmi')) {
      return '设置 → 应用设置 → 应用管理 → 心迹 → 自启动';
    } else if (m.contains('huawei') || m.contains('honor')) {
      return '设置 → 应用 → 应用启动管理 → 心迹 → 手动管理 → 开启自启动';
    } else if (m.contains('oppo') || m.contains('realme')) {
      return '设置 → 应用管理 → 应用列表 → 心迹 → 自启动';
    } else if (m.contains('vivo')) {
      return '设置 → 更多设置 → 应用程序 → 自启动管理 → 心迹';
    } else if (m.contains('oneplus')) {
      return '设置 → 应用 → 应用管理 → 心迹 → 电池 → 允许后台运行';
    } else if (m.contains('samsung')) {
      return '设置 → 应用程序 → 心迹 → 电池 → 允许后台活动';
    } else if (m.contains('meizu')) {
      return '设置 → 应用管理 → 心迹 → 权限管理 → 后台管理 → 允许后台运行';
    } else if (m.contains('asus')) {
      return '设置 → 电池管理 → 自启动管理 → 心迹';
    } else if (m.contains('letv') || m.contains('leeco')) {
      return '设置 → 权限管理 → 自启动管理 → 心迹';
    }

    return '请在系统设置中找到应用管理，然后允许心迹自启动和后台运行';
  }
}
