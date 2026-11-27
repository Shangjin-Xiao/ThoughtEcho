/// 用户可独立分配 AI 服务配置的面向场景任务槽位。
///
/// 未单独绑定（或绑定的服务商已被删除/禁用）的任务槽位一律无状态回退到
/// `MultiAISettings.currentProvider` 全局默认配置，不在运行期来回修改全局默认项。
enum AITask {
  /// 每日提示 / 今日思考（`AIService.streamGenerateDailyPrompt`）
  dailyInsight,

  /// 周期洞察（周报 / 月报 / 年报洞察与分析）
  periodicInsight,

  /// Dreaming 后台长期记忆归纳（`DreamingService` -> `AIService.completeForBackgroundSummary`）
  dreaming,

  /// Thoughter 对话与 Agent 工具调用
  agent,

  /// 笔记分享卡片排版生成（`AICardGenerationService` -> `AIService.generateSVG`）
  cardGeneration,

  /// 对话会话标题生成（`AIService.generateSessionTitle`）
  sessionTitle;

  /// 基础模式（大小模型分流）下归属主力模型的深度理解、长期记忆整理与创作任务。
  static const List<AITask> tieredPrimaryTasks = <AITask>[
    AITask.agent,
    AITask.dreaming,
    AITask.cardGeneration,
  ];

  /// 基础模式（大小模型分流）下归属轻量模型的快速响应与周期概览任务。
  static const List<AITask> tieredLightTasks = <AITask>[
    AITask.dailyInsight,
    AITask.periodicInsight,
    AITask.sessionTitle,
  ];

  /// 全部自定义模式下展示给用户的 6 项功能顺序。
  static const List<AITask> customDisplayOrder = <AITask>[
    AITask.agent,
    AITask.dailyInsight,
    AITask.periodicInsight,
    AITask.cardGeneration,
    AITask.sessionTitle,
    AITask.dreaming,
  ];

  /// 判断当前任务在基础模式下是否归属轻量模型。
  bool get usesLightTier =>
      this == AITask.dailyInsight ||
      this == AITask.periodicInsight ||
      this == AITask.sessionTitle;

  /// 持久化与备份 JSON 中使用的稳定键名。
  String get storageKey => name;

  /// 从持久化字符串安全解析 [AITask]，未知键名返回 `null` 以保证向前/向后兼容。
  static AITask? tryParse(String? raw) {
    final key = raw?.trim();
    if (key == null || key.isEmpty) return null;
    for (final task in AITask.values) {
      if (task.name == key) {
        return task;
      }
    }
    return null;
  }
}
