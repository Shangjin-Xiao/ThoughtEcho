# WIDGETS MODULE

## OVERVIEW
可复用 UI 组件层 (34+ files)，包括原子组件和复合业务组件。

## KEY WIDGETS
- `note_list_view.dart`: 核心列表展示，支持多种布局和复杂筛选。
- `quote_card.dart` / `quote_item_widget.dart`: 笔记内容的标准展示卡片。
- `streaming_text_dialog.dart`: AI 流式响应的弹窗容器。
- `quill_enhanced_toolbar_unified.dart`: 富文本编辑器工具栏。
- `hitokoto_widget.dart`: 首页展示的每日一言。

## CONVENTIONS
- **原子化**: 尽量保持 Widget 职责单一，避免 build 方法过长。
- **样式解耦**: 颜色和间距应引用 `AppTheme` 或 `Constants`，不要硬编码。
- **动画**: 复杂动效使用 `Lottie`，简单交互使用内置的 `AnimatedWidget`。

## SUB-DIRECTORIES
- `common/`: 基础通用组件。
- `local_ai/`: 本地 AI 相关特化组件。
- `onboarding/`: 引导页专用组件。
