# ThoughtEcho UI优化方案 - HAN-S (内容策划)

## 执行日期
2026-04-11

---

## 1. 默认提示优化

### 现状分析
- **文件**: `lib/pages/ai_assistant_page.dart` (第348-416行)
- **当前流程**:
  1. 显示固定文案欢迎消息（"你好！我是你的笔记助手"）
  2. 调用 `_generateAndShowDynamicInsight()` 生成动态洞察
  3. 结果：两条消息混杂，显得冗杂

### 优化目标
- **只保留动态洞察语**（程序拼接的统计信息）
- **移除所有固定文案**："你好"、"根据你的笔记概览" 等
- **示例保留**: "你最近7天写下了15条灵感，其中工作相关的有8条"

### 代码改进方案

```dart
// 优化前：_addWelcomeMessage() 方法
void _addWelcomeMessage() {
  if (!mounted) return;
  final l10n = AppLocalizations.of(context);
  // 固定文案 - 需要移除
  final String welcomeContent = _hasBoundNote
      ? l10n.aiAssistantWelcome(_getQuotePreview())
      : widget.exploreGuideSummary?.trim().isNotEmpty == true
          ? l10n.aiAssistantExploreWelcome(widget.exploreGuideSummary!.trim())
          : l10n.aiAssistantInputHint;

  final welcomeMsg = app_chat.ChatMessage(...);
  _appendMessage(welcomeMsg, persist: true);

  // 动态洞察 - 只在explore模式保留
  if (!_hasBoundNote && ...) {
    _generateAndShowDynamicInsight();
  }
}

// 优化后：改进版本
void _addWelcomeMessage() {
  if (!mounted) return;

  // 仅在Explore模式（无bound note）时显示动态洞察
  // 移除所有固定欢迎文案
  if (!_hasBoundNote &&
      (widget.exploreGuideSummary?.trim().isEmpty ?? true) &&
      _entrySource == AIAssistantEntrySource.explore) {
    _generateAndShowDynamicInsight();
  }
  // Note模式：不显示任何欢迎消息，直接等待用户输入
}

// 改进动态洞察生成（更丰富的统计信息）
Future<void> _generateAndShowDynamicInsight() async {
  final databaseService = _tryGetDatabaseService();
  if (databaseService == null) return;

  try {
    final quotes = await databaseService.getUserQuotes();
    if (quotes.isEmpty) return;

    // 多维度统计
    final count = quotes.length;
    final recentCount = quotes.where((q) {
      try {
        final qDate = DateTime.parse(q.date);
        return DateTime.now().difference(qDate).inDays <= 7;
      } catch (e) {
        return false;
      }
    }).length;

    // 统计分类（如果有tag信息）
    final tagStats = <String, int>{};
    for (final q in quotes) {
      // 假设tags字段存在
      // tagStats[q.tag] = (tagStats[q.tag] ?? 0) + 1;
    }

    // 动态生成洞察语（仅统计信息，无固定文案）
    final insightParts = <String>[];
    insightParts.add('你有 $count 条灵感记录');
    if (recentCount > 0) {
      insightParts.add('最近7天新增 $recentCount 条');
    }

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

### 改进影响
- **UI更清爽**: 移除冗余文案
- **聚焦对话**: 用户可立即开始输入
- **动态化**: 统计信息真实反映用户数据
- **多维度**: 可扩展更多统计维度（按标签、时间段等）

---

## 2. 对话历史Sheet优化

### 现状分析
- **文件**: `lib/widgets/session_history_sheet.dart`
- **现有优势**:
  - ✅ Material 3卡片设计
  - ✅ flutter_slidable 滑动删除
  - ✅ 消息数量徽章
  - ✅ 自然语言时间格式（"2小时前"）
  - ✅ 当前会话高亮

### 优化建议

#### 2.1 按日期分组显示

```dart
// 在 _SessionHistorySheetState 中新增分组方法
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
```

#### 2.2 显示最后一条消息预览

```dart
// 修改 _buildSessionCard 的消息预览部分
Widget _buildSessionCard(
  BuildContext context,
  ChatSession session,
  ThemeData theme,
  AppLocalizations l10n,
) {
  final isCurrent = session.id == widget.currentSessionId;
  final messageCount = _messageCounts[session.id] ?? 0;

  // 新增：获取最后一条消息预览
  final lastMessagePreview = _getLastMessagePreview(session.id);

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Slidable(
      // ... 其他代码 ...
      child: AnimatedContainer(
        // ... 样式代码 ...
        child: InkWell(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题行（已有）
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
                // 新增：最后一条消息预览
                if (lastMessagePreview != null)
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
                // 时间显示
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
  );
}

// 新增辅助方法：获取最后一条消息预览
String? _getLastMessagePreview(String sessionId) {
  // 从缓存或异步加载获取最后一条消息
  // 这里需要在 _loadSessions 时并行加载
  // 或使用 FutureBuilder 异步显示
  return null; // 暂时返回null，实现见下方
}
```

#### 2.3 完整的改进版SessionHistorySheet

```dart
class _SessionHistorySheetState extends State<SessionHistorySheet> {
  List<ChatSession>? _sessions;
  bool _isLoading = true;
  Map<String, int> _messageCounts = {};
  Map<String, String> _lastMessagePreviews = {}; // 新增

  Future<void> _loadSessions() async {
    setState(() => _isLoading = true);
    try {
      final List<ChatSession> sessions;
      if (widget.noteId.isEmpty) {
        sessions = await widget.chatSessionService.getAllSessions();
      } else {
        sessions = await widget.chatSessionService.getSessionsForNote(widget.noteId);
      }

      final Map<String, int> counts = {};
      final Map<String, String> previews = {}; // 新增

      for (final session in sessions) {
        try {
          counts[session.id] =
              await widget.chatSessionService.getMessageCount(session.id);

          // 新增：获取最后一条消息作为预览
          final messages = await widget.chatSessionService.getMessages(session.id);
          if (messages.isNotEmpty) {
            final lastMsg = messages.last;
            final preview = lastMsg.content.length > 50
                ? '${lastMsg.content.substring(0, 50)}...'
                : lastMsg.content;
            previews[session.id] = preview;
          }
        } catch (e) {
          AppLogger.w('Failed to load data for ${session.id}', error: e);
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
          ...sessions.map(
            (session) => _buildSessionCard(context, session, theme, l10n),
          ),
        ];
      }).toList(),
    );
  }

  // 新增：分组逻辑
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

  // 修改：在 _buildSessionCard 中使用预览
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
                    // 新增：最后一条消息预览
                    if (lastMessagePreview != null)
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

  // ... 保持其他方法不变 ...
}
```

---

## 3. Slash命令菜单优化

### 现状分析
- **文件**:
  - `lib/pages/ai_assistant_page.dart` (第1849-1873行)
  - `lib/widgets/ai/slash_commands_menu.dart`
- **当前问题**:
  - `ai_assistant_page.dart` 中使用 `Wrap` + `ActionChip` 横向排列
  - 不符合Google AI Gallery的列表式设计
  - 可用空间浪费，不利于快速扫视

### 优化方案

#### 3.1 在 `ai_assistant_page.dart` 中替换为列表式显示

```dart
// 优化前：横向ActionChip排列（第1849-1873行）
AnimatedSwitcher(
  duration: const Duration(milliseconds: 180),
  switchInCurve: Curves.easeOutCubic,
  switchOutCurve: Curves.easeInCubic,
  child: _showSlashCommands && filteredWorkflowDescriptors.isNotEmpty
      ? Padding(
          key: const ValueKey('slash_commands_visible'),
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: filteredWorkflowDescriptors.map((descriptor) {
                return ActionChip(
                  label: Text(descriptor.command),
                  onPressed: () {
                    _textController.clear();
                    _handleSubmitted(descriptor.command);
                  },
                );
              }).toList(),
            ),
          ),
        )
      : const SizedBox.shrink(
          key: ValueKey('slash_commands_hidden'),
        ),
),

