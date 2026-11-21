import 'ai_provider_settings.dart';
import 'ai_task.dart';

class MultiAISettings {
  final List<AIProviderSettings> providers;
  final String? currentProviderId;
  final bool enableFailover;

  /// 按具体任务场景显式绑定的服务商配置 ID 映射。
  ///
  /// 未出现在此映射中、或目标配置已被删除/禁用的任务槽位会自动回退到
  /// [currentProvider] 全局默认配置。
  final Map<AITask, String> taskProviderIds;

  const MultiAISettings({
    this.providers = const [],
    this.currentProviderId,
    this.enableFailover = true,
    this.taskProviderIds = const <AITask, String>{},
  });

  // 便捷的getter，用于获取当前全局默认 provider
  AIProviderSettings? get currentProvider {
    if (currentProviderId == null) return null;
    for (final provider in providers) {
      if (provider.id == currentProviderId) {
        return provider;
      }
    }
    return null;
  }

  /// 无状态按任务解析生效的 [AIProviderSettings]。
  ///
  /// 若 [task] 非空，且 [taskProviderIds] 中绑定的配置在 [providers] 中存在并处于启用状态
  /// （`isEnabled == true`），则返回该配置；否则回退到 [currentProvider]。
  AIProviderSettings? resolveProviderForTask(AITask? task) {
    if (task != null) {
      final explicit = explicitProviderForTask(task);
      if (explicit != null) {
        return explicit;
      }
    }
    return currentProvider;
  }

  /// 查询某个任务显式绑定且当前可用（存在且 `isEnabled == true`）的服务商配置。
  ///
  /// 若该任务处于「跟随默认」状态，或原绑定配置已不存在/已禁用，则返回 `null`。
  AIProviderSettings? explicitProviderForTask(AITask task) {
    final assignedId = taskProviderIds[task];
    if (assignedId == null || assignedId.isEmpty) {
      return null;
    }
    for (final provider in providers) {
      if (provider.id == assignedId && provider.isEnabled) {
        return provider;
      }
    }
    return null;
  }

  /// 查询某个任务当前显式生效的配置 ID；若跟随默认则返回 `null`。
  String? explicitProviderIdForTask(AITask task) =>
      explicitProviderForTask(task)?.id;

  /// 返回当前显式绑定到指定 [providerId]（且该配置存在并启用）的所有任务槽位。
  List<AITask> tasksAssignedTo(String providerId) {
    if (providerId.isEmpty) return const <AITask>[];
    return AITask.values
        .where((task) => explicitProviderForTask(task)?.id == providerId)
        .toList(growable: false);
  }

  /// 返回更新单个任务绑定后的新 [MultiAISettings]（不改动 [currentProviderId]）。
  ///
  /// 传入 `providerId == null` 或空字符串时表示恢复「跟随全局默认服务」。
  MultiAISettings withTaskProvider(AITask task, String? providerId) {
    final nextMap = Map<AITask, String>.from(taskProviderIds);
    final normalized = providerId?.trim();
    if (normalized == null || normalized.isEmpty) {
      nextMap.remove(task);
    } else {
      nextMap[task] = normalized;
    }
    return copyWith(
      taskProviderIds: Map<AITask, String>.unmodifiable(nextMap),
    );
  }

  /// 移除指定 [providerId] 的配置，并同步清理 [currentProviderId] 与 [taskProviderIds]。
  MultiAISettings withoutProvider(String providerId) {
    final remaining =
        providers.where((p) => p.id != providerId).toList(growable: false);
    final remainingIds = remaining.map((p) => p.id).toSet();

    final String? nextDefaultId;
    if (currentProviderId == providerId) {
      nextDefaultId = remaining.isNotEmpty ? remaining.first.id : null;
    } else if (currentProviderId != null &&
        !remainingIds.contains(currentProviderId)) {
      nextDefaultId = remaining.isNotEmpty ? remaining.first.id : null;
    } else {
      nextDefaultId = currentProviderId;
    }

    final cleanedTaskIds = <AITask, String>{
      for (final entry in taskProviderIds.entries)
        if (entry.value != providerId && remainingIds.contains(entry.value))
          entry.key: entry.value,
    };

    return copyWith(
      providers: remaining,
      currentProviderId: nextDefaultId,
      taskProviderIds: Map<AITask, String>.unmodifiable(cleanedTaskIds),
    );
  }

  // 为了向后兼容，保留 availableProviders getter
  List<AIProviderSettings> get availableProviders => providers;

  factory MultiAISettings.fromJson(Map<String, dynamic> json) {
    return MultiAISettings(
      providers: _parseProviders(json),
      currentProviderId: json['currentProviderId'] as String? ??
          _extractCurrentProviderIdFromLegacy(json),
      enableFailover: json['enableFailover'] ?? true,
      taskProviderIds: _parseTaskProviderIds(json['taskProviderIds']),
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

  static Map<AITask, String> _parseTaskProviderIds(Object? raw) {
    if (raw is! Map) {
      return const <AITask, String>{};
    }
    final parsed = <AITask, String>{};
    for (final entry in raw.entries) {
      final rawKey = entry.key;
      final rawValue = entry.value;
      if (rawKey is! String || rawValue is! String) continue;
      final task = AITask.tryParse(rawKey);
      final providerId = rawValue.trim();
      if (task != null && providerId.isNotEmpty) {
        parsed[task] = providerId;
      }
    }
    return Map<AITask, String>.unmodifiable(parsed);
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
      'taskProviderIds': <String, String>{
        for (final entry in taskProviderIds.entries)
          entry.key.storageKey: entry.value,
      },
    };
  }

  static const Object _sentinel = Object();

  MultiAISettings copyWith({
    List<AIProviderSettings>? providers,
    Object? currentProviderId = _sentinel,
    bool? enableFailover,
    Map<AITask, String>? taskProviderIds,
  }) {
    return MultiAISettings(
      providers: providers ?? this.providers,
      currentProviderId: identical(currentProviderId, _sentinel)
          ? this.currentProviderId
          : currentProviderId as String?,
      enableFailover: enableFailover ?? this.enableFailover,
      taskProviderIds: taskProviderIds != null
          ? Map<AITask, String>.unmodifiable(taskProviderIds)
          : this.taskProviderIds,
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
      taskProviderIds: <AITask, String>{},
    );
  }
}
