import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'services/settings_service.dart';
import 'services/database_service.dart';
import 'services/location_service.dart';
import 'services/weather_service.dart';
import 'services/clipboard_service.dart';
import 'services/log_service.dart';
import 'services/ai_service.dart';
import 'services/mmkv_service.dart';
import 'theme/app_theme.dart';

/// 创建应用全局 Providers
List<SingleChildWidget> createAppProviders({
  required SettingsService settingsService,
  required DatabaseService databaseService,
  required LocationService locationService,
  required WeatherService weatherService,
  required ClipboardService clipboardService,
  required LogService logService,
  required AppTheme appTheme,
  required MMKVService mmkvService,
  required ValueNotifier<bool> servicesInitialized,
}) {
  return [
    // ChangeNotifierProvider 用于需要监听变化的 Service
    ChangeNotifierProvider.value(value: settingsService),
    ChangeNotifierProvider.value(value: databaseService),
    ChangeNotifierProvider.value(value: locationService),
    ChangeNotifierProvider.value(value: weatherService),
    ChangeNotifierProvider.value(value: clipboardService),
    ChangeNotifierProvider.value(value: logService),
    ChangeNotifierProvider.value(value: appTheme),

    // Provider.value 用于不需要监听变化或已初始化的 Service
    Provider.value(value: mmkvService),

    // ValueListenableProvider 用于监听 ValueNotifier
    ValueListenableProvider<bool>.value(value: servicesInitialized),

    // ChangeNotifierProxyProvider 用于依赖其他 Provider 的 Service
    ChangeNotifierProxyProvider<SettingsService, AIService>(
      // AIService 只需要在创建时传入依赖
      create: (context) => AIService(
        settingsService: settingsService, // 直接使用传入的实例
        locationService: locationService, // 直接使用传入的实例
        weatherService: weatherService,   // 直接使用传入的实例
      ),
      // update 通常用于当依赖变化时重建或更新 Service，
      // 如果 AIService 内部状态不依赖 SettingsService 的变化而变化，可以简化
      update: (context, settings, previous) => previous ?? AIService(
              settingsService: settings,
              locationService: locationService,
              weatherService: weatherService,
            ),
      // 如果 AIService 不需要 SettingsService 更新时重建，可以使用下面的简化方式
      // update: (context, settings, previous) => previous!,
      // 但这要求 create 中必须正确初始化。
      // 保留 update 逻辑可以确保在 settings 变化时 AIService 能够拿到最新的引用，
      // 即使其内部逻辑不直接响应变化。
    ),
  ];
} 