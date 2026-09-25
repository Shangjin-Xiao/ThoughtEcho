import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/widgets/quote_card_helpers.dart';

void main() {
  group('QuoteCardColors.fromHex', () {
    const lightColorScheme = ColorScheme.light(
      surfaceContainerLowest: Color(0xFFFFFFFF),
      onSurface: Color(0xFF1C1B1F),
      onInverseSurface: Color(0xFFF4EFF4),
    );

    const darkColorScheme = ColorScheme.dark(
      surfaceContainerLowest: Color(0xFF0F0D13),
      onSurface: Color(0xFFE6E1E5),
      onInverseSurface: Color(0xFF313033),
    );

    test('空值或 null 时使用 surfaceContainerLowest 并选择高对比度文本色', () {
      final lightNull = QuoteCardColors.fromHex(null, lightColorScheme);
      expect(lightNull.cardColor, lightColorScheme.surfaceContainerLowest);
      expect(lightNull.baseContentColor, lightColorScheme.onSurface);

      final darkEmpty = QuoteCardColors.fromHex('', darkColorScheme);
      expect(darkEmpty.cardColor, darkColorScheme.surfaceContainerLowest);
      expect(darkEmpty.baseContentColor, darkColorScheme.onSurface);
    });

    test('亮色卡片在亮色主题下优先选择 onSurface', () {
      final colors = QuoteCardColors.fromHex('#FFFFFF', lightColorScheme);
      expect(colors.baseContentColor, lightColorScheme.onSurface);
    });

    test('亮色卡片在暗色主题下选择具有更高对比度的 onInverseSurface', () {
      final colors = QuoteCardColors.fromHex('#FFFFFF', darkColorScheme);
      expect(colors.baseContentColor, darkColorScheme.onInverseSurface);
    });

    test('暗色卡片在亮色主题下选择具有更高对比度的 onInverseSurface', () {
      final colors = QuoteCardColors.fromHex('#000000', lightColorScheme);
      expect(colors.baseContentColor, lightColorScheme.onInverseSurface);
    });

    test('暗色卡片在暗色主题下优先选择 onSurface', () {
      final colors = QuoteCardColors.fromHex('#000000', darkColorScheme);
      expect(colors.baseContentColor, darkColorScheme.onSurface);
    });

    test('非法十六进制颜色优雅降级为 surfaceContainerLowest', () {
      final colors = QuoteCardColors.fromHex('invalid-hex', lightColorScheme);
      expect(colors.cardColor, lightColorScheme.surfaceContainerLowest);
      expect(colors.baseContentColor, lightColorScheme.onSurface);
    });

    test('派生文本与图标颜色具有正确的透明度', () {
      final colors = QuoteCardColors.fromHex(null, lightColorScheme);
      final base = lightColorScheme.onSurface;
      expect(colors.primaryTextColor, base.withValues(alpha: 0.9));
      expect(colors.secondaryTextColor, base.withValues(alpha: 0.7));
      expect(colors.iconColor, base.withValues(alpha: 0.65));
    });
  });
}
