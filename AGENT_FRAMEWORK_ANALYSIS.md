# ThoughtEcho Agent 框架改进建议报告

**分析时间**: 2026-04-18  
**对标项目**: Claude Code (Anthropic)  
**分析范围**: Agent 架构、Tool 系统、权限管理、错误处理、性能优化

---

## 执行摘要

ThoughtEcho 的 Agent 框架采用了**清晰的 Tool Calling 架构**，相比 Claude Code 的 155 个工具实现，目前仅实现了 4 个专业工具。整体架构基础良好，但在以下关键领域存在显著改进空间：

| 维度 | ThoughtEcho 现状 | Claude Code 参考 | 改进优先级 |
|------|-----------------|------------------|----------|
| **工具系统** | 4 个工具（web_fetch, web_search, explore_notes, propose_edit） | 155+ 工具 + 动态发现 | 🔴 高 |
| **并发执行** | 顺序执行（无并发） | 智能批处理 + 并发安全检查 | 🔴 高 |
| **权限管理** | 无（信任所有工具） | 完整的权限系统（hook + 规则) | 🔴 高 |
| **错误处理** | 基础（try-catch + 消息截断） | 多层级（错误分类、上下文恢复、重试） | 🟡 中 |
| **工具超时** | 45 秒单一超时 | 分类超时（读写分离、优先级控制） | 🟡 中 |
| **结果容量** | 无限制（可能 OOM） | 50KB/工具, 200KB/消息, 智能溢出处理 | 🔴 高 |
| **调试与分析** | 基础事件流 | 完整的 Tool Use 摘要、分析、追踪 | 🟡 中 |
| **工具发现** | 静态注册 | 动态工具搜索 (ToolSearchTool) | 🟡 中 |

---

## 第一部分: 工具系统 (Tool System)

### 1.1 Claude Code 工具架构对标

**Claude Code 的工具生态**:
- **155+ 工具实现** 跨越文件、网络、Shell、代码、协作等领域
- **分类模型**：
  - 核心工具（File Read/Write, Bash, PowerShell）
  - 代码工具（File Edit, Notebook Edit）
  - 网络工具（Web Search, Web Fetch）
  - 协作工具（Task Create/Update, Send Message）
  - 系统工具（MCP Tool, Skill Tool, Tool Search）

**ThoughtEcho 当前状态**:
```dart
lib/services/agent_tools/
├── web_fetch_tool.dart      (75 行)  ✓ 已实现
├── web_search_tool.dart     (155 行) ✓ 已实现  
├── explore_notes_tool.dart  (202 行) ✓ 已实现
└── propose_edit_tool.dart   (97 行)  ✓ 已实现
```

### 1.2 建议的工具扩展计划（分阶段）

#### **第一阶段（即时）- 完善现有工具** 
- [ ] **WebFetchTool 增强**
  - 添加重试逻辑（超时恢复）
  - HTML 格式检测与智能清理
  - 内容类型识别（PDF、JSON、HTML）
  - 代理支持（针对地理限制）

- [ ] **WebSearchTool 增强**
  - 缓存搜索结果（24h 去重）
  - 搜索排序选项（相关度/时间）
  - 多语言搜索质量评分

- [ ] **ExploreNotesTool 增强**
  - 笔记相关度排序（向量相似度/BM25）
  - 分类过滤与日期范围查询
  - 结果分页（防止超大返回）

#### **第二阶段（1-2 周）- 核心工具** 
- [ ] **NotesEditTool** - 原生笔记编辑
  - 参数: `noteId`, `content`, `operation` (append/replace/insert)
  - 权限: 仅编辑 Agent 创建的笔记
  
- [ ] **QuoteQueryTool** - 高级查询
  - 参数: `query`, `filters` (category, dateRange, rating)
  - 返回: 结构化查询结果

#### **第三阶段（优化）- 高级工具**
- [ ] **TemplateTool** - 卡片模板应用
- [ ] **AnalyzeTool** - 数据分析与洞察
- [ ] **SchdulerTool** - 定时任务（与 smart_push 集成）

### 1.3 工具注册机制改进

