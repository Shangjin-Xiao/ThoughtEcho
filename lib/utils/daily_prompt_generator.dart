import 'dart:math';
import '../services/weather_service.dart';
import '../gen_l10n/app_localizations.dart';

class DailyPromptGenerator {
  // 获取默认的每日提示（国际化版本）
  static String getDefaultPrompt(AppLocalizations l10n) {
    // 使用日期为种子选择一个提示，确保同一天显示相同提示
    final today = DateTime.now();
    final dayOfYear = today.difference(DateTime(today.year, 1, 1)).inDays;

    // 所有默认提示
    final prompts = [
      l10n.promptDefault1,
      l10n.promptDefault2,
      l10n.promptDefault3,
      l10n.promptDefault4,
      l10n.promptDefault5,
      l10n.promptDefault6,
      l10n.promptDefault7,
      l10n.promptDefault8,
      l10n.promptDefault9,
      l10n.promptDefault10,
      l10n.promptDefault11,
      l10n.promptDefault12,
    ];

    final index = dayOfYear % prompts.length;
    return prompts[index];
  }

  // 根据时间和天气生成提示
  static String generatePromptBasedOnContext(
    AppLocalizations l10n, {
    String? city,
    String? weather,
    String? temperature,
  }) {
    final now = DateTime.now();
    final hour = now.hour;

    String timeOfDay;
    if (hour >= 5 && hour < 12) {
      timeOfDay = 'morning';
    } else if (hour >= 12 && hour < 18) {
      timeOfDay = 'afternoon';
    } else if (hour >= 18 && hour < 23) {
      timeOfDay = 'evening';
    } else {
      timeOfDay = 'lateNight';
    }

    List<String> prompts = [];

    // 通用积极提示
    prompts.addAll([
      l10n.promptGeneric1,
      l10n.promptGeneric2,
      l10n.promptGeneric3,
      l10n.promptGeneric4,
      l10n.promptGeneric5,
    ]);

    // 基于时间的提示
    _addTimeBasedPrompts(l10n, prompts, timeOfDay);

    // 获取天气key（只查找一次）
    String? weatherKey;
    if (weather != null) {
      weatherKey = WeatherService.weatherKeyToLabel.keys.firstWhere(
        (k) =>
            weather == k || weather == WeatherService.getWeatherDescription(k),
        orElse: () => weather,
      );
    }

    // 基于时间和天气的组合提示
    if (weatherKey != null) {
      _addTimeWeatherPrompts(l10n, prompts, timeOfDay, weatherKey);
      _addWeatherPrompts(l10n, prompts, weatherKey);
    }

    // 基于温度的提示
    _addTemperaturePrompts(l10n, prompts, temperature);

    // 基于城市的提示
    if (city != null && city.isNotEmpty) {
      prompts.add(l10n.promptCityContext(city));
    }

    // 随机选择一条提示
    if (prompts.isEmpty) {
      return l10n.promptFallback;
    }

    final random = Random();
    return prompts[random.nextInt(prompts.length)];
  }

  // 添加基于时间的提示
  static void _addTimeBasedPrompts(
    AppLocalizations l10n,
    List<String> prompts,
    String timeOfDay,
  ) {
    switch (timeOfDay) {
      case 'morning':
        prompts.addAll([
          l10n.promptMorning1,
          l10n.promptMorning2,
          l10n.promptMorning3,
          l10n.promptMorning4,
        ]);
        break;
      case 'afternoon':
        prompts.addAll([
          l10n.promptAfternoon1,
          l10n.promptAfternoon2,
          l10n.promptAfternoon3,
          l10n.promptAfternoon4,
        ]);
        break;
      case 'evening':
        prompts.addAll([
          l10n.promptEvening1,
          l10n.promptEvening2,
          l10n.promptEvening3,
          l10n.promptEvening4,
        ]);
        break;
      case 'lateNight':
        prompts.addAll([
          l10n.promptLateNight1,
          l10n.promptLateNight2,
          l10n.promptLateNight3,
          l10n.promptLateNight4,
        ]);
        break;
    }
  }

  // 添加基于时间和天气组合的提示
  static void _addTimeWeatherPrompts(
    AppLocalizations l10n,
    List<String> prompts,
    String timeOfDay,
    String weatherKey,
  ) {
    switch (timeOfDay) {
      case 'morning':
        switch (weatherKey) {
          case 'clear':
            prompts.add(l10n.promptClearMorning);
            break;
          case 'rain':
            prompts.add(l10n.promptRainMorning);
            break;
          case 'cloudy':
          case 'partly_cloudy':
            prompts.add(l10n.promptCloudyMorning);
            break;
        }
        break;
      case 'afternoon':
        switch (weatherKey) {
          case 'clear':
            prompts.add(l10n.promptClearAfternoon);
            break;
          case 'rain':
            prompts.add(l10n.promptRainAfternoon);
            break;
        }
        break;
      case 'evening':
      case 'lateNight':
        switch (weatherKey) {
          case 'clear':
            prompts.add(l10n.promptClearEvening);
            break;
          case 'rain':
            prompts.add(l10n.promptRainEvening);
            break;
          case 'wind':
            prompts.add(l10n.promptWindEvening);
            break;
        }
        break;
    }
  }

  // 添加基于天气的通用积极提示
  static void _addWeatherPrompts(
    AppLocalizations l10n,
    List<String> prompts,
    String weatherKey,
  ) {
    switch (weatherKey) {
      case 'clear':
        prompts.addAll([
          l10n.promptClearWeather1,
          l10n.promptClearWeather2,
        ]);
        break;
      case 'rain':
        prompts.addAll([
          l10n.promptRainWeather1,
          l10n.promptRainWeather2,
        ]);
        break;
      case 'cloudy':
      case 'partly_cloudy':
        prompts.addAll([
          l10n.promptCloudyWeather1,
          l10n.promptCloudyWeather2,
        ]);
        break;
      case 'snow':
        prompts.addAll([
          l10n.promptSnowWeather1,
          l10n.promptSnowWeather2,
        ]);
        break;
    }
  }

  // 添加基于温度的积极提示
  static void _addTemperaturePrompts(
    AppLocalizations l10n,
    List<String> prompts,
    String? temperature,
  ) {
    if (temperature == null) return;

    try {
      final tempValue = double.parse(temperature.replaceAll('°C', '').trim());
      if (tempValue > 28) {
        prompts.add(l10n.promptHotWeather);
      } else if (tempValue < 10) {
        prompts.add(l10n.promptColdWeather);
      }
    } catch (e) {
      // 忽略温度解析错误
    }
  }
}