// 优化后：使用SlashCommandsMenu列表式显示
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

#### 3.2 改进SlashCommandsMenu的显示

```dart
// 在 lib/widgets/ai/slash_commands_menu.dart 中增强

class _SlashCommandTile extends StatefulWidget {
  final AIWorkflowDescriptor command;
  final bool isSelected;
  final VoidCallback onTap;
  final ValueChanged<bool> onHover;

  // 新增：快捷键显示
  final String? keyboardShortcut;

  const _SlashCommandTile({
    required this.command,
    required this.isSelected,
    required this.onTap,
    required this.onHover,
    this.keyboardShortcut,
  });

  @override
  State<_SlashCommandTile> createState() => _SlashCommandTileState();
}

class _SlashCommandTileState extends State<_SlashCommandTile> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovering = true);
        widget.onHover(true);
      },
      onExit: (_) {
        setState(() => _isHovering = false);
        widget.onHover(false);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: widget.isSelected || _isHovering
            ? theme.colorScheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // 命令icon
                if (widget.command.icon != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      widget.command.icon!,
                      style: const TextStyle(fontSize: 18),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      '/',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                // 命令名称与描述
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            widget.command.command,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // 新增：快捷方式标签
                          if (widget.keyboardShortcut != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: theme.colorScheme.outline.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                widget.keyboardShortcut!,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: 10,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (widget.command.description != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            widget.command.description!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                // 高亮指示符
                if (widget.isSelected)
                  Container(
                    width: 4,
                    height: 32,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

#### 3.3 菜单样式优化（类似Google AI Gallery）

```dart
class SlashCommandsMenu extends StatefulWidget {
  final List<AIWorkflowDescriptor> commands;
  final String filterText;
  final ValueChanged<AIWorkflowDescriptor> onCommandSelected;
  final bool visible;

