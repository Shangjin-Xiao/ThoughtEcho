# 字体变粗问题 — 交接文档

## 问题
Flutter 3.35→3.44 升级后，Android 上字体全局变粗。

## 根因（两个叠加因素）

### 1. FontWeight → wght 轴精准映射（Flutter 3.41, PR #175771）
- **3.35**：FontWeight 只用于选择最近的静态字体文件。w500/w600 可能 fallback 到同一个文件，渲染结果一样细。
- **3.44**：FontWeight 精确驱动 variable font 的 wght 轴。w600 就是 600，不再"模糊匹配"。

### 2. Skia → Impeller 渲染引擎切换
- 项目在 3.35 时经 DevTools 确认使用的是 **Skia**
- Flutter 3.44 已**完全移除 Skia**（Android 10+），强制 Impeller
- 两个引擎的文字渲染路径不同，笔画粗细存在差异

### 事实澄清
- Android 系统默认字体是**静态 Roboto**，不是 RobotoFlex
- 变粗是 Flutter 引擎行为变了，不是字体文件变了

## 已尝试的失败方案
1. ❌ **fontVariations 补偿**：通过 DefaultTextStyle merge 泄漏，导致 inline fontWeight 失效
2. ❌ **仅 theme TextTheme 调整**：只影响引用 theme 的文字，inline 不受影响，造成粗细不一致

## 待执行方案：重构为 Theme 引用

将 ~296 处 inline FontWeight 改为引用 `Theme.of(context).textTheme.xxx`，以后调字重只改 theme 一处。

### 数据
- `FontWeight.bold` (w700)：150 处
- `FontWeight.w600`：92 处
- `FontWeight.w500`：54 处

### 替换规则

| 场景 | 当前写法 | 应改为 |
|------|----------|--------|
| 对话框/页面标题 | `TextStyle(fontSize: 20, fontWeight: FontWeight.bold)` | `Theme.of(context).textTheme.titleLarge` |
| 区块标题 | `TextStyle(fontSize: 16, fontWeight: FontWeight.bold)` | `Theme.of(context).textTheme.titleMedium` |
| 列表项标题 | `TextStyle(fontSize: 14, fontWeight: FontWeight.bold)` | `Theme.of(context).textTheme.titleSmall` |
| 按钮/标签 | `TextStyle(fontSize: 14, fontWeight: FontWeight.w600)` | `Theme.of(context).textTheme.labelLarge` |
| 小标签/说明 | `TextStyle(fontSize: 12, fontWeight: FontWeight.w500)` | `Theme.of(context).textTheme.labelMedium` |
| 正文强调 | `TextStyle(fontSize: 14, fontWeight: FontWeight.w500)` | `Theme.of(context).textTheme.bodyMedium` |
| 需要额外样式 | `TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: red)` | `Theme.of(context).textTheme.titleMedium?.copyWith(color: red)` |
| 条件判断型 | `isSelected ? FontWeight.bold : FontWeight.normal` | 保留 inline，但考虑降档为 `w600 : w400` |

### 不要改的
- `pw.FontWeight.bold`（pdf 库类型，在 `delta_to_pdf_parser.dart` 和 `pdf_export_service.dart`）
- `lib/gen_l10n/` 下的所有文件
- `*.mocks.dart` 文件

### 改完后
在 `app_theme.dart` 的 `createLightThemeData()` / `createDarkThemeData()` 里统一调 textTheme 的 fontWeight 即可全局生效。

## 相关文件
- 主题：`lib/theme/app_theme.dart`
- 项目规范：根目录 `AGENTS.md`