**现在** (静态硬编码):
```dart
// main.dart - Agent 初始化时硬编码工具列表
final agentService = AgentService(
  settingsService: settingsService,
  tools: [
    WebFetchTool(webFetchService),
    WebSearchTool(settingsService),
    ExploreNotesTool(databaseService),
    ProposeEditTool(databaseService),
  ],
);
```

**建议** (动态发现与注册):
```dart
// lib/services/agent_tool_registry.dart - 新增

class AgentToolRegistry {
  /// 动态工具注册与发现
  static const toolModules = [
    'web_fetch',      // 总是启用
    'web_search',     // 总是启用
    'explore_notes',  // 基于用户权限
    'edit_notes',     // 基于特性标志
  ];

  /// 从特性标志或权限系统获取可用工具
  static Future<List<AgentTool>> discoverAvailableTools({
    required SettingsService settings,
    required DatabaseService db,
    required bool isDevMode,
  }) async {
    final tools = <AgentTool>[];
    
    for (final module in toolModules) {
      final shouldEnable = await _checkToolEnabled(
        module,
        settings: settings,
        isDevMode: isDevMode,
      );
      
      if (shouldEnable) {
        tools.add(await _instantiateTool(module, db));
      }
    }
    
    return tools;
  }
  
  static Future<bool> _checkToolEnabled(
    String toolName, {
    required SettingsService settings,
    required bool isDevMode,
  }) async {
    // 检查特性标志 (FeatureGuide)
    // 检查用户权限
    // 检查平台限制 (Web 无 I/O)
    return true; // 示例
  }
}
```

---

## 第二部分: 并发与性能优化

### 2.1 Claude Code 的智能批处理

Claude Code 使用 **分析工具并发安全性** 的方式：

```typescript
// 简化版逻辑
function partitionToolCalls(toolUseMessages, toolUseContext) {
  return toolUseMessages.reduce((batches, toolUse) => {
    const isConcurrencySafe = tool.isConcurrencySafe(toolUse.input);
    
    if (isConcurrencySafe && lastBatch.isConcurrencySafe) {
      // 读操作可并发
      lastBatch.blocks.push(toolUse);
    } else {
      // 写操作必须顺序执行
      batches.push({ isConcurrencySafe: false, blocks: [toolUse] });
    }
    return batches;
  });
}
```

### 2.2 ThoughtEcho 改进方案

**现在** (顺序执行):
```dart
// agent_service.dart:286
for (final rawToolCall in rawToolCalls) {
  final result = await _executeToolSafely(parsedToolCall);  // 一个接一个
  // ...
}
```

**建议** (并发执行):
```dart
// lib/services/agent_tool_executor.dart - 新增

class ToolBatch {
  final bool isConcurrencySafe;  // 是否可并发执行
  final List<ToolCall> calls;
  
  ToolBatch({
    required this.isConcurrencySafe,
    required this.calls,
  });
}

class AgentToolExecutor {
  /// 分析工具调用并分组（读操作可并发，写操作顺序）
  static List<ToolBatch> partitionToolCalls(List<ToolCall> calls) {
    final batches = <ToolBatch>[];
    
    for (final call in calls) {
      final tool = _findTool(call.name);
      final isSafe = tool?.isConcurrencySafe ?? false;
      
      final lastBatch = batches.lastOrNull;
      if (isSafe && lastBatch?.isConcurrencySafe == true) {
        lastBatch!.calls.add(call);
      } else {
        batches.add(ToolBatch(
          isConcurrencySafe: isSafe,
          calls: [call],
        ));
      }
    }
    return batches;
  }
  
  /// 执行工具调用（智能并发）
  static Future<List<ToolResult>> executeBatches(
    List<ToolBatch> batches,
  ) async {
    final results = <ToolResult>[];
    
    for (final batch in batches) {
      if (batch.isConcurrencySafe) {
        // 并发执行读操作
        final futures = batch.calls.map((call) => _executeToolSafely(call));
        final batchResults = await Future.wait(futures);
        results.addAll(batchResults);
      } else {
        // 顺序执行写操作
        for (final call in batch.calls) {
          final result = await _executeToolSafely(call);
          results.add(result);
        }
      }
    }
    return results;
  }
}
```

### 2.3 性能指标与监控

