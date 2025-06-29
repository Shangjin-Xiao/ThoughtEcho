import 'package:flutter/material.dart';

/// 引导页面配置模型
class OnboardingPageData {
  final String title;
  final String subtitle;
  final String? description;
  final List<OnboardingFeature>? features;
  final OnboardingPageType type;

  const OnboardingPageData({
    required this.title,
    required this.subtitle,
    this.description,
    this.features,
    required this.type,
  });
}

/// 引导页面类型
enum OnboardingPageType {
  welcome, // 欢迎页面
  features, // 功能展示页面
  preferences, // 偏好设置页面
  complete, // 完成页面
}

/// 引导功能展示项
class OnboardingFeature {
  final String title;
  final String description;
  final IconData icon;
  final bool isHighlight;

  const OnboardingFeature({
    required this.title,
    required this.description,
    required this.icon,
    this.isHighlight = false,
  });
}

/// 用户偏好设置项
class OnboardingPreference<T> {
  final String key;
  final String title;
  final String description;
  final T defaultValue;
  final List<OnboardingPreferenceOption<T>>? options;
  final OnboardingPreferenceType type;

  const OnboardingPreference({
    required this.key,
    required this.title,
    required this.description,
    required this.defaultValue,
    this.options,
    required this.type,
  });
}

/// 偏好设置选项
class OnboardingPreferenceOption<T> {
  final T value;
  final String label;
  final String? description;

  const OnboardingPreferenceOption({
    required this.value,
    required this.label,
    this.description,
  });
}

/// 偏好设置类型
enum OnboardingPreferenceType {
  toggle, // 开关
  radio, // 单选
  multiSelect, // 多选
}

/// 引导状态管理
class OnboardingState {
  final int currentPageIndex;
  final bool isCompleting;
  final Map<String, dynamic> preferences;
  final bool canGoNext;
  final bool canGoPrevious;

  const OnboardingState({
    this.currentPageIndex = 0,
    this.isCompleting = false,
    this.preferences = const {},
    this.canGoNext = true,
    this.canGoPrevious = false,
  });

  OnboardingState copyWith({
    int? currentPageIndex,
    bool? isCompleting,
    Map<String, dynamic>? preferences,
    bool? canGoNext,
    bool? canGoPrevious,
  }) {
    return OnboardingState(
      currentPageIndex: currentPageIndex ?? this.currentPageIndex,
      isCompleting: isCompleting ?? this.isCompleting,
      preferences: preferences ?? this.preferences,
      canGoNext: canGoNext ?? this.canGoNext,
      canGoPrevious: canGoPrevious ?? this.canGoPrevious,
    );
  }

  /// 更新单个偏好设置
  OnboardingState updatePreference(String key, dynamic value) {
    final newPreferences = Map<String, dynamic>.from(preferences);
    newPreferences[key] = value;
    return copyWith(preferences: newPreferences);
  }

  /// 获取偏好设置值
  T? getPreference<T>(String key) {
    return preferences[key] as T?;
  }
}
