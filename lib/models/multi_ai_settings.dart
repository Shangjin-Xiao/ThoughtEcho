import '../constants/ai_provider_presets.dart';
import 'ai_provider_settings.dart';
import 'ai_task.dart';

/// 模型分配模式。
enum AIRoutingMode {
  /// 基础分配（大小模型自动分流）：主力模型负责深度创作，轻量模型负责快速与后台任务。
  tiered,

  /// 按功能自选（全部自定义）：6 项功能各自独立选择服务或跟随默认。
  custom;

  String get storageKey => name;

  static AIRoutingMode? tryParse(String? raw) {
    final key = raw?.trim();
    if (key == null || key.isEmpty) return null;
    for (final mode in AIRoutingMode.values) {
      if (mode.name == key) {
        return mode;
      }
    }
    return null;
  }
}

class MultiAISettings {
  final List<AIProviderSettings> providers;
  final String? currentProviderId;
  final bool enableFailover;
  final AIRoutingMode? _routingMode;

  /// 基础分配（[AIRoutingMode.tiered]）下指定的轻量服务商配置 ID。
  ///
  /// 为 `null`、目标配置已删除或处于禁用状态时自动跟随 [currentProvider]。
  final String? lightProviderId;

  /// 按具体任务场景显式绑定的服务商配置 ID 映射。
  ///
  /// 未出现在此映射中、或目标配置已被删除/禁用的任务槽位会自动回退到
  /// [currentProvider] 全局默认配置。
  final Map<AITask, String> taskProviderIds;

  /// 标记用户是否已经初始化过「按功能自选」模式。
  ///
  /// 一旦进入过自选模式（无论后续是否将全部槽位手动清空回「跟随默认」），再次从
  /// 基础模式切回自选模式时不再自动用轻量模型覆盖用户的「跟随默认」选择。
  final bool? _customRoutingInitialized;

  const MultiAISettings({
    this.providers = const [],
    this.currentProviderId,
    this.enableFailover = true,
    AIRoutingMode? routingMode,
    this.lightProviderId,
    this.taskProviderIds = const <AITask, String>{},
    bool? customRoutingInitialized,
  })  : _routingMode = routingMode,
        _customRoutingInitialized = customRoutingInitialized;

  bool get customRoutingInitialized =>
      _customRoutingInitialized ??
      (_routingMode == AIRoutingMode.custom || taskProviderIds.isNotEmpty);

  /// 判断指定服务商配置是否需要非空 API Key（本地 Ollama / LM Studio 等免密预设为 `false`）。
  static bool providerRequiresApiKey(AIProviderSettings provider) {
    final preset = AIProviderPresets.bySlugOrId(provider.providerSlug) ??
        AIProviderPresets.matchApiUrl(provider.apiUrl);
    return preset?.requiresApiKey ?? true;
  }

  /// 当前生效的模型分配模式。
  ///
  /// 未显式指定时：若已存在非空 [taskProviderIds] 则归入 [AIRoutingMode.custom]
  /// （保障旧存档与按任务构造实例平滑兼容），否则默认 [AIRoutingMode.tiered]。
  AIRoutingMode get routingMode =>
      _routingMode ??
      (taskProviderIds.isNotEmpty
          ? AIRoutingMode.custom
          : AIRoutingMode.tiered);

  // 便捷的getter，用于获取当前全局默认（主力）provider
  AIProviderSettings? get currentProvider {
    if (currentProviderId == null) return null;
    for (final provider in providers) {
      if (provider.id == currentProviderId) {
        return provider;
      }
    }
    return null;
  }

  /// 查询基础模式下显式指定且当前可用（存在且 `isEnabled == true`）的轻量服务商配置。
  ///
  /// 若未单独指定、目标不存在或已禁用，则返回 `null`（调用侧回退到 [currentProvider]）。
  AIProviderSettings? get lightProvider {
    final assignedId = lightProviderId;
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

  /// 基础模式下轻量任务实际生效的服务商配置（未指定轻量服务或不可用时跟随主力）。
  AIProviderSettings? get effectiveLightProvider =>
      lightProvider ?? currentProvider;

  /// 无状态按任务解析生效的 [AIProviderSettings]。
  ///
  /// - `task == null`：直接返回 [currentProvider]。
  /// - [AIRoutingMode.tiered]：轻量任务（每日提示、对话标题、记忆整理）优先使用
  ///   [lightProvider]，其余深度任务及回退均走 [currentProvider]。
  /// - [AIRoutingMode.custom]：优先使用 [explicitProviderForTask]，未指定或不可用时
  ///   回退到 [currentProvider]。
  AIProviderSettings? resolveProviderForTask(AITask? task) {
    if (task == null) {
      return currentProvider;
    }
    switch (routingMode) {
      case AIRoutingMode.tiered:
        if (task.usesLightTier) {
          return lightProvider ?? currentProvider;
        }
        return currentProvider;
      case AIRoutingMode.custom:
        return explicitProviderForTask(task) ?? currentProvider;
    }
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
    return AITask.customDisplayOrder
        .where((task) => explicitProviderForTask(task)?.id == providerId)
        .toList(growable: false);
  }

  /// 切换模型分配模式。
  ///
  /// 当用户首次从 [AIRoutingMode.tiered] 切到 [AIRoutingMode.custom]，且
  /// [taskProviderIds] 为空但曾选定有效的轻量服务（[lightProvider] 非空）时，
  /// 将 3 项轻量任务平滑预填为该轻量服务，方便用户在此基础上单独微调。
  MultiAISettings withRoutingMode(AIRoutingMode mode) {
    if (mode == routingMode && _routingMode == mode) {
      return this;
    }
    if (mode == AIRoutingMode.custom) {
      if (!customRoutingInitialized && taskProviderIds.isEmpty) {
        final activeLight = lightProvider;
        if (activeLight != null && activeLight.id != currentProvider?.id) {
          final prefilled = <AITask, String>{
            for (final task in AITask.tieredLightTasks) task: activeLight.id,
          };
          return copyWith(
            routingMode: mode,
            taskProviderIds: Map<AITask, String>.unmodifiable(prefilled),
            customRoutingInitialized: true,
          );
        }
      }
      return copyWith(
        routingMode: mode,
        customRoutingInitialized: true,
      );
    }
    return copyWith(routingMode: mode);
  }

  /// 更新基础模式下的轻量服务商配置 ID（传入 `null` 或空串表示跟随主力服务）。
  MultiAISettings withLightProvider(String? providerId) {
    final normalized = providerId?.trim();
    if (normalized == null ||
        normalized.isEmpty ||
        normalized == currentProviderId) {
      return copyWith(lightProviderId: null);
    }
    return copyWith(lightProviderId: normalized);
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
      customRoutingInitialized: true,
    );
  }

