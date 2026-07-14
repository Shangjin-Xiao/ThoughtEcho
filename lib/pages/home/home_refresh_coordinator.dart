import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/services/connectivity_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/weather_service.dart';
import 'package:thoughtecho/utils/app_logger.dart';

typedef HomePromptRefresh = Future<void> Function({bool initialLoad});

/// Owns environment initialization and the ordered home refresh flow.
class HomeRefreshCoordinator {
  const HomeRefreshCoordinator({
    required this.context,
    required this.isMounted,
    required this.refreshQuote,
    required this.refreshPrompt,
  });

  final BuildContext context;
  final bool Function() isMounted;
  final Future<void> Function() refreshQuote;
  final HomePromptRefresh refreshPrompt;

  bool get _active => isMounted() && context.mounted;

  Future<void> refresh() async {
    try {
      logDebug('开始刷新：先更新位置和天气信息...');
      await refreshEnvironment();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!isMounted() || !context.mounted) return;

      logDebug('位置和天气信息更新完成，开始刷新内容...');
      await Future.wait([refreshQuote(), refreshPrompt(initialLoad: false)]);
      logDebug('刷新完成');
    } catch (error) {
      logDebug('刷新失败: $error');
      if (!isMounted() || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).refreshFailed(error.toString()),
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> initialize() async {
    try {
      logDebug('开始初始化位置和天气服务...');
      await _initializeEnvironment();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!_active) return;
      logDebug('位置和天气服务初始化完成，开始获取每日提示...');
      await refreshPrompt(initialLoad: true);
    } catch (error) {
      logDebug('初始化位置天气和获取每日提示失败: $error');
      if (_active) await refreshPrompt(initialLoad: true);
    }
  }

  Future<void> refreshEnvironment() async {
    if (!_active) return;
    try {
      final locationService = context.read<LocationService>();
      final weatherService = context.read<WeatherService>();
      final connectivityService = context.read<ConnectivityService>();

      final isConnected = await connectivityService.checkConnectionNow();
      await locationService.refreshServiceStatus();
      if (!_active) return;

      if (!locationService.hasLocationPermission ||
          !locationService.isLocationServiceEnabled) {
        logDebug('位置权限未授予或位置服务未启用，跳过位置和天气刷新');
        return;
      }

      final position = await locationService.getCurrentLocation(
        skipPermissionRequest: true,
      );
      if (!isMounted() || !context.mounted || position == null) return;

      if (isConnected && locationService.isOfflineLocation) {
        final resolved = await locationService.resolveOfflineLocation();
        if (resolved && _active) _retroUpdateOfflineNotes(locationService);
      }
      await weatherService.getWeatherData(
        position.latitude,
        position.longitude,
        forceRefresh: isConnected,
      );
      logDebug('天气数据刷新完成: ${weatherService.currentWeather}');
    } catch (error) {
      logDebug('刷新位置和天气信息时发生错误: $error');
    }
  }

  Future<void> _initializeEnvironment() async {
    if (!_active) return;
    try {
      final locationService = context.read<LocationService>();
      final weatherService = context.read<WeatherService>();
      await locationService.init();
      if (!_active) return;

      if (!locationService.hasLocationPermission ||
          !locationService.isLocationServiceEnabled) {
        logDebug('位置权限未授予或位置服务未启用');
        return;
      }

      final position = await locationService
          .getCurrentLocation(
        highAccuracy: false,
        skipPermissionRequest: true,
      )
          .timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          logDebug('位置获取超时');
          return null;
        },
      );
      if (!isMounted() || !context.mounted || position == null) return;

      final isConnected = context.read<ConnectivityService>().isConnected;
      unawaited(
        weatherService
            .getWeatherData(
              position.latitude,
              position.longitude,
              forceRefresh: isConnected,
              timeout: const Duration(seconds: 10),
            )
            .then((_) => logDebug('天气数据更新完成: ${weatherService.currentWeather}'))
            .catchError((error) => logDebug('天气数据更新失败: $error')),
      );
    } catch (error) {
      logDebug('初始化位置和天气服务时发生错误: $error');
    }
  }

  void _retroUpdateOfflineNotes(LocationService locationService) {
    if (!_active) return;
    final resolvedAddress = locationService.getLocationDisplayText();
    if (resolvedAddress.isEmpty) return;
    final database = context.read<DatabaseService>();

    unawaited(() async {
      try {
        final count = await database.batchUpdatePendingLocations(
          resolvedAddress: resolvedAddress,
        );
        if (count > 0) logDebug('P1: 回溯更新了 $count 条离线笔记的位置信息');
      } catch (error) {
        logDebug('回溯更新离线笔记位置失败: $error');
      }
    }());
  }
}
