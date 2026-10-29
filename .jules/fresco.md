## 2025-05-20 - SVGCardWidget Design Tokens & Theme Adaptability
**Learning:** Hardcoded `Colors.grey` and `Colors.red` fallbacks in card widgets break visual consistency across dark mode and custom paper/ink themes. Replacing them with `ColorScheme` surface and error containers resolves contrast and adaptability issues seamlessly.
**Action:** Always derive error/fallback container colors and borders from `ColorScheme.surfaceContainerHighest` or `ColorScheme.errorContainer` instead of fixed shade palettes.

## 2025-10-27 - Emergency Pages Responsive Layouts & Design Tokens
**Learning:** Emergency views with fixed vertical spacing or `Spacer()` within `Column` can cause vertical layout overflow on smaller viewports. Replacing hardcoded `Container` and `Spacer()` constructs with `Card` components wrapped in `SingleChildScrollView` guarantees error content visibility and Theme Token alignment across diverse screen heights.
**Action:** Always wrap full-screen error or emergency fallback views in `SingleChildScrollView` and use `Card` with `AppShapeTokens.of(context).cardRadius`.
