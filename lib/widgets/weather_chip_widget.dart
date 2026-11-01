import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/add_note_controller.dart';
import '../gen_l10n/app_localizations.dart';
import '../models/quote_model.dart';
import '../services/weather_service.dart';

/// 快捷记事弹窗中的天气 Chip 局部状态组件。
///
/// 直接监听 [AddNoteController] 及 [WeatherService] 的变更，
/// 仅在天气状态变化时局部重绘，避免触发父级 Dialog 整体 Rebuild。
class WeatherChipWidget extends StatelessWidget {
  final AddNoteController controller;
  final Quote? initialQuote;
  final WeatherService? weatherService;
  final WeatherService? Function()? getWeatherService;
  final Future<void> Function()? onShowWeatherDialog;
  final Future<void> Function()? onShowNewNoteWeatherDialog;
  final VoidCallback? onEnsureMetadataServices;
  final VoidCallback? onCancelAutoAttachPlan;

  const WeatherChipWidget({
    super.key,
    required this.controller,
    this.initialQuote,
    this.weatherService,
    this.getWeatherService,
    this.onShowWeatherDialog,
    this.onShowNewNoteWeatherDialog,
    this.onEnsureMetadataServices,
    this.onCancelAutoAttachPlan,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final weaService = getWeatherService?.call() ??
        weatherService ??
        _readServiceOrNull<WeatherService>(context);

    final listenable = weaService != null
        ? Listenable.merge([controller, weaService])
        : controller;

    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final liveWeatherService = getWeatherService?.call() ??
            weatherService ??
            _readServiceOrNull<WeatherService>(context);

        final weather = liveWeatherService?.currentWeather;
        final formattedWeather = liveWeatherService?.getFormattedWeather(l10n);

        return Tooltip(
          message: weather != null && liveWeatherService != null
              ? l10n.addWeatherWithValue(formattedWeather ?? weather)
              : l10n.addWeatherInfo,
          child: FilterChip(
            key: const ValueKey('add_note_weather_chip'),
            showCheckmark: false,
            avatar: Icon(
              weather != null && liveWeatherService != null
                  ? liveWeatherService.getWeatherIconData()
                  : Icons.cloud,
              color: controller.includeWeather
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              size: 18,
            ),
            label: Text(l10n.weather),
            selected: controller.includeWeather,
            onSelected: (value) async {
              // 编辑模式下统一弹对话框
              if (initialQuote != null) {
                await onShowWeatherDialog?.call();
                return;
              }
              // 新建模式：已勾选天气时，点击弹出详情/移除对话框
              if (controller.includeWeather) {
                await onShowNewNoteWeatherDialog?.call();
                return;
              }
              // 新建模式：首次勾选
              if (value) {
                controller.includeWeather = true;
                // 勾选时获取天气
                onEnsureMetadataServices?.call();
                controller.fetchWeatherForNewNote();
              } else {
                // 取消勾选要连在途标志一起放掉
                onCancelAutoAttachPlan?.call();
                controller.removeNewWeather();
              }
            },
            selectedColor: theme.colorScheme.primaryContainer,
          ),
        );
      },
    );
  }

  static T? _readServiceOrNull<T>(BuildContext context) {
    try {
      return Provider.of<T?>(context, listen: false);
    } catch (_) {
      return null;
    }
  }
}