**建议添加**:
```dart
// lib/services/agent_performance_metrics.dart

class ToolExecutionMetrics {
  final String toolName;
  final Duration executionTime;
  final int tokensConsumed;
  final String? errorType;
  
  ToolExecutionMetrics({
    required this.toolName,
    required this.executionTime,
    required this.tokensConsumed,
    this.errorType,
  });
}

class AgentPerformanceMonitor {
  static final _metrics = <ToolExecutionMetrics>[];
  
  static void recordToolExecution({
    required String toolName,
    required Duration duration,
    required int tokens,
    String? error,
  }) {
    _metrics.add(ToolExecutionMetrics(
      toolName: toolName,
      executionTime: duration,
      tokensConsumed: tokens,
      errorType: error,
    ));
    
    // 发送到分析系统
    _logToAnalytics();
  }
  
  static Map<String, dynamic> getSummary() {
    // 返回工具使用汇总、耗时分布、错误率等
    return {
      'totalToolCalls': _metrics.length,
      'totalDuration': _metrics.fold<Duration>(
        Duration.zero,
        (sum, m) => sum + m.executionTime,
      ),
      'toolStatistics': _computeToolStats(),
      'errorRateByTool': _computeErrorRate(),
    };
  }
}
```

---

## 第三部分: 权限与安全

### 3.1 Claude Code 的权限框架

Claude Code 实现了**多层权限系统**:

```typescript
// toolExecution.ts - 简化版

export async function runToolUse(...) {
  // 1. 权限预检查 (Pre-tool hooks)
  await executePreToolHooks(tool.name, toolInput);
  
  // 2. 权限决策
  const permissionResult = await checkRuleBasedPermissions(
    tool.name,
    userRules,    // 用户自定义规则
    configRules,  // 系统配置
  );
  
  if (permissionResult.denied) {
    return handlePermissionDenied(permissionResult.reason);
  }
  
  // 3. 执行工具
  const output = await executeTool(toolInput);
  
  // 4. 后置处理 (Post-tool hooks)
  await executePostToolHooks(tool.name, output);
}
```

### 3.2 ThoughtEcho 权限框架建议

**第一阶段 - 基础权限**:
```dart
// lib/services/agent_permissions.dart

enum ToolPermissionLevel {
  always,      // 总是允许（如 web_fetch）
  oncePerRun,  // 每次运行询问（如 edit_notes）
  never,       // 从不允许（如系统操作）
}

class ToolPermission {
  final String toolName;
  final ToolPermissionLevel level;
  final String? userMessage;  // 询问用户时显示的消息
  
  ToolPermission({
    required this.toolName,
    required this.level,
    this.userMessage,
  });
}

class AgentPermissionManager {
  static const defaultPermissions = {
    'web_fetch': ToolPermission(
      toolName: 'web_fetch',
      level: ToolPermissionLevel.always,
    ),
    'edit_notes': ToolPermission(
      toolName: 'edit_notes',
      level: ToolPermissionLevel.oncePerRun,
      userMessage: 'Agent 请求编辑您的笔记。是否允许？',
    ),
  };
  
  /// 获取工具权限决策
  Future<bool> checkToolPermission(
    String toolName, {
    required BuildContext context,
  }) async {
    final permission = defaultPermissions[toolName];
    if (permission == null) return false;
    
    switch (permission.level) {
      case ToolPermissionLevel.always:
        return true;
      case ToolPermissionLevel.oncePerRun:
        return await _showPermissionDialog(context, permission);
      case ToolPermissionLevel.never:
        return false;
    }
  }
}
```

**第二阶段 - 高级规则引擎** (参考 Claude Code):
```dart
// lib/services/agent_permission_rules.dart

class PermissionRule {
  final String toolName;
  final bool Function(Map<String, Object?> args) predicate;
  final bool isAllowed;
  final String source;  // 'user', 'config', 'default'
  
  PermissionRule({
    required this.toolName,
    required this.predicate,
    required this.isAllowed,
    required this.source,
  });
}

class RuleBasedPermissionEngine {
  final List<PermissionRule> rules = [];
  
  /// 添加用户规则
  void addRule(PermissionRule rule) => rules.add(rule);
  
  /// 判断工具调用是否被允许
  Future<PermissionDecision> resolvePermission(
    String toolName,
    Map<String, Object?> arguments,
  ) async {
    // 按优先级检查规则：user > config > default
    for (final rule in rules) {
      if (rule.toolName != toolName) continue;
      if (!rule.predicate(arguments)) continue;
      
      return PermissionDecision(
        allowed: rule.isAllowed,
        reason: 'Rule from ${rule.source}',
        rule: rule,
      );
    }
    
    return PermissionDecision.default_();
  }
}
```

