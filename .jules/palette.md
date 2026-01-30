# Palette's Journal

## 2024-05-24 - Icon Button Accessibility
**Learning:** Icon-only buttons (like "Favorite" or "More Options") are often ambiguous for screen reader users and those relying on visual tooltips.
**Action:** Always wrap icon-only buttons in a `Tooltip` widget or use the `tooltip` property if available (e.g., `PopupMenuButton`, `IconButton`). Ensure the tooltip text dynamically reflects the button's state (e.g., "Favorite" vs "Unfavorite"). This improves both accessibility (Semantics) and usability (Hover text).
