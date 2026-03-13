## 2026-03-13 - [Add tooltips to close buttons]
**Learning:** Tooltips for close buttons (`Icons.close`) without text labels are often missing, violating accessibility rules for screen readers.
**Action:** Always add `tooltip: MaterialLocalizations.of(context).closeButtonTooltip` to `IconButton` elements containing `Icons.close` to ensure they are accessible.
