import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../gen_l10n/app_localizations.dart';
import '../../services/ai_service.dart';
import '../../services/insight_history_service.dart';
import '../../services/location_service.dart';
import '../../services/settings_service.dart';
import '../../services/weather_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';
import '../../utils/daily_prompt_generator.dart';

class HomeDailyPromptPanel extends StatefulWidget {
  final double screenWidth;
  final bool isSmallScreen;
  final bool isVerySmallScreen;

  const HomeDailyPromptPanel({
    super.key,
    required this.screenWidth,
    required this.isSmallScreen,
    required this.isVerySmallScreen,
  });

  @override
  State<HomeDailyPromptPanel> createState() => HomeDailyPromptPanelState();
}

class HomeDailyPromptPanelState extends State<HomeDailyPromptPanel> {
  String _accumulatedPromptText = '';
  StreamSubscription<String>? _promptSubscription;
  bool _isGeneratingDailyPrompt = false;

  Future<void> refreshPrompt({bool initialLoad = false}) async {
    if (initialLoad &&
        (_promptSubscription != null || _accumulatedPromptText.isNotEmpty)) {
      logDebug(
        'Daily prompt already loaded or loading, skipping initial fetch.',
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _accumulatedPromptText = '';
      _isGeneratingDailyPrompt = true;
      _promptSubscription?.cancel();
      _promptSubscription = null;
    });

    try {
      final aiService = context.read<AIService>();
      final locationService = context.read<LocationService>();
      final weatherService = context.read<WeatherService>();
      final settingsService = context.read<SettingsService>();

      final city = locationService.city;
      final weather = weatherService.currentWeather;
      final temperature = weatherService.temperature;
      final aiEnabledForToday = settingsService.todayThoughtsUseAI;

      if (!aiEnabledForToday || !aiService.hasValidApiKey()) {
        _setLocalPrompt(
          city: city,
          weather: weather,
          temperature: temperature,
        );
        return;
      }

      final insightHistoryService = context.read<InsightHistoryService>();
      final recentInsights =
          await insightHistoryService.formatRecentInsightsForDailyPrompt();
      logDebug(
        '获取到 ${recentInsights.length} 条最近的周期洞察',
        source: 'HomeDailyPromptPanel',
      );

      if (!mounted) return;

      final l10n = AppLocalizations.of(context);
      final promptStream = aiService.streamGenerateDailyPrompt(
        l10n,
        city: city,
        weather: weather,
        temperature: temperature,
        historicalInsights: recentInsights,
      );

      if (!mounted) return;

      _promptSubscription = promptStream.listen(
        (chunk) {
          if (!mounted) return;
          setState(() {
            _accumulatedPromptText += chunk;
          });
        },
        onError: (error) {
          logDebug('获取每日提示流出错: $error，使用本地生成的提示');
          if (!mounted) return;
          _setLocalPrompt(
            city: city,
            weather: weather,
            temperature: temperature,
          );
        },
        onDone: () {
          if (!mounted) return;
          setState(() {
            _accumulatedPromptText = _accumulatedPromptText.trim();
            _isGeneratingDailyPrompt = false;
          });
        },
        cancelOnError: true,
      );
    } catch (e) {
      logDebug('获取每日提示失败 (setup): $e');
      if (!mounted) return;

      final locationService = context.read<LocationService>();
      final weatherService = context.read<WeatherService>();
      _setLocalPrompt(
        city: locationService.city,
        weather: weatherService.currentWeather,
        temperature: weatherService.temperature,
      );
      logDebug('AI提示获取失败，已使用本地生成的提示');
    }
  }

  void _setLocalPrompt({
    String? city,
    String? weather,
    String? temperature,
  }) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final localPrompt = DailyPromptGenerator.generatePromptBasedOnContext(
      l10n,
      city: city,
      weather: weather,
      temperature: temperature,
    );

    setState(() {
      _accumulatedPromptText = localPrompt;
      _isGeneratingDailyPrompt = false;
    });
  }

  @override
  void dispose() {
    _promptSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final aiService = context.watch<AIService>();
    final settingsService = context.watch<SettingsService>();
    final isAiConfigured = aiService.hasValidApiKey() &&
        settingsService.aiSettings.apiUrl.isNotEmpty &&
        settingsService.aiSettings.model.isNotEmpty;

    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(
        widget.screenWidth > 600 ? 16.0 : (widget.isVerySmallScreen ? 8.0 : 12),
        widget.isVerySmallScreen ? 2.0 : 4.0,
        widget.screenWidth > 600 ? 16.0 : (widget.isVerySmallScreen ? 8.0 : 12),
        widget.isVerySmallScreen ? 8.0 : 12.0,
      ),
      padding: EdgeInsets.all(
        widget.screenWidth > 600
            ? 18.0
            : (widget.isVerySmallScreen ? 10.0 : 14.0),
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.defaultShadow,
        border: Border.all(
          color: theme.colorScheme.outline.withAlpha(30),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lightbulb_outline,
                color: theme.colorScheme.primary,
                size: widget.screenWidth > 600
                    ? 22
                    : (widget.isVerySmallScreen ? 16 : 18),
              ),
              SizedBox(width: widget.isVerySmallScreen ? 4 : 6),
              Text(
                l10n.todayThoughts,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: widget.screenWidth > 600
                      ? 16
                      : (widget.isVerySmallScreen ? 13 : 15),
                ),
              ),
            ],
          ),
          SizedBox(
            height:
                widget.isVerySmallScreen ? 4 : (widget.isSmallScreen ? 6 : 8),
          ),
          if (_isGeneratingDailyPrompt && _accumulatedPromptText.isEmpty)
            _DailyPromptLoading(
              isAiConfigured: isAiConfigured,
              screenWidth: widget.screenWidth,
              isSmallScreen: widget.isSmallScreen,
              isVerySmallScreen: widget.isVerySmallScreen,
            )
          else
            Text(
              _accumulatedPromptText.isNotEmpty
                  ? _accumulatedPromptText.trim()
                  : (isAiConfigured
                      ? l10n.waitingForTodayThoughts
                      : l10n.noTodayThoughts),
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.4,
                fontSize: widget.screenWidth > 600
                    ? 15
                    : (widget.isVerySmallScreen ? 12 : 14),
                color: _accumulatedPromptText.isNotEmpty
                    ? theme.textTheme.bodyMedium?.color
                    : theme.colorScheme.onSurface.withAlpha(120),
              ),
              textAlign: TextAlign.center,
              maxLines: widget.isVerySmallScreen ? 2 : 3,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

class _DailyPromptLoading extends StatelessWidget {
  final bool isAiConfigured;
  final double screenWidth;
  final bool isSmallScreen;
  final bool isVerySmallScreen;

  const _DailyPromptLoading({
    required this.isAiConfigured,
    required this.screenWidth,
    required this.isSmallScreen,
    required this.isVerySmallScreen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: isVerySmallScreen ? 16 : 18,
          height: isVerySmallScreen ? 16 : 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.primary,
          ),
        ),
        SizedBox(height: isVerySmallScreen ? 3 : (isSmallScreen ? 4 : 6)),
        Text(
          isAiConfigured
              ? l10n.loadingTodayThoughts
              : l10n.fetchingDefaultPrompt,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withAlpha(160),
            fontSize: screenWidth > 600 ? 13 : (isVerySmallScreen ? 10 : 12),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
