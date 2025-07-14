import 'ai_provider_settings.dart';

class MultiAISettings {
  final List<AIProviderSettings> providers;
  final String? currentProviderId;
  final bool enableFailover;

  const MultiAISettings({
    this.providers = const [],
    this.currentProviderId,
    this.enableFailover = true,
  });

  // 便捷的getter，用于获取当前provider
  AIProviderSettings? get currentProvider {
    if (currentProviderId == null) return null;
    try {
      return providers.firstWhere((p) => p.id == currentProviderId);
    } catch (e) {
      return null;
    }
  }

  // 为了向后兼容，保留 availableProviders getter
  List<AIProviderSettings> get availableProviders => providers;
  factory MultiAISettings.fromJson(Map<String, dynamic> json) {
    return MultiAISettings(
      providers: (json['providers'] as List<dynamic>?)
              ?.map(
                (e) => AIProviderSettings.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          (json['availableProviders'] as List<dynamic>?)
              ?.map(
                (e) => AIProviderSettings.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
      currentProviderId: json['currentProviderId'] as String? ??
          _extractCurrentProviderIdFromLegacy(json),
      enableFailover: json['enableFailover'] ?? true,
    );
  }

  // 辅助方法：从旧版本的 currentProvider 对象中提取 ID
  static String? _extractCurrentProviderIdFromLegacy(
    Map<String, dynamic> json,
  ) {
    final currentProvider = json['currentProvider'];
    if (currentProvider != null && currentProvider is Map<String, dynamic>) {
      return currentProvider['id'] as String?;
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'providers': providers.map((e) => e.toJson()).toList(),
      'availableProviders': providers.map((e) => e.toJson()).toList(), // 为了向后兼容
      'currentProviderId': currentProviderId,
      'currentProvider': currentProvider?.toJson(), // 为了向后兼容
      'enableFailover': enableFailover,
    };
  }

  MultiAISettings copyWith({
    List<AIProviderSettings>? providers,
    String? currentProviderId,
    bool? enableFailover,
  }) {
    return MultiAISettings(
      providers: providers ?? this.providers,
      currentProviderId: currentProviderId ?? this.currentProviderId,
      enableFailover: enableFailover ?? this.enableFailover,
    );
  }

  // 静态方法：创建默认设置
  static MultiAISettings defaultSettings() {
    return MultiAISettings(
      providers: [AIProviderSettings.defaultSettings()],
      currentProviderId: null,
      enableFailover: true,
    );
  }
}