---

## 第四部分: 错误处理与恢复

### 4.1 Claude Code 的错误分类系统

```typescript
// toolErrors.ts

export function classifyToolError(error: unknown): string {
  // 错误分类
  if (error instanceof TelemetrySafeError) {
    return error.telemetryMessage;  // 可安全记录
  }
  if (error instanceof ShellError) {
    return `Error:${error.code}`;    // 提取 ENOENT 等错误码
  }
  if (error.name && error.name !== 'Error') {
    return error.name;               // 保留知道的错误类型
  }
  return 'UnknownError';
}
```

### 4.2 ThoughtEcho 改进方案

**建议**:
```dart
// lib/services/agent_error_handler.dart

enum ToolErrorType {
  networkError,
  validationError,
  permissionError,
  timeoutError,
  resourceExhausted,
  malformedResponse,
  unknown,
}

class ToolError extends Error {
  final String toolName;
  final ToolErrorType type;
  final String message;
  final Object? originalError;
  final StackTrace? stackTrace;
  
  ToolError({
    required this.toolName,
    required this.type,
    required this.message,
    this.originalError,
    this.stackTrace,
  });
  
  /// 是否可重试
  bool get isRetryable =>
      type == ToolErrorType.networkError ||
      type == ToolErrorType.timeoutError;
  
  /// 生成用户友好的错误信息
  String get userMessage => switch (type) {
    ToolErrorType.networkError => 
      '网络连接失败，请检查网络后重试',
    ToolErrorType.timeoutError => 
      '操作超时（${toolName}），请稍后重试',
    ToolErrorType.permissionError => 
      '权限不足，无法执行 $toolName',
    ToolErrorType.validationError => 
      '参数验证失败：$message',
    ToolErrorType.resourceExhausted => 
      '资源已耗尽，请清理后重试',
    _ => '工具执行失败：$message',
  };
}

class ToolErrorHandler {
  /// 分类错误
  static ToolErrorType classifyError(Object error) {
    if (error is TimeoutException) return ToolErrorType.timeoutError;
    if (error is SocketException) return ToolErrorType.networkError;
    if (error is FormatException) return ToolErrorType.malformedResponse;
    if (error is OutOfMemoryError) return ToolErrorType.resourceExhausted;
    return ToolErrorType.unknown;
  }
  
  /// 重试策略
  static Future<T> executeWithRetry<T>({
    required Future<T> Function() operation,
    required String toolName,
    int maxRetries = 3,
    Duration delay = const Duration(seconds: 2),
  }) async {
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        return await operation();
      } catch (e) {
        if (attempt == maxRetries - 1) rethrow;
        if (!_isRetryable(e)) rethrow;
        
        await Future.delayed(delay * (attempt + 1));
      }
    }
    throw AssertionError('Should not reach here');
  }
  
  static bool _isRetryable(Object error) {
    return classifyError(error).isRetryable;
  }
}
```

---

## 第五部分: 容量管理与截断策略

### 5.1 Claude Code 的容量控制

Claude Code 实现了**多层容量限制**:
```typescript
// toolLimits.ts

export const DEFAULT_MAX_RESULT_SIZE_CHARS = 50_000;      // 单工具限制
export const MAX_TOOL_RESULTS_PER_MESSAGE_CHARS = 200_000; // 批量限制
export const MAX_TOOL_RESULT_TOKENS = 100_000;             // 令牌限制
```

### 5.2 ThoughtEcho 改进方案

**现在**:
```dart
// agent_service.dart:298
const int _defaultMaxSingleMessageChars = 1200;
const int _searchToolMaxSingleMessageChars = 5000;

// 直接截断，容易丢失信息
final truncated = text.length > _maxContentLength
    ? '${text.substring(0, _maxContentLength)}…'
    : text;
```

