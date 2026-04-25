part of '../home_page.dart';

/// Extension for lifecycle methods and initialization
extension _HomeLifecycle on _HomePageState {
  /// Initializes location and weather services, then fetches daily prompt
  Future<void> _initLocationAndWeatherThenFetchPrompt() async {
    try {
      logDebug('开始初始化位置和天气服务...');

      // 先初始化位置和天气
      await _initLocationAndWeather();

      // 减少等待时间，因为已经优化了并行初始化
      await Future.delayed(const Duration(milliseconds: 300));

      logDebug('位置和天气服务初始化完成，开始获取每日提示...');

      // 然后获取每日提示（包含位置和天气信息）
      await _fetchDailyPrompt(initialLoad: true);
    } catch (e) {
      logDebug('初始化位置天气和获取每日提示失败: $e');
      // 即使初始化失败，也尝试获取默认提示
      await _fetchDailyPrompt(initialLoad: true);
    }
  }

  /// 初始化位置和天气服务 - 简化优化版本
  Future<void> _initLocationAndWeather() async {
    if (!mounted) return;

    try {
      logDebug('开始初始化位置和天气服务...');

      final locationService = Provider.of<LocationService>(
        context,
        listen: false,
      );
      final weatherService = Provider.of<WeatherService>(
        context,
        listen: false,
      );

      // 并行初始化位置服务（天气服务在WeatherService构造时已经初始化）
      await locationService.init();

      if (!mounted) return;

      logDebug('位置服务初始化完成，权限状态: ${locationService.hasLocationPermission}');

      // 如果有权限，获取位置和天气
      if (locationService.hasLocationPermission &&
          locationService.isLocationServiceEnabled) {
        logDebug('开始获取位置（低精度模式）...');

        final position = await locationService
            .getCurrentLocation(
          highAccuracy: false, // 使用低精度模式，更快
          skipPermissionRequest: true,
        )
            .timeout(
          const Duration(seconds: 8), // 设置超时
          onTimeout: () {
            logDebug('位置获取超时');
            return null;
          },
        );

        if (!mounted) return;

        if (position != null) {
          logDebug('位置获取成功: ${position.latitude}, ${position.longitude}');

          // P10: 冷启动时检查网络状态，联网则强刷天气获取实时数据
          final connectivityService = Provider.of<ConnectivityService>(
            context,
            listen: false,
          );
          final isConnected = connectivityService.isConnected;

          // 异步获取天气，不阻塞主流程（使用事件队列调度，避免 microtask 抢占 UI）
          unawaited(
            weatherService
                .getWeatherData(
                  position.latitude,
                  position.longitude,
                  forceRefresh: isConnected,
                  timeout: const Duration(seconds: 10),
                )
                .then((_) =>
                    logDebug('天气数据更新完成: ${weatherService.currentWeather}'))
                .catchError((e) => logDebug('天气数据更新失败: $e')),
          );
        } else {
          logDebug('位置获取失败');
        }
      } else {
        logDebug('位置权限未授予或位置服务未启用');
      }
    } catch (e) {
      logDebug('初始化位置和天气服务时发生错误: $e');
      // 不抛出异常，让调用方继续执行
    }
  }

  /// 刷新位置和天气信息
  Future<void> _refreshLocationAndWeather() async {
    if (!mounted) return;

    try {
      logDebug('开始刷新位置和天气信息...');

      final locationService = Provider.of<LocationService>(
        context,
        listen: false,
      );
      final weatherService = Provider.of<WeatherService>(
        context,
        listen: false,
      );
      final connectivityService = Provider.of<ConnectivityService>(
        context,
        listen: false,
      );

      // 先刷新网络状态
      final isConnected = await connectivityService.checkConnectionNow();

      // P4: 动态刷新位置服务和权限状态，防止初始化时的过期值
      await locationService.refreshServiceStatus();

      // 如果有位置权限，重新获取位置和天气
      if (locationService.hasLocationPermission &&
          locationService.isLocationServiceEnabled) {
        logDebug('重新获取当前位置...');
        final position = await locationService.getCurrentLocation(
          skipPermissionRequest: true,
        );

        if (!mounted) return;

        if (position != null) {
          // 联网时尝试解析离线坐标的地址
          if (isConnected && locationService.isOfflineLocation) {
            logDebug('尝试解析离线位置的地址...');
            final resolved = await locationService.resolveOfflineLocation();

            // P1: 地址解析成功后，回溯更新近期离线笔记的位置字段
            if (resolved && mounted) {
              _retroUpdateOfflineNoteLocations(locationService);
            }
          }

          logDebug('位置获取成功，开始刷新天气数据...');
          // 仅联网时强制刷新天气，离线时使用缓存避免冲掉已有数据
          await weatherService.getWeatherData(
            position.latitude,
            position.longitude,
            forceRefresh: isConnected,
          );
          logDebug('天气数据刷新完成: ${weatherService.currentWeather}');
        } else {
          logDebug('位置获取失败');
        }
      } else {
        logDebug('位置权限未授予或位置服务未启用，跳过位置和天气刷新');
      }
    } catch (e) {
      logDebug('刷新位置和天气信息时发生错误: $e');
      // 不抛出异常，让调用方继续执行
    }
  }

