# FontWeight 重构完成交接文档

## 概述
已将项目中大约 296 处 inline FontWeight 用法成功重构为 `Theme.of(context).textTheme` 的引用。此项工作有效解决了 Flutter 升级到 3.41+ 之后，由于 variable font `wght` 轴精准映射和 Impeller 引擎切换带来的 Android 端字体全局变粗问题。现在，应用中的所有字重已统一收口到 `AppTheme` 集中管理。

---

## 改造明细

### 1. 字重映射规则
在重构过程中，我们严格遵循了以下映射原则（并在 copyWith 中保留了颜色、行高、字距等其他样式属性）：

| 原始样式 | 语义化分类 | 重构后的 Theme 引用 |
|:---|:---|:---|
| `fontSize: 20`+ / `FontWeight.bold` | 对话框/页面标题 | `Theme.of(context).textTheme.titleLarge` |
| `fontSize: 16` / `FontWeight.bold` | 区块标题 | `Theme.of(context).textTheme.titleMedium` |
| `fontSize: 14` / `FontWeight.bold` | 列表项标题 | `Theme.of(context).textTheme.titleSmall` |
| `fontSize: 14` / `FontWeight.w600` | 按钮/标签 | `Theme.of(context).textTheme.labelLarge` |
| `fontSize: 12` / `FontWeight.w500` | 小标签/说明 | `Theme.of(context).textTheme.labelMedium` |
| `fontSize: 14` / `FontWeight.w500` | 正文强调 | `Theme.of(context).textTheme.bodyMedium` |

### 2. 特殊场景处理
* **条件字重**（如 `isSelected ? FontWeight.w600 : FontWeight.normal`）：此类用法保留了 inline 逻辑，但对字重级别进行了整体降档（例如将 `w600 : w500` 降档为 `w500 : w400`），从而在 variable font 的精准渲染下保持合适的视觉对比度。
* **无 BuildContext 场景**（如 `SvgToImageService` 中的 Canvas 低级文字绘制）：保留了原始 inline 字重。因为其不处于 Widget 树中，无法且无需通过 `Theme.of(context)` 获取主题，且不使用系统的 Roboto 变体字体进行呈现。
* **PDF 导出**（`pw.FontWeight`）：已严格排除，未做任何修改，避免破坏 PDF 导出的排版结构。

---

## 主题全局配置

在 `lib/theme/app_theme.dart` 的 `_fixAndroidVariableFontWeight` 方法中，我们统一配置了全局字重，这使得未来如果需要再次全局调整字重，只需在该处修改即可：

* **Android 12+ (RobotoFlex variable font 优化)**：
  - `titleLarge` / `titleMedium` / `titleSmall` -> `FontWeight.w600` (降档，避免 w700 太粗)
  - `labelLarge` -> `FontWeight.w500`
  - `labelMedium` / `labelSmall` -> `FontWeight.w400`
* **其他平台 (常规字重体系)**：
  - `titleLarge` / `titleMedium` / `titleSmall` -> `FontWeight.w600`
  - `labelLarge` / `labelMedium` / `labelSmall` -> `FontWeight.w500`

---

## 验证结果
* **格式化**：所有 Dart 文件均已通过 `dart format` 格式化。
* **静态分析**：执行 `flutter analyze --no-fatal-infos` 结果为 **No issues found**，无任何编译错误或警告。
* **自动化测试**：运行 `flutter test test/all_tests.dart` 结果为 **All 280 tests passed**，保证了重构的鲁棒性，未引入任何破坏性变更。

---

## 注意事项
1. 新增 UI 组件时，请**绝对避免**直接声明 `fontWeight: FontWeight.bold/w600/w500`，请优先使用 `Theme.of(context).textTheme` 中的预设槽位。
2. 如需微调文字粗细，请直接在 `lib/theme/app_theme.dart` 的 `_fixAndroidVariableFontWeight` 方法中调整对应槽位的 `fontWeight` 映射，该调整将全局安全生效。
