import 'package:flutter/widgets.dart';

import '../gen_l10n/app_localizations.dart';

/// 预设国际化描述构建回调函数
typedef LocalizedDescriptionBuilder = String Function(AppLocalizations l10n);

/// Lottie动画配置管理
///
/// 统一管理应用中使用的所有Lottie动画资源
class LottieConfig {
  // 动画文件路径常量
  static const String _basePath = 'assets/lottie/';

  // 加载动画
  static const String searchLoading = '${_basePath}search_loading.json';
  static const String weatherSearchLoading =
      '${_basePath}weather_search_loading.json';
  static const String customLoading = '${_basePath}custom_loading.json';

  // 状态动画
  static const String notFound = '${_basePath}not_found.json';

  static String _searchLoadingDescription(AppLocalizations l10n) =>
      l10n.lottieSearchLoading;
  static String _weatherSearchLoadingDescription(AppLocalizations l10n) =>
      l10n.lottieWeatherSearchLoading;
  static String _customLoadingDescription(AppLocalizations l10n) =>
      l10n.lottieCustomLoading;
  static String _notFoundDescription(AppLocalizations l10n) =>
      l10n.lottieNotFound;

  // 动画配置预设
  static const Map<String, AnimationPreset> presets = {
    'searchLoading': AnimationPreset(
      path: searchLoading,
      repeat: true,
      size: 48.0,
      description: '搜索中...',
      descriptionBuilder: _searchLoadingDescription,
    ),
    'weatherSearchLoading': AnimationPreset(
      path: weatherSearchLoading,
      repeat: true,
      size: 160.0,
      description: '天气搜索中...',
      descriptionBuilder: _weatherSearchLoadingDescription,
    ),
    'customLoading': AnimationPreset(
      path: customLoading,
      repeat: true,
      size: 80.0,
      description: '加载中...',
      descriptionBuilder: _customLoadingDescription,
    ),
    'notFound': AnimationPreset(
      path: notFound,
      repeat: false,
      size: 120.0,
      description: '未找到相关内容',
      descriptionBuilder: _notFoundDescription,
    ),
  };

  // 根据场景获取推荐动画
  static AnimationPreset getAnimationForScene(LottieScene scene) {
    switch (scene) {
      case LottieScene.searchLoading:
        return presets['searchLoading']!;
      case LottieScene.weatherSearchLoading:
        return presets['weatherSearchLoading']!;
      case LottieScene.customLoading:
        return presets['customLoading']!;
      case LottieScene.notFound:
        return presets['notFound']!;
    }
  }

  /// 获取指定场景在当前 [BuildContext] 语言环境下的国际化描述
  static String getDescriptionForScene(
    LottieScene scene,
    BuildContext context,
  ) {
    return getAnimationForScene(scene).getDescription(context);
  }

  /// 根据 [AppLocalizations] 获取指定场景的国际化描述
  static String getDescriptionForSceneWithL10n(
    LottieScene scene,
    AppLocalizations? l10n,
  ) {
    return getAnimationForScene(scene).descriptionOf(l10n);
  }
}

/// 动画预设配置
class AnimationPreset {
  final String path;
  final bool repeat;
  final double size;
  final String description;
  final Duration? duration;
  final LocalizedDescriptionBuilder? descriptionBuilder;

  const AnimationPreset({
    required this.path,
    required this.repeat,
    required this.size,
    required this.description,
    this.duration,
    this.descriptionBuilder,
  });

  /// 获取国际化描述；若 [l10n] 为空或未设置构建器，则回退到默认的 [description]。
  String descriptionOf([AppLocalizations? l10n]) {
    if (l10n != null && descriptionBuilder != null) {
      return descriptionBuilder!(l10n);
    }
    return description;
  }

  /// 基于 [BuildContext] 解析当前语言环境下的预设描述。
  /// 若上下文中缺失 [AppLocalizations]，则优雅回退至 [description]。
  String getDescription(BuildContext context) {
    final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
    return descriptionOf(l10n);
  }
}

/// Lottie动画使用场景枚举
enum LottieScene {
  searchLoading, // 搜索中动画
  weatherSearchLoading, // 天气搜索中动画
  customLoading, // 自定义加载动画
  notFound, // 未找到相关内容动画
}
