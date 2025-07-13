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

  // 动画配置预设
  static const Map<String, AnimationPreset> presets = {
    'searchLoading': AnimationPreset(
      path: searchLoading,
      repeat: true,
      size: 48.0,
      description: '搜索中...',
    ),
    'weatherSearchLoading': AnimationPreset(
      path: weatherSearchLoading,
      repeat: true,
      size: 160.0,
      description: '天气搜索中...',
    ),
    'customLoading': AnimationPreset(
      path: customLoading,
      repeat: true,
      size: 80.0,
      description: '加载中...',
    ),
    'notFound': AnimationPreset(
      path: notFound,
      repeat: false,
      size: 120.0,
      description: '未找到相关内容',
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
}

/// 动画预设配置
class AnimationPreset {
  final String path;
  final bool repeat;
  final double size;
  final String description;
  final Duration? duration;

  const AnimationPreset({
    required this.path,
    required this.repeat,
    required this.size,
    required this.description,
    this.duration,
  });
}

/// Lottie动画使用场景枚举
enum LottieScene {
  searchLoading, // 搜索中动画
  weatherSearchLoading, // 天气搜索中动画
  customLoading, // 自定义加载动画
  notFound, // 未找到相关内容动画
}
