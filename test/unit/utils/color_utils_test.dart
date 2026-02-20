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
    });

    group('Theme-based colors', () {
      const surfaceColor = Colors.white;

      test('getPageBackgroundColor handles brightness', () {
        // Dark mode
        expect(
          ColorUtils.getPageBackgroundColor(surfaceColor, Brightness.dark),
          surfaceColor,
        );

        // Light mode
        final expectedLight = Color.alphaBlend(
          ColorUtils.withOpacitySafe(surfaceColor, 0.82),
          Colors.white,
        );
        expect(
          ColorUtils.getPageBackgroundColor(surfaceColor, Brightness.light),
          expectedLight,
        );
      });

      test('getCardBackgroundColor handles brightness', () {
        // Dark mode
        expect(
          ColorUtils.getCardBackgroundColor(surfaceColor, Brightness.dark),
          surfaceColor,
        );

        // Light mode
        final expectedLight = Color.lerp(surfaceColor, Colors.white, 0.08)!;
        expect(
          ColorUtils.getCardBackgroundColor(surfaceColor, Brightness.light),
          expectedLight,
        );
      });

      test('getNoteListBackgroundColor handles brightness', () {
        // Dark mode
        expect(
          ColorUtils.getNoteListBackgroundColor(surfaceColor, Brightness.dark),
          const Color(0xFF2A2A2A),
        );

        // Light mode
        final expectedLight = Color.alphaBlend(
          ColorUtils.withOpacitySafe(surfaceColor, 0.3),
          Colors.white,
        );
        expect(
          ColorUtils.getNoteListBackgroundColor(surfaceColor, Brightness.light),
          expectedLight,
        );
      });

      test('getSearchBoxBackgroundColor handles brightness', () {
        // Dark mode
        final expectedDark = Color.lerp(surfaceColor, Colors.white, 0.05)!;
        expect(
          ColorUtils.getSearchBoxBackgroundColor(surfaceColor, Brightness.dark),
          expectedDark,
        );

        // Light mode
        final expectedLight = Color.lerp(surfaceColor, Colors.white, 0.04)!;
        expect(
          ColorUtils.getSearchBoxBackgroundColor(
            surfaceColor,
            Brightness.light,
          ),
          expectedLight,
        );
      });
    });
  });
}
