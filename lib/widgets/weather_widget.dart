import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../gen_l10n/app_localizations.dart';
import '../services/weather_service.dart';
import '../services/location_service.dart';

class WeatherWidget extends StatelessWidget {
  const WeatherWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final weatherService = Provider.of<WeatherService>(context);
    final locationService = Provider.of<LocationService>(context);
    final theme = Theme.of(context);

    // 构建位置显示文本 - 使用 LocationService 的统一方法
    String locationText = locationService.getDisplayLocation();
    if (locationText.isEmpty) {
      if (locationService.province != null) {
        // 如果没有城市但有省份
        locationText = locationService.province!;
      } else {
        locationText = l10n.unknownLocation;
      }
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.cloud,
                      color: theme.colorScheme.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.currentWeather,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                // 显示位置信息的小标签
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 12,
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        locationText,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Icon(
              weatherService.weatherIcon == 'error'
                  ? Icons.error_outline
                  : (weatherService.weatherIcon != null
                        ? weatherService.getWeatherIconData()
                        : Icons.cloud_queue),
              size: 40, // 稍微放大图标
              color: weatherService.weatherIcon == 'error'
                  ? Colors.red
                  : theme.colorScheme.primary,
            ),
            const SizedBox(height: 8),
            Text(
              WeatherService.getLocalizedWeatherDescription(
                AppLocalizations.of(context),
                weatherService.currentWeather ?? 'unknown',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              weatherService.temperature ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22, // 稍微放大温度字体
                fontWeight: FontWeight.bold,
              ),
            ),
            // 移除了旧的位置标签，因为现在放到了顶部
          ],
        ),
      ),
    );
  }
}
