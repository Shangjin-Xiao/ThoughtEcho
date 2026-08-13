import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/color_utils.dart';

void main() {
  group('ColorUtils', () {
    const Color testColor = Color(0xFF2196F3); // Blue

    test('createMaterialColor generates MaterialColor with all swatches', () {
      final materialColor = createMaterialColor(testColor);

      expect(materialColor, isA<MaterialColor>());
      expect(materialColor.toARGB32(), testColor.toARGB32());

      // Verify swatches exist at generated indices (50, 150, 250...950)
      expect(materialColor[50], isNotNull);
      for (int i = 150; i <= 950; i += 100) {
        expect(materialColor[i], isNotNull);
      }
    });

    test('adjustColor returns a color with same value', () {
      final adjusted = adjustColor(testColor);
      expect(adjusted.toARGB32(), testColor.toARGB32());
    });

    test('ColorValueExtension.applyOpacity applies opacity correctly', () {
      final opacityColor = testColor.applyOpacity(0.5);
      expect(opacityColor.a, 0.5); // Use .a for alpha (0.0-1.0)
      expect(opacityColor.r, testColor.r);
      expect(opacityColor.g, testColor.g);
      expect(opacityColor.b, testColor.b);
    });

    test('ColorExtension.withAlpha applies opacity correctly', () {
      final opacityColor = ColorExtension(testColor).withAlpha(0.3);
      expect(opacityColor.a, closeTo(0.3, 0.001));
      expect(opacityColor.r, testColor.r);
      expect(opacityColor.g, testColor.g);
      expect(opacityColor.b, testColor.b);

      // Test 0.0 opacity
      final zeroOpacity = ColorExtension(testColor).withAlpha(0.0);
      expect(zeroOpacity.a, 0.0);

      // Test 1.0 opacity
      final fullOpacity = ColorExtension(testColor).withAlpha(1.0);
      expect(fullOpacity.a, 1.0);
    });

    test('withOpacitySafe clamps opacity and applies correctly', () {
      // Normal case
      var result = ColorUtils.withOpacitySafe(testColor, 0.6);
      expect(result.a, closeTo(0.6, 0.001));

      // Clamp below 0
      result = ColorUtils.withOpacitySafe(testColor, -0.5);
      expect(result.a, 0.0);

      // Clamp above 1
      result = ColorUtils.withOpacitySafe(testColor, 1.5);
      expect(result.a, 1.0);

      // Exactly 0
      result = ColorUtils.withOpacitySafe(testColor, 0.0);
      expect(result.a, 0.0);

      // Exactly 1
      result = ColorUtils.withOpacitySafe(testColor, 1.0);
      expect(result.a, 1.0);
    });

    // 页面/卡片/记录页/搜索框四张表面的取值已经搬到 AppSurfaceTokens，
    // 对应的断言在 test/unit/theme/theme_style_contrast_test.dart。
  });
}
