# ThoughtEcho UI 优化 - 代码实施指南

## 核心改动说明

本文档提供逐步实施优化的代码片段和修改指南。

---

## Part 1: 默认提示优化 (ai_assistant_page.dart)

### 改动位置
**文件**: `lib/pages/ai_assistant_page.dart`
**行号**: 348-416 (方法: `_addWelcomeMessage()` 和 `_generateAndShowDynamicInsight()`)

### 修改步骤

#### Step 1: 简化 `_addWelcomeMessage()` 方法

将第 348-373 行替换为：

```dart
void _addWelcomeMessage() {
  if (!mounted) return;

  // 仅在Explore模式（无bound note）时显示动态洞察
  // Note模式：跳过欢迎消息，直接等待用户输入
  if (!_hasBoundNote &&
      (widget.exploreGuideSummary?.trim().isEmpty ?? true) &&
      _entrySource == AIAssistantEntrySource.explore) {
    _generateAndShowDynamicInsight();
  }
  // 其他模式：不显示任何预初始化消息
}
```

#### Step 2: 增强 `_generateAndShowDynamicInsight()` 方法

将第 376-416 行替换为：

```dart
/// Generate and display a dynamic insight based on current data
/// 生成基于用户数据的动态洞察统计（仅统计信息，无固定文案）
Future<void> _generateAndShowDynamicInsight() async {
  final databaseService = _tryGetDatabaseService();
  if (databaseService == null) return;

  try {
    final quotes = await databaseService.getUserQuotes();
    if (quotes.isEmpty) return;

    // 第一维度：总数统计
    final count = quotes.length;
    final l10n = AppLocalizations.of(context);

    // 第二维度：最近7天
    final recentCount = quotes
        .where((q) {
          try {
            final qDate = DateTime.parse(q.date);
            return DateTime.now().difference(qDate).inDays <= 7;
          } catch (e) {
            return false;
          }
        })
        .length;

    // 第三维度：最近30天
    final monthlyCount = quotes
        .where((q) {
          try {
            final qDate = DateTime.parse(q.date);
            return DateTime.now().difference(qDate).inDays <= 30;
          } catch (e) {
            return false;
          }
        })
        .length;

    // 构建动态洞察语（纯统计信息）
    final insightParts = <String>[];

    // 基础统计
    insightParts.add('你有 **$count** 条灵感记录');

    // 按时间段统计
    if (recentCount > 0) {
      final percentage = ((recentCount / count) * 100).toStringAsFixed(0);
      insightParts.add('其中最近7天新增 **$recentCount** 条（占比 $percentage%）');
    }

    if (monthlyCount > recentCount) {
      final additionalCount = monthlyCount - recentCount;
      insightParts.add('本月新增 **$monthlyCount** 条');
    }

    // 时间洞察
    final now = DateTime.now();
    final oldestQuote = quotes.reduce((a, b) {
      try {
        final aDate = DateTime.parse(a.date);
        final bDate = DateTime.parse(b.date);
        return aDate.isBefore(bDate) ? a : b;
      } catch (e) {
        return a;
      }
    });

    try {
      final oldestDate = DateTime.parse(oldestQuote.date);
      final daysDiff = now.difference(oldestDate).inDays;
      if (daysDiff > 0) {
        final avgDaily = (count / daysDiff).toStringAsFixed(1);
        insightParts.add('累积 **$daysDiff** 天，日均 **$avgDaily** 条');
      }
    } catch (e) {
      // 忽略解析错误
    }

    // 组合最终文案（仅统计信息）
    final insightText = insightParts.join('，') + '。';

    if (!mounted) return;

    final insightMsg = app_chat.ChatMessage(
      id: _uuid.v4(),
      content: insightText,
      isUser: false,
      role: 'system',
      timestamp: DateTime.now(),
      includedInContext: false,
    );
    _appendMessage(insightMsg, persist: false);
  } catch (e) {
    AppLogger.d('Failed to generate dynamic insight: $e');
  }
}
```

### 验证

修改后，进入 Explore 页面的 AI 助手时应该看到：
- ✅ 仅显示统计信息，例如："你有 **15** 条灵感记录，其中最近7天新增 **8** 条（占比 53%）..."
- ✅ 没有"你好"或"根据你的笔记概览"等固定文案
- ✅ Note 模式下完全不显示欢迎消息

---

## Part 2: 对话历史优化 (session_history_sheet.dart)

### 改动位置
**文件**: `lib/widgets/session_history_sheet.dart`

### 完整替换建议

新增分组方法，替换整个 `_SessionHistorySheetState` 类：

