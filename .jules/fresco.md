## 2025-05-20 - SVGCardWidget Design Tokens & Theme Adaptability
**Learning:** Hardcoded `Colors.grey` and `Colors.red` fallbacks in card widgets break visual consistency across dark mode and custom paper/ink themes. Replacing them with `ColorScheme` surface and error containers resolves contrast and adaptability issues seamlessly.
**Action:** Always derive error/fallback container colors and borders from `ColorScheme.surfaceContainerHighest` or `ColorScheme.errorContainer` instead of fixed shade palettes.
