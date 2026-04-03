## 2026-03-13 - [Add tooltips to close buttons]
**Learning:** Tooltips for close buttons (`Icons.close`) without text labels are often missing, violating accessibility rules for screen readers.
**Action:** Always add `tooltip: MaterialLocalizations.of(context).closeButtonTooltip` to `IconButton` elements containing `Icons.close` to ensure they are accessible.
## 2024-04-03 - Added Semantics/Tooltips for IconButtons
**Learning:** Icon-only buttons often lack accessibility context for screen readers in Flutter. Using `tooltip` in `IconButton` or wrapping `InkWell` containing `Icon` with `Tooltip` provides semantics and mouse hover text automatically.
**Action:** Always add `tooltip` for `IconButton` or semantic labels for icon-only components.
