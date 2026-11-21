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
  agent;

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