  /// P1: 回溯更新近期离线笔记的位置字段
  /// 当网络恢复并成功解析出地址后，更新最近 24 小时内
  /// 带有 pending/failed 位置标记的笔记
  void _retroUpdateOfflineNoteLocations(LocationService locationService) {
    if (!mounted) return;

    final dbService = Provider.of<DatabaseService>(context, listen: false);
    final resolvedAddress = locationService.getLocationDisplayText();
    if (resolvedAddress.isEmpty) return;

    Future.microtask(() async {
      try {
        final allQuotes = await dbService.getAllQuotes();
        final cutoff = DateTime.now().subtract(const Duration(hours: 24));
        int updatedCount = 0;

        for (final quote in allQuotes) {
          // 只更新 24 小时内、有坐标但地址为 pending/failed 的笔记
          final quoteDate = DateTime.tryParse(quote.date);
          if (quoteDate == null || quoteDate.isBefore(cutoff)) continue;

          if (LocationService.isNonDisplayMarker(quote.location) &&
              quote.latitude != null &&
              quote.longitude != null) {
            final updatedQuote = quote.copyWith(
              location: resolvedAddress,
            );
            final updateResult = await dbService.updateQuote(updatedQuote);
            switch (updateResult) {
              case QuoteUpdateResult.updated:
                updatedCount++;
                break;
              case QuoteUpdateResult.notFound:
                logWarning('回溯更新离线笔记位置时笔记不存在: ${quote.id}');
                break;
              case QuoteUpdateResult.skippedDeleted:
                logWarning('回溯更新离线笔记位置时笔记已删除: ${quote.id}');
                break;
            }
          }
        }

        if (updatedCount > 0) {
          logDebug('P1: 回溯更新了 $updatedCount 条离线笔记的位置信息');
        }
      } catch (e) {
        logDebug('回溯更新离线笔记位置失败: $e');
      }
    });
  }

  /// 网络状态变化回调：恢复联网时自动刷新位置和天气
  void _onConnectivityChanged() {
    final isConnected = _connectivityService?.isConnected ?? false;
    if (isConnected && mounted) {
      logDebug('网络已恢复，自动刷新位置和天气...');
      _refreshLocationAndWeather();
    }
  }

  /// 检查是否应该显示一周年庆典动画（整个周期内只播放一次）
  Future<void> _checkAndShowAnniversaryAnimation() async {
    if (!mounted) return;
    final settingsService = context.read<SettingsService>();
    final settings = settingsService.appSettings;

    final now = DateTime.now();
    final shouldShow = AnniversaryDisplayUtils.shouldAutoShowAnimation(
      now: now,
      developerMode: settings.developerMode,
      anniversaryShown: settings.anniversaryShown,
      anniversaryAnimationEnabled: settings.anniversaryAnimationEnabled,
    );
    if (!shouldShow) {
      return;
    }

    // 标记为已显示
    await settingsService.setAnniversaryShown(true);

    if (!mounted) return;

    // 显示全屏覆盖动画
    await showAnniversaryAnimationOverlay(context);
  }

  /// 开发者模式预览一周年动画
  void _showAnniversaryPreview(BuildContext context) {
    showAnniversaryAnimationOverlay(context);
  }

  /// 切换标签页
  void _onTabChanged(int index) {
    setState(() {
      _currentIndex = index;
    });

    // 当切换到笔记列表页时，重新加载标签
    if (_currentIndex == 1) {
      _refreshTags();
      _consumeInitialHighlightedNote();
    }

    _triggerGuideForCurrentIndex();
  }

  /// 刷新标签列表
  Future<void> _refreshTags() async {
    logDebug('刷新标签列表');
    setState(() {
      _isLoadingTags = true;
    });
    await _loadTags();
  }

  /// 改进标签加载逻辑
  Future<void> _loadTags() async {
    try {
      logDebug('加载标签数据...');
      if (!context.mounted) return; // 添加 mounted 检查
      final categories = await context.read<DatabaseService>().getCategories();

      if (mounted) {
        setState(() {
          _tags = categories;
          _isLoadingTags = false;
        });
        logDebug('标签加载完成，共 ${categories.length} 个标签');
      }
    } catch (e) {
      logDebug('加载标签时出错: $e');
      if (mounted) {
        setState(() {
          _isLoadingTags = false;
        });
      }
    }
  }

  /// 预加载标签数据，确保AddNoteDialog打开时数据已准备好
  Future<void> _preloadTags() async {
    setState(() {
      _isLoadingTags = true;
    });

    try {
      // 使用Future.microtask避免阻塞UI初始化
      await Future.microtask(() async {
        await _loadTags();
      });
    } catch (e) {
      logDebug('预加载标签失败: $e');
      if (mounted) {
        setState(() {
          _isLoadingTags = false;
        });
      }
    }
  }
}
