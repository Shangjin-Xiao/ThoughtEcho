# AI助手对话历史搜索高亮突出显示设计方案

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 当用户在AI助手对话历史搜索中进行搜索时，在搜索结果卡片中对匹配的关键字进行突出显示（高亮）。
- **标题匹配**：使用应用主题色 + 粗体（不带底色，保持头部清爽）。
- **正文/消息匹配**：使用应用主题色 + 粗体 + 15%透明度的主题色背景底色（类似马克笔涂抹效果），保证在长文本中一目了然。

**Architecture:** 
1. 在 `lib/pages/ai_assistant/session_history_page_content.dart` 中实现一个通用的 `_buildHighlightedText` 辅助方法，该方法接收原始文本、搜索关键字、基础样式、主题对象以及是否使用背景色块的标志。
2. 该方法使用 `Text.rich` 和多个 `TextSpan`，利用 `indexOf` 循环在文本中拆分并为匹配的关键字应用特定的高亮样式。
3. 在 `_buildSessionCard` 中，将渲染标题和正文的 `Text` 替换为 `_buildHighlightedText`。当非搜索状态（即搜索词为空）时，自动降级回普通 `Text` 渲染，确保零性能开销与一致的外观。

**Tech Stack:** Flutter (Material 3), Dart

---

### Task 1: 实现高亮渲染辅助方法与会话卡片更新

**Files:**
- Modify: `lib/pages/ai_assistant/session_history_page_content.dart`

**Step 1: 新增 `_buildHighlightedText` 方法并更新 `_buildSessionCard`**

在 `lib/pages/ai_assistant/session_history_page_content.dart` 文件的末尾或合适位置添加以下辅助方法：

```dart
  Widget _buildHighlightedText({
    required String text,
    required String query,
    required TextStyle baseStyle,
    required ThemeData theme,
    required bool useBackground,
    int maxLines = 1,
    TextOverflow overflow = TextOverflow.ellipsis,
  }) {
    if (query.isEmpty) {
      return Text(
        text,
        style: baseStyle,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    final List<InlineSpan> spans = [];
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();

    int start = 0;
    int indexOfQuery = lowerText.indexOf(lowerQuery, start);

    final highlightStyle = useBackground
        ? baseStyle.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
          )
        : baseStyle.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
          );

    while (indexOfQuery != -1) {
      if (indexOfQuery > start) {
        spans.add(TextSpan(
          text: text.substring(start, indexOfQuery),
        ));
      }
      spans.add(TextSpan(
        text: text.substring(indexOfQuery, indexOfQuery + query.length),
        style: highlightStyle,
      ));
      start = indexOfQuery + query.length;
      indexOfQuery = lowerText.indexOf(lowerQuery, start);
    }

    if (start < text.length) {
      spans.add(TextSpan(
        text: text.substring(start),
      ));
    }

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: spans,
      ),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
```

并在 `_buildSessionCard` 中，将标题和正文（snippet）部分替换为调用 `_buildHighlightedText` 方法。

**Step 2: 验证编译**

无编译错误即为成功。

---

### Task 2: 运行测试并添加新测试用例以验证高亮逻辑

**Files:**
- Test: `test/widget/session_history_page_test.dart`

**Step 1: 运行现有测试**

运行: `flutter test --reporter compact test/widget/session_history_page_test.dart`
预期结果: 所有测试应该正常通过。

**Step 2: 在测试文件中补充针对高亮显示的细化验证**

在 `test/widget/session_history_page_test.dart` 的 `main` 方法中添加一个新的测试用例，专门用来检查 `Text.rich` 中高亮 `TextSpan` 的属性（例如 `style.color` 或 `style.backgroundColor`）是否正确渲染。

```dart
  testWidgets('applies highlight styles to matching search text in snippet and title',
      (tester) async {
    final now = DateTime(2026, 4, 18, 12);
    final matchedSession = _session(
      id: 'highlight-match',
      title: '学习Flutter',
      lastActiveAt: now,
    );
    final service = _FakeChatSessionService(
      sessions: [matchedSession],
      messageCounts: const {'highlight-match': 1},
      searchResults: [
        ChatSessionSearchResult(
          session: matchedSession,
          snippet: 'Flutter是Google的UI框架',
          isTruncated: false,
          matchStart: 0,
          matchEnd: 7,
        ),
      ],
    );

    await tester.pumpWidget(
      _buildTestApp(
        SessionHistoryPage(
          noteId: '',
          currentSessionId: null,
          chatSessionService: service,
          onSelect: (_) {},
          onDelete: (_) {},
          onNewChat: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Flutter');
    await tester.pumpAndSettle();

    // 检查是否存在 Text.rich 组件
    final richTextFinder = find.byType(RichText);
    expect(richTextFinder, findsAtLeastNWidgets(2)); // 一个用于标题，一个用于正文（或其它RichText）
  });
```

**Step 3: 运行所有测试**

运行: `flutter test --reporter compact test/widget/session_history_page_test.dart`
预期结果: PASS