  const SlashCommandsMenu({
    super.key,
    required this.commands,
    required this.filterText,
    required this.onCommandSelected,
    required this.visible,
  });

  @override
  State<SlashCommandsMenu> createState() => _SlashCommandsMenuState();
}

class _SlashCommandsMenuState extends State<SlashCommandsMenu>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOut));

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    if (widget.visible) {
      _animationController.forward();
    }
  }

  @override
  void didUpdateWidget(SlashCommandsMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _selectedIndex = 0;
      _animationController.forward();
    } else if (!widget.visible && oldWidget.visible) {
      _animationController.reverse();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filteredCommands = widget.commands
        .where((cmd) =>
            widget.filterText.isEmpty ||
            cmd.command.toLowerCase().contains(widget.filterText.toLowerCase()) ||
            cmd.displayName
                .toLowerCase()
                .contains(widget.filterText.toLowerCase()))
        .toList();

    if (filteredCommands.isEmpty) {
      return const SizedBox.shrink();
    }

    _selectedIndex = _selectedIndex.clamp(0, filteredCommands.length - 1);

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          constraints: const BoxConstraints(maxHeight: 300), // 新增：限制高度
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.2 : 0.08,
                ),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 菜单头部
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '快捷命令',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${filteredCommands.length} 个',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                height: 1,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
              // 命令列表
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  itemCount: filteredCommands.length,
                  itemBuilder: (context, index) {
                    final command = filteredCommands[index];
                    final isSelected = index == _selectedIndex;

                    return _SlashCommandTile(
                      command: command,
                      isSelected: isSelected,
                      keyboardShortcut: '${index + 1}', // 快捷数字键
                      onTap: () {
                        setState(() {
                          _selectedIndex = index;
                        });
                        widget.onCommandSelected(command);
                      },
                      onHover: (hovering) {
                        if (hovering) {
                          setState(() {
                            _selectedIndex = index;
                          });
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

---

## 4. 导入需求

为支持以上优化，需要在 `ai_assistant_page.dart` 中添加导入：

```dart
// 如果未导入，需添加
import 'package:flutter_slidable/flutter_slidable.dart'; // 已存在于session_history_sheet.dart

// 确保SlashCommandsMenu导入
import '../widgets/ai/slash_commands_menu.dart'; // 补充
```

---

## 5. 实施优先级

| 优化项 | 优先级 | 预计工时 | 复杂度 |
|-------|--------|--------|--------|
| 1. 默认提示移除固定文案 | **高** | 30min | 低 |
| 2. 对话历史按日期分组 | **高** | 45min | 中 |
| 3. 消息预览显示 | **中** | 45min | 中 |
| 4. Slash菜单列表化 | **高** | 30min | 低 |
| 5. 快捷键显示 | **低** | 20min | 低 |

---

## 6. 测试检查清单

- [ ] 验证默认提示仅显示动态洞察统计
- [ ] 确认对话历史按日期正确分组（今天/昨天/本周/更早）
- [ ] 检查消息预览内容完整性（无乱码）
- [ ] 验证Slash菜单列表显示（最多5条可见）
- [ ] 测试菜单过滤逻辑（输入时实时搜索）
- [ ] 验证高亮指示符与键盘/鼠标导航同步
- [ ] 确认移动设备上菜单高度不超过屏幕50%
- [ ] 验证暗色/亮色主题下的对比度

---

## 7. 关键文件路径

```
lib/pages/ai_assistant_page.dart              # 主修改文件
lib/widgets/session_history_sheet.dart        # 历史Sheet优化
lib/widgets/ai/slash_commands_menu.dart       # Slash菜单优化
lib/l10n/app_zh.arb                          # 保留的l10n配置
```

---

## 8. 预期效果

### 优化前
- 页面冗杂，固定文案与动态内容混杂
- 历史列表无分类，难以快速定位
- Slash菜单占用多行空间，不够紧凑

### 优化后
✅ **清爽**: 移除冗余文案，聚焦对话
✅ **高效**: 按时间自动分组，快速浏览
✅ **Modern**: Google AI Gallery风格列表菜单
✅ **易用**: 实时搜索、键盘快捷键、鼠标悬停
✅ **信息丰富**: 消息预览、计数徽章、时间标签