```dart
class _SessionHistorySheetState extends State<SessionHistorySheet> {
  List<ChatSession>? _sessions;
  bool _isLoading = true;
  Map<String, int> _messageCounts = {};
  Map<String, String> _lastMessagePreviews = {}; // 新增：消息预览缓存

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _isLoading = true);
    try {
      final List<ChatSession> sessions;
      if (widget.noteId.isEmpty) {
        sessions = await widget.chatSessionService.getAllSessions();
      } else {
        sessions =
            await widget.chatSessionService.getSessionsForNote(widget.noteId);
      }

      final Map<String, int> counts = {};
      final Map<String, String> previews = {}; // 新增

      for (final session in sessions) {
        try {
          counts[session.id] =
              await widget.chatSessionService.getMessageCount(session.id);

          // 新增：异步加载最后一条消息预览
          try {
            final messages = await widget.chatSessionService.getMessages(session.id);
            if (messages.isNotEmpty) {
              final lastMsg = messages.last;
              final preview = lastMsg.content.length > 60
                  ? '${lastMsg.content.substring(0, 60)}...'
                  : lastMsg.content;
              previews[session.id] = preview;
            }
          } catch (e) {
            AppLogger.w('Failed to load preview for ${session.id}', error: e);
          }
        } catch (e) {
          AppLogger.w('Failed to load message count for ${session.id}', error: e);
          counts[session.id] = 0;
        }
      }

      if (mounted) {
        setState(() {
          _sessions = sessions;
          _messageCounts = counts;
          _lastMessagePreviews = previews; // 新增
          _isLoading = false;
        });
      }
    } catch (e) {
      AppLogger.e('Failed to load sessions', error: e);
      if (mounted) {
        setState(() {
          _sessions = [];
          _messageCounts = {};
          _lastMessagePreviews = {};
          _isLoading = false;
        });
      }
    }
  }

  // 新增：按日期分组
  Map<String, List<ChatSession>> _groupSessionsByDate(
    List<ChatSession> sessions,
  ) {
    final grouped = <String, List<ChatSession>>{};

    for (final session in sessions) {
      final now = DateTime.now();
      final lastDate = DateTime(
        session.lastActiveAt.year,
        session.lastActiveAt.month,
        session.lastActiveAt.day,
      );
      final nowDate = DateTime(now.year, now.month, now.day);

      String groupKey;
      if (lastDate == nowDate) {
        groupKey = '📅 今天';
      } else if (lastDate == nowDate.subtract(const Duration(days: 1))) {
        groupKey = '📅 昨天';
      } else if (lastDate.isAfter(nowDate.subtract(const Duration(days: 7)))) {
        groupKey = '📅 本周';
      } else {
        groupKey = '📅 更早';
      }

      grouped.putIfAbsent(groupKey, () => []).add(session);
    }

    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(children: [
              Text(l10n.chatHistory, style: theme.textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: widget.onNewChat,
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.newChat),
              ),
            ]),
          ),
          const Divider(height: 1),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            )
          else if (_sessions == null || _sessions!.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline,
                      size: 48, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                  const SizedBox(height: 12),
                  Text(l10n.noChats,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      )),
                ],
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: _buildGroupedSessionList(context, theme, l10n),
            ),
        ],
      ),
    );
  }

  // 新增：分组显示会话列表
  Widget _buildGroupedSessionList(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    final grouped = _groupSessionsByDate(_sessions!);
    final groupOrder = ['📅 今天', '📅 昨天', '📅 本周', '📅 更早'];

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: groupOrder
          .where((key) => grouped.containsKey(key))
          .expand((groupKey) {
        final sessions = grouped[groupKey]!;
        return [
          // 分组标题
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Text(
              groupKey,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // 分组内的会话卡片
          ...sessions.map(
            (session) => _buildSessionCard(context, session, theme, l10n),
          ),
        ];
      }).toList(),
    );
  }

  Widget _buildSessionCard(
    BuildContext context,
    ChatSession session,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    final isCurrent = session.id == widget.currentSessionId;
    final messageCount = _messageCounts[session.id] ?? 0;
    final lastMessagePreview = _lastMessagePreviews[session.id];
    final truncatedTitle = session.title.length > 50
        ? '${session.title.substring(0, 50)}...'
        : session.title;
    final lastUpdated = TimeUtils.formatElapsedRelativeTimeLocalized(
      context,
      session.lastActiveAt,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Slidable(
        key: ValueKey(session.id),
        endActionPane: ActionPane(
          motion: const ScrollMotion(),
          children: [
            SlidableAction(
              onPressed: (_) => _confirmDelete(context, session.id),
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
              icon: Icons.delete_outline,
              label: l10n.delete,
            ),
          ],
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isCurrent
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
                : theme.colorScheme.surface,
            border: Border.all(
              color: isCurrent
                  ? theme.colorScheme.primary.withValues(alpha: 0.5)
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              width: isCurrent ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isCurrent ? null : () => widget.onSelect(session.id),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题行
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          isCurrent ? Icons.chat_bubble : Icons.chat_bubble_outline,
                          color: isCurrent
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            truncatedTitle,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: theme.colorScheme.onSurface,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 消息计数徽章
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            messageCount.toString(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // 消息预览（新增）
                    if (lastMessagePreview != null && lastMessagePreview.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          lastMessagePreview,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    // 最后修改时间
                    Text(
                      lastUpdated,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, String sessionId) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteChat),
        content: Text(l10n.deleteChatConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              widget.onDelete(sessionId);
              if (mounted) {
                await _loadSessions();
              }
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }
}
```

### 验证

