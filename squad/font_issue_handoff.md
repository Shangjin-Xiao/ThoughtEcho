# 字体变粗问题 — 修复交接文档 (v2)

## 问题
Flutter 3.35 → 3.44 升级后，Android 上字体全局变粗。

## 根因
Flutter 3.41 起 FontWeight 自动驱动 variable font 的 wght 轴。Android 12+ 的 RobotoFlex 字形比旧静态 Roboto 笔画更粗。

## 前任方案的缺陷
用 `fontVariations` 在 theme TextTheme 上补偿 → **会通过 DefaultTextStyle merge 泄漏到 inline fontWeight**，导致 bold 文字反而变细。项目有 240+ 处 inline fontWeight，全部受影响。

## 当前方案（已实施）
在 theme TextTheme 中用**补偿后的 FontWeight 值**替代原始值：
- `FontWeight(350)` 替代 `w400`（正文）
- `FontWeight(440)` 替代 `w500`（label/title）
- 其他按比例下调

**优势**：widget 层 inline `fontWeight: FontWeight.bold` 会在 merge 时直接替换 fontWeight，不泄漏。

## 覆盖范围
- ✅ theme textTheme 的 15 个默认样式（大部分 UI 文本）
- ⚠️ 240 处 inline fontWeight 不受影响（保持引擎的新渲染）

## 补偿值可能需要调整
当前映射是估算值，用户需要在真机上看效果。如果觉得：
- 太细了 → 把 `weightMap` 里的值往上调（如 400→370）
- 还是太粗 → 往下调（如 400→330）

## 文件
- [`lib/theme/app_theme.dart`](file:///home/azureuser/ThoughtEcho/lib/theme/app_theme.dart) — `_compensateWeight()` 方法
