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