修改后，点击"历史"按钮应该看到：
- ✅ 会话按日期分组（📅 今天、📅 昨天、📅 本周、📅 更早）
- ✅ 每个会话卡片显示标题、消息数量徽章、最后消息预览、修改时间
- ✅ 当前会话高亮显示
- ✅ 可向右滑动卡片删除

---

## Part 3: Slash 命令菜单优化 (ai_assistant_page.dart)

### 改动位置
**文件**: `lib/pages/ai_assistant_page.dart`
**行号**: 1849-1873 (位置: `_buildInputArea` 方法中的 `AnimatedSwitcher`)
**需要导入**: `import '../widgets/ai/slash_commands_menu.dart';` (检查是否已有)

### 修改代码

将第 1849-1873 行的 `AnimatedSwitcher` 替换为：

```dart
AnimatedSwitcher(
  duration: const Duration(milliseconds: 180),
  switchInCurve: Curves.easeOutCubic,
  switchOutCurve: Curves.easeInCubic,
  child: _showSlashCommands && filteredWorkflowDescriptors.isNotEmpty
      ? Padding(
          key: const ValueKey('slash_commands_visible'),
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: SlashCommandsMenu(
            commands: filteredWorkflowDescriptors,
            filterText: _textController.text.trimLeft().substring(1).trim(),
            onCommandSelected: (descriptor) {
              _textController.clear();
              _handleSubmitted(descriptor.command);
            },
            visible: true,
          ),
        )
      : const SizedBox.shrink(
          key: ValueKey('slash_commands_hidden'),
        ),
),
```

### 验证

修改后，在输入框输入 "/" 时应该看到：
- ✅ 弹出列表式菜单（替代横向ActionChip）
- ✅ 每行显示：命令名称 + 描述 + 快捷键数字
- ✅ 左侧显示命令icon或"/"符号
- ✅ 右侧选中时显示竖线指示符
- ✅ 支持鼠标悬停高亮
- ✅ 实时过滤（继续输入命令名称时过滤列表）

---

## 完整检查清单

### 修改验证

- [ ] **Step 1**: 修改 `_addWelcomeMessage()` - 移除固定欢迎文案
  - [ ] Explore模式下显示动态洞察统计
  - [ ] Note模式下无欢迎消息

- [ ] **Step 2**: 增强 `_generateAndShowDynamicInsight()` - 生成丰富的统计信息
  - [ ] 显示总数统计
  - [ ] 显示最近7天/30天统计
  - [ ] 显示累积天数和日均数据

- [ ] **Step 3**: 替换 `SessionHistorySheet` - 优化历史Sheet
  - [ ] 会话按日期分组显示
  - [ ] 每个卡片显示消息预览
  - [ ] 当前会话高亮
  - [ ] 滑动删除功能正常

- [ ] **Step 4**: 替换 Slash菜单显示 - 从横向改为列表
  - [ ] 菜单显示为竖向列表
  - [ ] 每行显示完整信息（命令+描述+快捷键）
  - [ ] 支持鼠标和键盘导航
  - [ ] 实时过滤功能正常

### 测试场景

```
场景 1: 默认提示
- 打开应用 → 进入AI助手Explore模式
- 验证：仅显示统计信息，无"你好"文案

场景 2: 对话历史
- 创建多个会话
- 点击历史按钮
- 验证：按日期分组、显示预览、能删除

场景 3: Slash命令
- 在输入框输入"/"
- 验证：显示列表菜单、支持搜索
- 选择命令
- 验证：命令执行正常
```

---

## 调试技巧

### 如果菜单不显示

1. 检查导入: `import '../widgets/ai/slash_commands_menu.dart';`
2. 检查 `filteredWorkflowDescriptors` 是否为空
3. 检查 `_showSlashCommands` 状态是否更新
4. 查看控制台日志: `flutter logs`

### 如果历史Sheet加载慢

1. 异步加载消息预览可能耗时
2. 考虑限制预览长度（当前: 60字符）
3. 可添加缓存机制减少重复查询

### 性能优化建议

```dart
// 缓存预览，避免每次重新加载
if (_lastMessagePreviews[session.id] == null) {
  // 异步加载预览
}

// 限制分组数据量（如果会话太多）
if (_sessions!.length > 100) {
  // 分页加载
}
```

---

## 提交提示

修改完成后，建议:

```bash
# 1. 格式化代码
dart format lib/pages/ai_assistant_page.dart
dart format lib/widgets/session_history_sheet.dart
dart format lib/widgets/ai/slash_commands_menu.dart

# 2. 静态分析
flutter analyze

# 3. 运行测试
flutter test

# 4. 构建
flutter build apk
```

---

## 相关文件

| 文件 | 改动类型 | 优先级 |
|-----|--------|--------|
| lib/pages/ai_assistant_page.dart | ✏️ 修改 | 高 |
| lib/widgets/session_history_sheet.dart | ✏️ 修改 | 高 |
| lib/widgets/ai/slash_commands_menu.dart | ✅ 现有，无需改动 | - |

---

**优化完成预计**: 2-3 小时（3项改动）
**测试验证**: 1 小时
**总计**: 3-4 小时

