/// 集成指南：增强的Slash Commands和Agent笔记查询

/// 此文件提供了实现增强的Slash Commands和Agent笔记查询功能的集成指南。

/// ============================================================================
/// Part 1: Slash Commands UI增强集成
/// ============================================================================

/*

### 1.1 在AIAssistantPage中使用新的Slash Commands菜单

在build()方法中，找到当前的Slash Commands显示位置（约1618行），替换为：

```dart
if (_showSlashCommands && filteredWorkflowDescriptors.isNotEmpty)
  SlashCommandsMenu(
    commands: filteredWorkflowDescriptors,
    filterText: _textController.text.trimLeft().substring(1).trim(),
    onCommandSelected: (command) {
      _textController.clear();
      _handleSubmitted(command.command);
    },
    visible: _showSlashCommands,
  ),
```

### 1.2 自然语言触发检测

在_handleSubmitted()中已经添加了自然语言触发检测：

```dart
// 检测自然语言触发（Agent模式下）
if (_isAgentMode && descriptor == null) {
  final workflows = _buildWorkflowDescriptors(l10n);
  final triggeredId =
      NaturalLanguageTriggerDetector.shouldAutoTrigger(trimmed, workflows);
  if (triggeredId != null) {
    // 可以显示提示或自动执行
    logDebug('自然语言触发命令: ${triggered.command}');
  }
}
```

*/

/// ============================================================================
/// Part 2: Agent笔记查询能力优化
/// ============================================================================

/*

### 2.1 ChatSessionService新增查询方法

已添加的方法：
- getNotesByTags(tags, limit) - 按标签查询笔记
- getRecentNotes(limit, beforeNoteId) - 获取最新笔记
- getNotesByDateRange(start, end, limit) - 按日期范围查询
- queryNotes({tags, dateStart, dateEnd, keyword, limit}) - 组合查询
- getNoteTagIds(noteId) - 获取笔记标签
- formatNoteForAgent(noteRow, tags, matchScore) - 格式化笔记供Agent使用

### 2.2 在Agent中使用这些方法

在Agent Service中调用笔记查询（通过Tool）：

```dart
// 示例：Agent工具定义
AgentTool(
  name: 'get_recent_notes',
  description: '获取最近创建的笔记',
  parametersSchema: {
    'type': 'object',
    'properties': {
      'limit': {
        'type': 'integer',
        'description': '返回的笔记数量，默认10',
      },
    },
  },
  execute: (toolCall) async {
    final limit = toolCall.arguments['limit'] as int? ?? 10;
    final notes = await chatSessionService.getRecentNotes(limit: limit);
    final formatted = notes.map((n) =>
        ChatSessionService.formatNoteForAgent(n)
    ).toList();
    return ToolResult(
      toolCallId: toolCall.id,
      content: jsonEncode(formatted),
    );
  },
)
```

*/

/// ============================================================================
/// Part 3: Tool调用可视化集成
/// ============================================================================

/*

### 3.1 在消息列表中显示Tool调用卡片

在AIAssistantPage的build()中添加显示Tool调用卡片的逻辑：

```dart
// 在消息渲染后添加
if (_isToolInProgress && _toolProgressItems.isNotEmpty)
  ToolCallProgressPanel(
    toolCalls: _toolProgressItems.map((item) =>
      ToolCallInfo(
        id: item.toolName,
        name: item.toolName,
        parameters: {}, // 从Agent中获取
        status: item.status == ToolProgressStatus.running
          ? ToolCallStatus.executing
          : ToolCallStatus.completed,
        result: item.result,
        startTime: DateTime.now(),
      ),
    ).toList(),
  ),
```

### 3.2 监听Tool执行进度

在_onAgentServiceChanged()中已有相关实现。Tool状态通过以下方式更新：
- agentThinking：开始思考
- agentToolCallPrefix{toolName}：执行具体工具
- 空值：执行完成

*/

/// ============================================================================
/// Part 4: 完整的自然语言触发工作流
/// ============================================================================

/*

### 工作流示例：用户输入"帮我分析这个"

1. 用户输入文本 → _textController 变化 → _onTextChanged()
   - 如果以"/"开头，显示SlashCommandsMenu
   - 否则继续

2. 用户提交 → _handleSubmitted()
   - 首先检查Slash命令
   - 如果没有，检查自然语言触发关键词
   - 如果在Agent模式且有匹配，可以自动执行或提示用户

3. 触发工作流 → _runExplicitWorkflow() 或 _askAgent()
   - 收集笔记上下文
   - 调用相应的服务

*/

/// ============================================================================
/// Part 5: 性能优化和最佳实践
/// ============================================================================

/*

### 5.1 数据库查询优化

所有ChatSessionService新增的查询方法都使用了优化的SQL：
- 按标签查询使用索引：quote_tags(tag_id, quote_id)
- 按日期查询使用BETWEEN和索引：quotes(date)
- 组合查询使用JOIN和GROUP BY

### 5.2 查询结果缓存

可以在需要的地方添加缓存：

```dart
final class NoteQueryCache {
  static final Map<String, Future<List<Map>>> _cache = {};

  static Future<List<Map>> getCachedNotes(
    String key,
    Future<List<Map>> Function() fetcher,
  ) async {
    return _cache.putIfAbsent(key, fetcher);
  }

  static void clear() => _cache.clear();
}
```

### 5.3 错误处理

所有查询方法都包含try-catch和错误日志：

```dart
catch (e) {
  logError(
    'ChatSessionService.queryNotes 失败',
    error: e,
    source: 'ChatSessionService',
  );
  return [];
}
```

*/

/// ============================================================================
/// Part 6: 测试点清单
/// ============================================================================

/*

### UI测试
- [ ] 输入"/"时显示SlashCommandsMenu
- [ ] 在菜单中上下键导航
- [ ] 点击菜单项执行命令
- [ ] 过滤功能正确工作

### 自然语言检测测试
- [ ] 输入"帮我润色"→ 检测到polish命令
- [ ] 输入"分析一下来源" → 检测到sourceAnalysis
- [ ] 检测精度 >90%

### 笔记查询测试
- [ ] getNotesByTags() 返回正确的标签笔记
- [ ] getRecentNotes() 返回最新的笔记
- [ ] getNotesByDateRange() 按日期范围正确过滤
- [ ] queryNotes() 支持多条件组合查询

### Tool调用显示测试
- [ ] Tool执行时显示加载卡片
- [ ] Tool完成时显示结果
- [ ] Tool失败时显示错误和重试按钮
- [ ] 支持展开/收起详情

*/