  /// 移除指定 [providerId] 的配置，并同步清理 [currentProviderId]、[lightProviderId] 与 [taskProviderIds]。
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

    final String? nextLightId;
    if (lightProviderId == null ||
        lightProviderId == providerId ||
        !remainingIds.contains(lightProviderId)) {
      nextLightId = null;
    } else {
      nextLightId = lightProviderId;
    }

    final cleanedTaskIds = <AITask, String>{
      for (final entry in taskProviderIds.entries)
        if (entry.value != providerId && remainingIds.contains(entry.value))
          entry.key: entry.value,
    };

    return copyWith(
      providers: remaining,
      currentProviderId: nextDefaultId,
      lightProviderId: nextLightId,
      taskProviderIds: Map<AITask, String>.unmodifiable(cleanedTaskIds),
    );
  }

  // 为了向后兼容，保留 availableProviders getter
  List<AIProviderSettings> get availableProviders => providers;

  factory MultiAISettings.fromJson(Map<String, dynamic> json) {
    final rawTaskIds = _parseTaskProviderIds(json['taskProviderIds']);
    final parsedMode = AIRoutingMode.tryParse(json['routingMode'] as String?);
    // 旧版本尚无 sessionTitle 独立槽位，Thoughter 标题跟随 AITask.agent；
    // 升级旧配置时同步继承已显式指定的 agent 服务，避免首条对话消息外发给默认服务。
    final Map<AITask, String> parsedTaskIds;
    if (parsedMode == null &&
        rawTaskIds.containsKey(AITask.agent) &&
        !rawTaskIds.containsKey(AITask.sessionTitle)) {
      parsedTaskIds = Map<AITask, String>.unmodifiable({
        ...rawTaskIds,
        AITask.sessionTitle: rawTaskIds[AITask.agent]!,
      });
    } else {
      parsedTaskIds = rawTaskIds;
    }
    final effectiveMode = parsedMode ??
        (parsedTaskIds.isNotEmpty
            ? AIRoutingMode.custom
            : AIRoutingMode.tiered);
    final rawLightId = json['lightProviderId'];
    final normalizedLightId =
        rawLightId is String && rawLightId.trim().isNotEmpty
            ? rawLightId.trim()
            : null;
    final rawCustomInit = json['customRoutingInitialized'];
    final customInitialized = rawCustomInit is bool
        ? rawCustomInit
        : (effectiveMode == AIRoutingMode.custom || parsedTaskIds.isNotEmpty);

    return MultiAISettings(
      providers: _parseProviders(json),
      currentProviderId: json['currentProviderId'] as String? ??
          _extractCurrentProviderIdFromLegacy(json),
      enableFailover: json['enableFailover'] ?? true,
      routingMode: effectiveMode,
      lightProviderId: normalizedLightId,
      taskProviderIds: parsedTaskIds,
      customRoutingInitialized: customInitialized,
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
      'routingMode': routingMode.storageKey,
      'lightProviderId': lightProviderId,
      'customRoutingInitialized': customRoutingInitialized,
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
    Object? routingMode = _sentinel,
    Object? lightProviderId = _sentinel,
    Map<AITask, String>? taskProviderIds,
    bool? customRoutingInitialized,
  }) {
    return MultiAISettings(
      providers: providers ?? this.providers,
      currentProviderId: identical(currentProviderId, _sentinel)
          ? this.currentProviderId
          : currentProviderId as String?,
      enableFailover: enableFailover ?? this.enableFailover,
      routingMode: identical(routingMode, _sentinel)
          ? _routingMode
          : routingMode as AIRoutingMode?,
      lightProviderId: identical(lightProviderId, _sentinel)
          ? this.lightProviderId
          : lightProviderId as String?,
      taskProviderIds: taskProviderIds != null
          ? Map<AITask, String>.unmodifiable(taskProviderIds)
          : this.taskProviderIds,
      customRoutingInitialized:
          customRoutingInitialized ?? _customRoutingInitialized,
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
      routingMode: AIRoutingMode.tiered,
      lightProviderId: null,
      taskProviderIds: <AITask, String>{},
      customRoutingInitialized: false,
    );
  }
}
