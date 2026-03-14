# WIDGETS 模块

## 概览
可复用 UI 组件层（40+ 文件），包含原子组件和复合业务组件。

## 核心组件

| 文件 | 说明 |
|------|------|
| `note_list_view.dart` | **核心笔记列表（2100+ 行）**，支持多布局、筛选、滑动操作 |
| `quote_card.dart` | 笔记卡片标准展示，支持卡片模板和颜色 |
| `quote_item_widget.dart` | 列表中的单条笔记条目 |
| `streaming_text_dialog.dart` | AI 流式响应弹窗容器 |
| `quill_enhanced_toolbar_unified.dart` | 富文本编辑器工具栏 |
| `add_note_dialog.dart` | 快速添加笔记弹窗 |
| `hitokoto_widget.dart` | 首页每日一言展示 |
| `weather_widget.dart` | 天气信息展示 |
| `media_player_widget.dart` | 视频/音频播放器 |
| `motion_photo_preview_page.dart` | 动态照片预览 |
| `unified_media_import_dialog.dart` | 统一媒体导入弹窗 |
| `app_snackbar.dart` | 统一 SnackBar 样式封装 |

## 拆分子目录

| 子目录 | 说明 |
|--------|------|
| `note_list/` | NoteListView 拆分：data_stream / filters / items / scroll |
| `common/` | 基础通用组件（`lottie_animation_widget.dart`） |
| `local_ai/` | 本地 AI 特化组件 |
| `onboarding/` | 引导页专用（page_views / preferences_page_view） |

## 规范

### 组件设计原则
- **单一职责**：每个 Widget 只做一件事，build 方法不超过 50 行
- **无状态优先**：能用 `StatelessWidget` 的不用 `StatefulWidget`
- **参数设计**：必要参数用 `required`，可选参数提供合理默认值

### 样式规范
```dart
// 正确：引用主题
color: Theme.of(context).colorScheme.primary
padding: const EdgeInsets.all(AppTheme.spacingMedium)

// 错误：硬编码（禁止）
color: Color(0xFF1976D2)
padding: const EdgeInsets.all(16)  // 除非是一次性间距
```

### 文本国际化
- Widget 中所有用户可见文本必须使用 `AppLocalizations.of(context)`
- Tooltip、semanticsLabel 同样需要国际化

### 动画规范
- 复杂 Lottie 动画使用 `LottieAnimationWidget`（封装了加载、缓存逻辑）
- 简单过渡动画使用 Flutter 内置 `AnimatedContainer`、`AnimatedOpacity` 等
- 自定义动画使用 `AnimationController` + `dispose()` 中取消

### 列表性能
```dart
// 长列表必须用 builder 模式
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) => QuoteItemWidget(item: items[index]),
)

// 禁止
Column(children: items.map((e) => QuoteItemWidget(item: e)).toList())
```

### Context 安全
- 异步操作后访问 context 前检查 `mounted`
- 禁止将 `BuildContext` 保存为成员变量

## 与 Services 交互
```dart
// 读取数据（不监听）
final db = context.read<DatabaseService>();

// 监听状态变化
final db = context.watch<DatabaseService>();
// 或
Consumer<DatabaseService>(
  builder: (context, db, child) => ...,
)
```
