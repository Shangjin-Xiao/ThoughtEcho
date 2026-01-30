## 2025-05-20 - Custom Icon Buttons Accessibility
**Learning:** Custom interactive elements built with `InkWell` wrapping `Icon` (instead of `IconButton`) lack automatic accessibility features like tooltips.
**Action:** When identifying custom button implementations, explicitly wrap them in `Tooltip` widgets and ensure they have semantic labels if necessary.
