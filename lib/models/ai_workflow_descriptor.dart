enum AIWorkflowId {
  polish,
  continueWriting,
  deepAnalysis,
  sourceAnalysis,
  insights,
  webFetch,
}

class AIWorkflowDescriptor {
  const AIWorkflowDescriptor({
    required this.id,
    required this.command,
    required this.displayName,
    required this.requiresBoundNote,
    required this.allowedInStandardMode,
    required this.allowAgentNaturalLanguageTrigger,
    required this.producesEditableResult,
    this.description,
    this.icon,
    this.naturalLanguageTriggers = const [],
  });

  final AIWorkflowId id;
  final String command;
  final String displayName;
  final bool requiresBoundNote;
  final bool allowedInStandardMode;
  final bool allowAgentNaturalLanguageTrigger;
  final bool producesEditableResult;
  final String? description; // 简短描述
  final String? icon; // icon标记符
  final List<String> naturalLanguageTriggers; // 自然语言触发关键词
}

class AIWorkflowCommandRegistry {
  static const Map<String, AIWorkflowId> aliases = <String, AIWorkflowId>{
    '/润色': AIWorkflowId.polish,
    '/polish': AIWorkflowId.polish,
    '/续写': AIWorkflowId.continueWriting,
    '/continue': AIWorkflowId.continueWriting,
    '/深度分析': AIWorkflowId.deepAnalysis,
    '/分析来源': AIWorkflowId.sourceAnalysis,
    '/智能洞察': AIWorkflowId.insights,
    '/web': AIWorkflowId.webFetch,
  };

  // 自然语言触发关键词映射
  static const Map<AIWorkflowId, List<String>> naturalLanguageTriggers =
      <AIWorkflowId, List<String>>{
    AIWorkflowId.polish: [
      '润色',
      '修饰',
      '打磨',
      '改进表达',
      '优化文字',
      '美化',
      '帮我润色',
    ],
    AIWorkflowId.continueWriting: [
      '续写',
      '继续',
      '延伸',
      '展开',
      '接下来',
      '帮我续写',
      '继续写',
    ],
    AIWorkflowId.deepAnalysis: [
      '深度分析',
      '深入分析',
      '分析内涵',
      '洞察',
      '分析一下',
      '深层分析',
      '帮我分析',
    ],
    AIWorkflowId.sourceAnalysis: [
      '分析来源',
      '验证来源',
      '查证来源',
      '来源',
      '出处',
      '这是谁说的',
    ],
    AIWorkflowId.insights: [
      '智能洞察',
      '生成洞察',
      '关联',
      '扩展',
      '这告诉我们',
      '背景',
      '联想',
    ],
    AIWorkflowId.webFetch: [
      '网页',
      '抓取',
      '获取',
      '网址',
      '链接',
      '查看网页',
      '获取网页内容',
    ],
  };

  static AIWorkflowId? match(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    final normalized =
        trimmed.startsWith('／') ? '/${trimmed.substring(1)}' : trimmed;
    final primaryToken = normalized.split(RegExp(r'\s+')).first;
    final candidates = <String>{
      normalized,
      normalized.toLowerCase(),
      primaryToken,
      primaryToken.toLowerCase(),
    };
    for (final candidate in candidates) {
      final match = aliases[candidate];
      if (match != null) {
        return match;
      }
    }
    return null;
  }

  /// 检测自然语言触发（返回匹配的WorkflowId和匹配度分数）
  static (AIWorkflowId, double)? detectNaturalLanguageTrigger(String text) {
    final lowerText = text.toLowerCase();
    double bestScore = 0;
    AIWorkflowId? bestMatch;

    naturalLanguageTriggers.forEach((workflowId, triggers) {
      for (final trigger in triggers) {
        final triggerLower = trigger.toLowerCase();
        if (lowerText.contains(triggerLower)) {
          // 完全匹配得分更高
          final score = (trigger.length / lowerText.length).clamp(0.5, 1.0);
          if (score > bestScore) {
            bestScore = score;
            bestMatch = workflowId;
          }
        }
      }
    });

    if (bestMatch != null) {
      return (bestMatch!, bestScore);
    }
    return null;
  }
}
