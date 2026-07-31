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
      providers: _parseProviders(json),
      currentProviderId: json['currentProviderId'] as String? ??
          _extractCurrentProviderIdFromLegacy(json),
      enableFailover: json['enableFailover'] ?? true,
    );
  }

  static List<AIProviderSettings> _parseProviders(Map<String, dynamic> json) {
    final providers = json['providers'] as List<dynamic>? ??
        json['availableProviders'] as List<dynamic>?;
    if (providers == null) {
      return [];
    }
    return providers
        .map((e) => AIProviderSettings.fromJson(e as Map<String, dynamic>))
        .toList();
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

  /// 首次启动时的默认值：一个配置都没有。
  ///
  /// 以前这里会塞一条 URL、模型、密钥全空的「默认配置」占位，用户在设置页里
  /// 看到的是一条既不能用也删不掉的假配置。空列表让设置页能正确显示引导态。
  static MultiAISettings defaultSettings() {
    return const MultiAISettings(
      providers: [],
      currentProviderId: null,
      enableFailover: true,
    );
  }
}
