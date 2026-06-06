# 字体变粗问题 — 完整交接文档 v3

## 问题
Flutter 3.35→3.44 升级后，Android 上字体全局变粗。

## 根因（已验证）

有**两个叠加因素**：

### 1. FontWeight → wght 轴映射变更（Flutter 3.41, PR #175771）
- **3.35**：FontWeight 只用于选择最近的静态字体文件。w500/w600 可能 fallback 到同一个 Regular 文件，渲染结果一样细。
- **3.44**：FontWeight 精确驱动 variable font 的 wght 轴。w500 就是 500，w600 就是 600，不再"模糊匹配"。
- **结果**：之前很多看起来一样的字重现在有了真实差异，w600/bold 真的变粗了。

### 2. Impeller 渲染引擎替代 Skia
- Flutter 3.27：Impeller 成为 Android 默认渲染引擎
- Flutter 3.41：开始移除 Skia fallback 选项
- **Flutter 3.44（当前版本）：Skia 已被完全移除**（Android 10+），无法切回
- Impeller 的文字渲染路径与 Skia 不同，笔画粗细可能存在细微差异
- 项目从 3.35（Skia）直接跳到 3.44（强制 Impeller），两个引擎差异叠加

### ⚠️ 事实修正
Android 系统默认字体是**静态 Roboto**，不是 RobotoFlex。之前 agent 说"RobotoFlex 字形重绘导致变粗"是**错误的**。变粗是因为 Flutter 引擎对字重的处理方式变了，不是字体文件变了。

## 官方建议
Flutter 官方对此的建议很简单：**调整 FontWeight 值到你想要的视觉效果**。没有全局开关。

## 项目现状

### 数据
- `FontWeight.bold` (w700)：150 处
- `FontWeight.w600`：92 处
- `FontWeight.w500`：54 处
- 总计约 **296 处** inline fontWeight

### 已尝试的失败方案
1. ❌ **fontVariations 补偿**：会通过 DefaultTextStyle merge 泄漏，导致 inline fontWeight 失效
2. ❌ **仅 theme TextTheme 调整**：只影响引用 theme 的文字，240 处 inline 不受影响，造成同页粗细不一致

## 推荐方案：重构为 Theme 引用（一劳永逸）

### 思路
将 296 处 inline `TextStyle(fontWeight: FontWeight.xxx)` 改为引用 `Theme.of(context).textTheme.xxx`。以后调字重只改 theme 一处，全 app 跟着动，**所有平台生效**。

### 替换规则

根据 M3 Typography 规范，每种 inline 用法应映射到对应的 textTheme slot：

| 场景 | 当前写法 | 应改为 |
|------|----------|--------|
| 对话框/页面标题 | `TextStyle(fontSize: 20, fontWeight: FontWeight.bold)` | `Theme.of(context).textTheme.titleLarge` |
| 区块标题 | `TextStyle(fontSize: 16, fontWeight: FontWeight.bold)` | `Theme.of(context).textTheme.titleMedium` |
| 列表项标题 | `TextStyle(fontSize: 14, fontWeight: FontWeight.bold)` | `Theme.of(context).textTheme.titleSmall` |
| 按钮/标签 | `TextStyle(fontSize: 14, fontWeight: FontWeight.w600)` | `Theme.of(context).textTheme.labelLarge` |
| 小标签/说明 | `TextStyle(fontSize: 12, fontWeight: FontWeight.w500)` | `Theme.of(context).textTheme.labelMedium` |
| 正文 | `TextStyle(fontSize: 14)` | `Theme.of(context).textTheme.bodyMedium` |
| 需要额外样式 | `TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: red)` | `Theme.of(context).textTheme.titleMedium?.copyWith(color: red)` |

### 无法直接映射的情况
有些地方用 `fontWeight` 是有语义的（如条件判断 `isSelected ? FontWeight.bold : FontWeight.normal`），这类需要保留 inline fontWeight 但改用更合适的值。

### 执行方式

**建议用 AI 模型批量处理，逐文件审查替换**。可以按以下指令给模型：

```
对每个包含 FontWeight.bold / FontWeight.w600 / FontWeight.w500 的 .dart 文件：
1. 读取文件，理解每个 fontWeight 的上下文（标题？标签？正文？）
2. 根据 fontSize 和语义，映射到 Theme.of(context).textTheme 的对应 slot
3. 如果原代码有额外样式（color, letterSpacing 等），使用 copyWith 保留
4. 如果是条件判断型（isSelected ? bold : normal），保留 inline 但确认字重值合理
5. 确保 import 了 flutter/material.dart
6. 每个文件改完后运行 dart format 和 flutter analyze
```

### 改完后调整字重
重构完成后，所有字重集中在 theme 的 textTheme。如果还觉得粗，只需要在 `app_theme.dart` 的 `createLightThemeData()` / `createDarkThemeData()` 里调 textTheme 的 fontWeight 值即可全局生效。

## 注意事项

- 搜索网络确认最新 API，不要假设——这个问题已经被之前的 agent 多次误判
- `lib/services/delta_to_pdf_parser.dart` 和 `pdf_export_service.dart` 里的 `pw.FontWeight.bold` 是 pdf 库的类型，**不要改**
- `lib/gen_l10n/` 是生成文件，**不要改**
- 改完后在 Android 真机上对比 3.35 截图验证视觉效果
- Windows/iOS 不受此问题影响，但重构到 theme 引用对所有平台都是好的架构改进

## 相关文件
- 主题：`lib/theme/app_theme.dart`
- M3 Typography 定义：Flutter SDK `packages/flutter/lib/src/material/typography.dart` L2095-2149
- FontWeight 文档：Flutter SDK `bin/cache/pkg/sky_engine/lib/ui/text.dart` L57-61
