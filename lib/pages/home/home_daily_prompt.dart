part of '../home_page.dart';

/// Extension for daily prompt related logic
extension _HomeDailyPrompt on _HomePageState {
  /// Fetches the daily prompt
  Future<void> _fetchDailyPrompt({bool initialLoad = false}) async {
    // 如果是初始加载，并且已经有订阅或累积文本，则不重复加载
    if (initialLoad &&
        (_promptSubscription != null || _accumulatedPromptText.isNotEmpty)) {
      logDebug(
        'Daily prompt already loaded or loading, skipping initial fetch.',
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _accumulatedPromptText = ''; // Clear previous text
      _isGeneratingDailyPrompt = true; // Set loading state
      _promptSubscription?.cancel(); // Cancel previous subscription
      _promptSubscription = null;
    });

    try {
      final aiService = context.read<AIService>();
      final locationService = context.read<LocationService>();
      final weatherService = context.read<WeatherService>();

      // 获取环境信息
      String? city = locationService.city;
      String? weather = weatherService.currentWeather;
      String? temperature = weatherService.temperature;

      // 检查是否启用今日思考AI，或是否有AI配置；不满足则使用本地生成
      final settingsService = context.read<SettingsService>();
      final aiEnabledForToday = settingsService.todayThoughtsUseAI;

      if (!aiEnabledForToday || !aiService.hasValidApiKey()) {
        // 使用本地的每日提示生成器
        final l10n = AppLocalizations.of(context);
        final localPrompt = DailyPromptGenerator.generatePromptBasedOnContext(
          l10n,
          city: city,
          weather: weather,
          temperature: temperature,
        );

        if (mounted) {
          setState(() {
            _accumulatedPromptText = localPrompt;
            _isGeneratingDailyPrompt = false;
          });
        }
        return;
      }

      // 获取最近的周期洞察（本周、上周、本月、上月）
      final insightHistoryService = context.read<InsightHistoryService>();
      final recentInsights =
          await insightHistoryService.formatRecentInsightsForDailyPrompt();
      logDebug('获取到 ${recentInsights.length} 条最近的周期洞察', source: 'HomePage');

      // Call the new stream method with environment context and historical insights
      if (!mounted) {
        return; // Ensure the widget is still mounted after async work
      }

      final l10n = AppLocalizations.of(context);
      final Stream<String> promptStream = aiService.streamGenerateDailyPrompt(
        l10n,
        city: city,
        weather: weather,
        temperature: temperature,
        historicalInsights: recentInsights,
      );

      if (!mounted) {
        return; // Ensure mounted before setting stream and listening
      }

      // Set the stream variable so StreamBuilder can react to connection state changes
      setState(() {});

      // Listen to the stream and accumulate text
      _promptSubscription = promptStream.listen(
        (String chunk) {
          // Append the new chunk and update state to trigger UI rebuild
          if (mounted) {
            setState(() {
              _accumulatedPromptText += chunk;
            });
          }
        },
        onError: (error) {
          // Handle errors - 提供降级策略
          logDebug('获取每日提示流出错: $error，使用本地生成的提示');
          if (mounted) {
            // 生成本地提示作为降级
            final l10n = AppLocalizations.of(context);
            final fallbackPrompt =
                DailyPromptGenerator.generatePromptBasedOnContext(
              l10n,
              city: city,
              weather: weather,
              temperature: temperature,
            );

            setState(() {
              _accumulatedPromptText = fallbackPrompt;
              _isGeneratingDailyPrompt = false; // Stop loading on error
            });

            // 不显示错误信息，只在debug中记录，用户看到的是降级提示
          }
        },
        onDone: () {
          // Stream finished, update loading state and trim the accumulated text
          if (mounted) {
            setState(() {
              _accumulatedPromptText =
                  _accumulatedPromptText.trim(); // 去除前后空白字符
              _isGeneratingDailyPrompt = false; // Stop loading on done
            });
            // 移除每日思考生成完成的弹窗通知
          }
        },
        cancelOnError: true, // Cancel subscription if an error occurs
      );
    } catch (e) {
      logDebug('获取每日提示失败 (setup): $e');
      if (mounted) {
        // 使用本地生成的提示作为降级策略
        final locationService = context.read<LocationService>();
        final weatherService = context.read<WeatherService>();
        final l10n = AppLocalizations.of(context);

        final fallbackPrompt =
            DailyPromptGenerator.generatePromptBasedOnContext(
          l10n,
          city: locationService.city,
          weather: weatherService.currentWeather,
          temperature: weatherService.temperature,
        );

        setState(() {
          _accumulatedPromptText = fallbackPrompt;
          _isGeneratingDailyPrompt = false; // Stop loading on setup error
        });

        // 只在debug模式下显示错误，普通用户看到降级提示即可
        logDebug('AI提示获取失败，已使用本地生成的提示');
      }
    }
  }

  /// 统一刷新方法 - 先刷新位置天气，再同时刷新每日一言和每日提示
  Future<void> _handleRefresh() async {
    try {
      logDebug('开始刷新：先更新位置和天气信息...');

      // 第一步：重新获取位置和天气信息
      await _refreshLocationAndWeather();

      // 等待一下确保位置和天气信息已更新
      await Future.delayed(const Duration(milliseconds: 500));

      logDebug('位置和天气信息更新完成，开始刷新内容...');

      // 第二步：并行刷新每日一言和每日提示（现在有最新的位置天气信息）
      await Future.wait([
        // 刷新每日一言
        if (_dailyQuoteViewKey.currentState != null)
          _dailyQuoteViewKey.currentState!.refreshQuote(),
        // 刷新每日提示（现在会使用最新的位置和天气信息）
        _fetchDailyPrompt(),
      ]);

      logDebug('刷新完成');
    } catch (e) {
      logDebug('刷新失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).refreshFailed(e.toString()),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
