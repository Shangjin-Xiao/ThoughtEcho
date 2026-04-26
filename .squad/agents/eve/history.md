# EVE 的项目记忆

## 核心背景

- 项目: ThoughtEcho (心迹)
- 负责人: 上晋
- 我的角色: UI/UX 设计师
- 设计系统: Material Design 3

## Learnings

### 2026-04-06: 现代 AI 聊天界面设计研究

**Flutter AI Toolkit 核心模式**:
- 输入状态机 (`InputState` 枚举) 管理发送/取消/语音切换
- 流式响应用 `onUpdate` 回调实时刷新 UI
- 消息编辑通过 `initialMessage` + `associatedResponse` 实现
- 桌面端使用悬浮按钮 (hovering_buttons) 提供 Copy/Regenerate

**ThoughtEcho 现状**:
- ✅ 探索页底部导航图标已使用 `Icons.auto_awesome` (星星)
- ⚠️ 探索页顶部有 8dp 多余空白 (SliverAppBar 下方)
- ⚠️ AI 助手页缺少停止生成按钮 (P1 需求)
- ⚠️ 斜杠命令直接显示 ActionChip，应改为弹出菜单

**设计改进优先级**:
1. P0: 探索页布局优化 (移除多余间距, 添加 snap)
2. P1: 停止生成按钮 (AnimatedSwitcher 切换发送/停止)
3. P2: 斜杠命令菜单 (条件渲染弹出面板)
4. P3: 思考过程指示器 (Gemini/Claude 风格)
5. P4: 消息气泡优化 (Material 3 + 尖角设计)

**Material 3 规范**:
- 表面层级: surface → surfaceContainerLow → surfaceContainer → surfaceContainerHigh
- 圆角: 卡片 16dp, 按钮 12dp, 消息气泡 16dp (带尖角 4dp)
- 动画时长: 快速 200ms, 标准 300ms, 入场 600ms

**参考资料**:
- [Flutter AI Toolkit](https://github.com/flutter/ai) - LlmChatView, ChatInput, InputState
- Google AI Gallery - Agent Skills UI
- Gemini/ChatGPT/Claude - 思考指示器, 工具调用可视化

### 2026-04-06: ThinkingWidget 组件创建

**组件位置**: `lib/widgets/ai/thinking_widget.dart`

**核心特性**:
- 可折叠展开的思考过程展示
- 进行中时自动展开，完成后默认折叠
- 左侧竖线标识（Material 3 样式）
- 使用 Markdown 渲染内容
- 平滑动画过渡（AnimatedSize + RotationTransition）

**API**:
```dart
ThinkingWidget(
  thinkingText: '思考内容...',
  inProgress: true,  // 是否进行中
  accentColor: Colors.purple,  // 可选强调色
)
```

**国际化键** (已添加):
- `aiThinking`: "正在思考..." / "Thinking..."
- `showThinking`: "查看思考过程" / "Show thinking"
- `hideThinking`: "收起思考过程" / "Hide thinking"

**动画细节**:
- 折叠/展开: 300ms easeInOut
- 图标旋转: 200ms 线性
- 自动状态切换: inProgress 变化时触发

**使用场景**:
- AI 助手页展示 Agent 思考过程
- 深度分析功能展示分析步骤
- 任何需要展示 AI 推理过程的地方
