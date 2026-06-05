## 2026-03-13 - [Add tooltips to close buttons]
**Learning:** Tooltips for close buttons (`Icons.close`) without text labels are often missing, violating accessibility rules for screen readers.
**Action:** Always add `tooltip: MaterialLocalizations.of(context).closeButtonTooltip` to `IconButton` elements containing `Icons.close` to ensure they are accessible.
## 2026-04-03 - Added Semantics/Tooltips for IconButtons
**Learning:** Icon-only buttons often lack accessibility context for screen readers in Flutter. Using `tooltip` in `IconButton` or wrapping `InkWell` containing `Icon` with `Tooltip` provides semantics and mouse hover text automatically.
**Action:** Always add `tooltip` for `IconButton` or semantic labels for icon-only components.
## 2025-04-17 - [Add tooltip to motion photo close button]
**Learning:** In Flutter, icon-only buttons (`IconButton`) require an explicit `tooltip` to provide semantic labels for screen readers. Using `MaterialLocalizations.of(context).closeButtonTooltip` is a localized, zero-maintenance way to add this without modifying `l10n` resource files directly.
**Action:** When adding close/cancel icon buttons, always check for missing tooltips and use standard `MaterialLocalizations` when applicable.
## 2026-05-18 - Tooltips for Dynamic Icons
**Learning:** For dynamic icon buttons (like play/pause toggles), assigning a dynamic tooltip is crucial. While localized strings are ideal, a hardcoded English fallback (e.g., 'Pause' / 'Play') significantly improves screen reader comprehension over an unlabeled icon that changes. Avoid redundant `Semantics` wrappers around `Icon` and `Text` widgets, as `Text` is already read and `Icon` without a semantic label is ignored.
**Action:** When working on media controls or toggle buttons, ensure the `tooltip` property updates dynamically alongside the icon state. Do not shuffle structural `Semantics` tags without a proven need.
## 2026-05-01 - [Tooltip on icon-only buttons]
**Learning:** Icon-only buttons used throughout the application (such as the app bar action buttons and the input clear fields) may be missing tooltips, making it difficult for screen readers to explain what those buttons do.
**Action:** When creating or modifying `IconButton` components, always verify that a `tooltip` attribute containing localized strings from `AppLocalizations` is present, especially when it is icon-only.
## 2024-05-24 - Missing Tooltips on IconButtons
**Learning:** Found multiple instances where `IconButton` widgets were missing `tooltip` properties. This affects accessibility for screen readers and tooltips on web/desktop.
**Action:** Added semantic string tooltips or translated string references across the settings and subpages. The Python script was improved to find these, but `IconButton` wrappers can mask these errors from naive regex tools.
## 2025-05-18 - [Localize code copy button]
**Learning:** Hardcoded text like "复制代码" and "已复制" in `IconButton` tooltips inside `CodeBlockWidget` breaks accessibility for non-Chinese speakers using screen readers.
**Action:** Always extract text to ARB localization files and use `AppLocalizations.of(context)` for tooltips, ensuring screen readers receive correctly localized labels for UI actions.
## 2026-05-19 - [Fix Missing Semantic Labels for Custom GestureDetectors]
**Learning:** Found multiple custom `GestureDetector` widgets missing `Semantics` wrappers, making interactive UI elements inaccessible to screen readers. For instance, the video placeholder in `MediaPlayerWidget` and the close button in `FeatureGuidePopover`.
**Action:** Always wrap interactive `GestureDetector` and `InkWell` widgets (especially those without text) with `Semantics(button: true, label: ...)` to ensure keyboard navigation and screen reader accessibility.
## 2025-02-28 - [完善引导弹窗遮罩层的无障碍支持]
**Learning:** 自定义悬浮层（Overlay/Popover）中作为背景点击关闭的 GestureDetector 往往缺乏无障碍焦点和语意说明，屏幕阅读器用户无法感知这是一个可以用来关闭弹窗的可交互区域。
**Action:** 确保这种非文字说明的交互背景元素（如全屏透明遮罩）被 Semantics 包装，提供 `button: true` 和 `label: MaterialLocalizations.of(context).closeButtonTooltip`，以此提升无障碍体验。
## 2026-05-20 - [Fix Missing Tooltips for IconButton]
**Learning:** `pdf_preview_dialog.dart` where `IconButton` with `Icons.close` was missing a `tooltip` property.
**Action:** When adding close buttons inside standard dialogs and modals, always set `tooltip: MaterialLocalizations.of(context).closeButtonTooltip`.