**建议** (智能溢出处理):
```dart
// lib/services/agent_result_manager.dart

class ToolResultCapacity {
  /// 单个工具结果硬上限
  static const int maxResultChars = 50_000;
  
  /// 单次消息批量上限
  static const int maxPerMessageChars = 200_000;
  
  /// 每种工具的个性化限制
  static const toolSpecificLimits = {
    'web_fetch': 20_000,      // 网页较小
    'web_search': 5_000,      // 摘要较小
    'explore_notes': 30_000,  // 笔记较大
  };
}

class IntelligentResultTruncation {
  /// 智能截断策略（不是简单cut）
  static String truncateResult({
    required String content,
    required String toolName,
    required int maxChars,
  }) {
    final limit = ToolResultCapacity.toolSpecificLimits[toolName] ?? 
                  ToolResultCapacity.maxResultChars;
    final actualLimit = maxChars.clamp(0, limit);
    
    if (content.length <= actualLimit) {
      return content;
    }
    
    // 尝试在合理的边界截断
    final truncated = content.substring(0, actualLimit);
    final lastNewline = truncated.lastIndexOf('\n');
    final lastPeriod = truncated.lastIndexOf('。');
    
    final cutPoint = [lastNewline, lastPeriod]
        .where((i) => i > actualLimit * 0.8)  // 避免太短
        .fold(actualLimit, (a, b) => b > a ? b : a);
    
    return '${truncated.substring(0, cutPoint)}'
           '\n\n[内容已智能截断，原长度 ${content.length} 字符，'
           '保留 $cutPoint 字符。要查看完整内容，请使用 web_fetch 工具。]';
  }
  
  /// 溢出处理：无法存入内存的大结果转存文件
  static Future<String> handleOversizedResult({
    required String content,
    required String toolName,
  }) async {
    if (content.length < ToolResultCapacity.maxResultChars) {
      return content;
    }
    
    // 保存到文件并返回摘要
    final file = await _getLargeResultFile(toolName);
    await file.writeAsString(content);
    
    return '''[结果太大，已保存到文件]
文件路径: ${file.path}
大小: ${content.length} 字符
摘要: ${content.substring(0, 500)}...
    ''';
  }
}

/// 消息级容量管理
class PerMessageCapacityManager {
  final Map<String, int> toolResultSizes = {};
  
  /// 添加工具结果并检查是否超出消息级别限制
  Future<String> addToolResult({
    required String toolName,
    required String result,
  }) async {
    final totalSize = toolResultSizes.values.fold<int>(
      0, (sum, size) => sum + size
    );
    
    if (totalSize + result.length > 
        ToolResultCapacity.maxPerMessageChars) {
      // 需要启用溢出处理（大文件存储或压缩）
      return await IntelligentResultTruncation.handleOversizedResult(
        content: result,
        toolName: toolName,
      );
    }
    
    toolResultSizes[toolName] = result.length;
    return result;
  }
}
```

---

## 第六部分: 调试与可观测性

### 6.1 Claude Code 的工具使用追踪

Claude Code 记录：
- 工具调用序列（Tool Use Timeline）
- 权限决策历史（Permission Audit Log）
- 性能指标（Duration, Token Count）
- 错误摘要（Tool Use Summary）

### 6.2 ThoughtEcho 改进方案

