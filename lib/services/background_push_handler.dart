import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/mmkv_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/smart_push_service.dart';
import 'package:thoughtecho/utils/app_logger.dart';

/// 后台推送入口
///
/// 当 Android AlarmManager 触发时，会在独立的 isolate 中运行此函数。
/// 这里必须初始化最小的必要环境。
@pragma('vm:entry-point')
void backgroundPushCallback() async {
  // 1. 初始化 Flutter 绑定
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  // 2. 初始化日志 (简单控制台输出)
  AppLogger.initialize();
  AppLogger.i('后台推送任务启动');

  try {
    // 3. 初始化基础服务
    // 注意：在后台 Isolate 中，我们需要全新的服务实例
    final mmkvService = MMKVService();
    await mmkvService.init();

    // 数据库初始化可能需要依赖 DataDirectoryService 来确定路径
    // 如果 DatabaseService 内部已经处理了 init 逻辑（自动判断路径），则直接 init
    // 但通常 DatabaseService.init() 依赖 getApplicationDocumentsDirectory
    // 在后台 Isolate 中，PathProvider 插件应该能正常工作
    final databaseService = DatabaseService();
    await databaseService.init();

    final locationService = LocationService();
    // 尝试预热位置服务（可能需要权限）
    // 注意：后台定位权限在 Android 10+ 比较严格，这里只是尽力而为
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

    // 加载设置（内部会读取 MMKV）
    // 这里我们不需要调用 initialize() 去注册通知点击回调，因为点击通知会打开主 Isolate
    // 我们只需要 checkAndPush
    await pushService.loadSettingsForBackground();

    // 5. 执行检查和推送
    await pushService.checkAndPush(isBackground: true);

  } catch (e, stack) {
    AppLogger.e('后台推送任务发生严重错误', error: e, stackTrace: stack);
  } finally {
    AppLogger.i('后台推送任务结束');
    // 在 Isolate 中通常不需要手动关闭，Dart 会在函数执行完后自动处理资源，
    // 但如果 DatabaseService 有连接池，最好 close。
    // 这里我们暂不显式 close，依赖系统回收。
  }
}