**建议**:
```dart
// lib/services/agent_execution_logger.dart

class ToolUseEvent {
  final String toolName;
  final Map<String, Object?> arguments;
  final DateTime startTime;
  final Duration? duration;
  final String? result;
  final bool isError;
  final String? errorType;
  
  ToolUseEvent({
    required this.toolName,
    required this.arguments,
    required this.startTime,
    this.duration,
    this.result,
    this.isError = false,
    this.errorType,
  });
}

class AgentExecutionLogger {
  final List<ToolUseEvent> _events = [];
  
  /// 记录工具调用
  void logToolUse({
    required String toolName,
    required Map<String, Object?> arguments,
  }) {
    _events.add(ToolUseEvent(
      toolName: toolName,
      arguments: arguments,
      startTime: DateTime.now(),
    ));
  }
  
  /// 记录工具结果
  void logToolResult({
    required String toolName,
    required String result,
    required Duration duration,
    required bool isError,
    String? errorType,
  }) {
    final event = _events.lastWhere(
      (e) => e.toolName == toolName && e.duration == null,
    );
    
    event.duration = duration;
    event.result = result;
    event.isError = isError;
    event.errorType = errorType;
  }
  
  /// 生成执行摘要（用于 UI 展示和分析）
  ToolUseSummary generateSummary() {
    return ToolUseSummary(
      totalCalls: _events.length,
      successfulCalls: _events.where((e) => !e.isError).length,
      failedCalls: _events.where((e) => e.isError).length,
      totalDuration: _events.fold(
        Duration.zero,
        (sum, e) => sum + (e.duration ?? Duration.zero),
      ),
      toolStatistics: _computeToolStats(),
      timeline: _events,
    );
  }
}

class ToolUseSummary {
  final int totalCalls;
  final int successfulCalls;
  final int failedCalls;
  final Duration totalDuration;
  final Map<String, ToolStatistics> toolStatistics;
  final List<ToolUseEvent> timeline;
  
  ToolUseSummary({
    required this.totalCalls,
    required this.successfulCalls,
    required this.failedCalls,
    required this.totalDuration,
    required this.toolStatistics,
    required this.timeline,
  });
}
```

---

## 第七部分: 实现优先级排序

### 优先级矩阵

| 改进项 | 影响度 | 工作量 | 优先级 | 预期耗时 |
|--------|--------|--------|--------|----------|
| **容量管理系统** | 🔴 高 | 🟡 中 | P0 | 1-2天 |
| **权限框架 (基础)** | 🔴 高 | 🟡 中 | P0 | 2-3天 |
| **工具扩展 (第一批)** | 🔴 高 | 🟡 中 | P1 | 3-5天 |
| **并发执行** | 🟡 中 | 🟡 中 | P1 | 2-3天 |
| **错误分类系统** | 🟡 中 | 🟢 低 | P2 | 1天 |
| **执行日志与分析** | 🟡 中 | 🟢 低 | P2 | 1-2天 |
| **权限规则引擎** | 🟡 中 | 🔴 高 | P3 | 5-7天 |
| **动态工具发现** | 🟡 中 | 🔴 高 | P3 | 3-5天 |

### 推荐实现路线

**第1周 (基础稳定)**:
1. 容量管理系统 (50KB/工具, 200KB/消息)
2. 基础权限框架 (Always/OncePerRun/Never)
3. 工具扩展：NotesEditTool, QuoteQueryTool

**第2周 (性能优化)**:
4. 并发执行系统（读操作并发，写操作顺序）
5. 错误分类与重试逻辑
6. 执行日志系统

**第3周 (高级特性)**:
7. 权限规则引擎
8. 动态工具发现系统
9. 集成分析与监控

---

## 第八部分: 代码示例对比

### 8.1 工具执行流程对比

**现在 (ThoughtEcho)**:
```dart
// agent_service.dart:239-305 (简化)
for (final rawToolCall in rawToolCalls) {
  final parsedToolCall = _tryConvertToolCall(rawToolCall);
  
  // 执行工具
  final result = await _executeToolSafely(parsedToolCall);
  
  // 转义并截断
  final escapedContent = _escapeToolResult(result.content);
  final maxMessageChars = _toolMessageCharLimit(parsedToolCall.name);
  messages.add(
    openai.ChatMessage.tool(
      toolCallId: rawToolCall.id,
      content: _truncate(escapedContent, maxMessageChars),
    ),
  );
}
```

**建议 (完整流程)**:
```dart
// 改进后的流程
for (final batch in agentToolExecutor.partitionToolCalls(toolCalls)) {
  // 1. 权限检查
  if (!await permissionManager.checkPermissions(batch)) {
    _emitEvent(AgentPermissionDeniedEvent(batch));
    continue;
  }
  
  // 2. 并发或顺序执行
  final results = await agentToolExecutor.executeBatch(batch);
  
  // 3. 错误分类
  for (final result in results) {
    if (result.isError) {
      final errorType = ToolErrorHandler.classifyError(result.error);
      executionLogger.logToolError(errorType);
    }
  }
  
  // 4. 智能容量管理
  for (final result in results) {
    final managedResult = await capacityManager.addToolResult(
      toolName: result.toolName,
      result: result.content,
    );
    
    messages.add(
      openai.ChatMessage.tool(
        toolCallId: result.toolCallId,
        content: managedResult,
      ),
    );
  }
  
  // 5. 记录执行
  executionLogger.recordBatchExecution(batch, results);
}
```

---

## 第九部分: 检查清单 (实施清单)

### 容量管理系统
- [ ] 创建 `lib/services/agent_result_manager.dart`
- [ ] 实现 `ToolResultCapacity` 常量
- [ ] 实现 `IntelligentResultTruncation` 类
- [ ] 实现 `PerMessageCapacityManager` 类
- [ ] 修改 `agent_service.dart` 使用新系统
- [ ] 添加单元测试
- [ ] 测试大文件场景

### 权限框架
- [ ] 创建 `lib/services/agent_permissions.dart`
- [ ] 定义 `ToolPermissionLevel` 枚举
- [ ] 实现 `AgentPermissionManager`
- [ ] 创建权限 UI 对话框
- [ ] 与 Agent 执行集成
- [ ] 权限决策日志

### 工具系统增强
- [ ] 增强 `WebFetchTool` (重试、代理)
- [ ] 增强 `WebSearchTool` (缓存、排序)
- [ ] 增强 `ExploreNotesTool` (相关度排序)
- [ ] 创建 `NotesEditTool`
- [ ] 创建 `QuoteQueryTool`
- [ ] 工具文档和示例

### 并发执行
- [ ] 创建 `lib/services/agent_tool_executor.dart`
- [ ] 实现 `ToolBatch` 类
- [ ] 实现 `partitionToolCalls()` 方法
- [ ] 实现并发执行逻辑
- [ ] 集成到 `agent_service.dart`
- [ ] 并发安全性测试

### 错误处理
- [ ] 创建 `lib/services/agent_error_handler.dart`
- [ ] 定义 `ToolErrorType` 枚举
- [ ] 实现 `ToolError` 类
- [ ] 实现错误分类
- [ ] 实现重试逻辑
- [ ] 错误恢复测试

### 执行日志
- [ ] 创建 `lib/services/agent_execution_logger.dart`
- [ ] 实现 `ToolUseEvent` 类
- [ ] 实现 `AgentExecutionLogger`
- [ ] 实现 `ToolUseSummary` 生成
- [ ] UI 集成（展示执行摘要）
- [ ] 分析与统计

---

## 总结与建议

### 关键发现

✅ **优势**:
- 架构清晰，Tool 抽象良好
- 事件流模型合理
- 参数验证完善
- 错误处理基础完整

⚠️ **不足**:
- 缺乏容量控制（容易 OOM）
- 无权限系统（信任所有工具）
- 工具数量极少（仅 4 个）
- 顺序执行（无法利用并发）
- 缺乏工具调试数据

### 建议优先级

**立即做**（本周）:
1. 实现容量管理系统（防止 OOM）
2. 实现基础权限框架（安全隔离）

**本月做**（2-3周）:
3. 扩展工具库（+2-3 个常用工具）
4. 实现智能并发执行

**长期优化**（1-2 个月）:
5. 高级权限规则引擎
6. 动态工具发现系统
7. 完整的可观测性系统

---

## 附录：参考资源

### Claude Code 源码位置
- **Tool 系统**: `src/tools/` (~155 个工具)
- **Tool 编排**: `src/services/tools/toolOrchestration.ts`
- **Tool 执行**: `src/services/tools/toolExecution.ts`
- **权限系统**: `src/hooks/toolPermission/`
- **容量限制**: `src/constants/toolLimits.ts`
- **错误处理**: `src/utils/toolErrors.ts`

### ThoughtEcho 改进位置
- **Agent 核心**: `lib/services/agent_service.dart` (727 行)
- **Tool 定义**: `lib/services/agent_tool.dart` (258 行)
- **Tool 实现**: `lib/services/agent_tools/` (4 个工具)
- **相关服务**: `lib/services/settings_service.dart`

---

**报告完成**  
**建议反馈**: 该报告基于 2026-04-18 的代码快照。请根据项目实际需求调整优先级。

