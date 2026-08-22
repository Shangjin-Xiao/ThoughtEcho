import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/theme/app_theme.dart';
import 'package:thoughtecho/theme/theme_style.dart';

import '../../test_harness.dart';

/// `theme_style_contrast_test.dart` 校验的是**令牌取值**，这里校验**落地结果**。
///
/// 两者不能互相替代：令牌对了但接线错了（漏掉某一级、或者顺序搞反被下一层覆盖），
/// 用户看到的还是老样子。所以这里直接断言 `createLightThemeData()` 的产物。
///
/// **读这些断言前要知道一件事**：`ThemeData.textTheme` 里的字号、行高、字重
/// **大部分是 null**。它们由 `Theme` widget 在 build 时按 locale 的字形几何
/// （`ThemeData.localize` + `Typography.dense` 之类）补齐。所以「某一级的 fontSize
/// 是 null」是**正常**的，代表「没被主题改动，交给几何」；反过来，**非 null
/// 就意味着这一级被风格显式钉住了**。下面每条断言都按这个含义来读。
void main() {
  setUpAll(() async {
    await TestHarness.initialize();
  });

  Future<ThemeData> themeFor(ThemeStyle style) async {
    final appTheme = AppTheme();
    await appTheme.setThemeStyle(style);
    return appTheme.createLightThemeData();
  }

  /// AppBar 实际用的标题样式。
  ///
  /// `appBarTheme.titleTextStyle` 目前**是 null**（FlexColorScheme 没设它），
  /// M3 的 AppBar 因此回落到 `textTheme.titleLarge`——风格是从那条路跟上的。
  /// 断言必须按这个优先级写：直接断言 `titleTextStyle` 会拿到 null 而误判，
  /// 只断言 `titleLarge` 又会在将来某天 `titleTextStyle` 变成非空时假绿。
  TextStyle? appBarTitleStyle(ThemeData theme) =>
      theme.appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge;

  test('material 的排版一个像素不变', () async {
    final theme = await themeFor(ThemeStyle.material);
    final text = theme.textTheme;
    // 字体族保持 FlexColorScheme 给的 Roboto，没被换成衬线。
    expect(text.bodyLarge?.fontFamily, 'Roboto');
    expect(text.labelSmall?.fontFamily, 'Roboto');
    // 字号 / 行高 / 字重全部留给字形几何——一项都没被钉住，就是「没动过」。
    for (final entry in {
      'displaySmall': text.displaySmall,
      'titleLarge': text.titleLarge,
      'titleMedium': text.titleMedium,
      'bodyLarge': text.bodyLarge,
      'bodyMedium': text.bodyMedium,
      'bodySmall': text.bodySmall,
      'labelLarge': text.labelLarge,
    }.entries) {
      expect(entry.value?.fontSize, isNull, reason: '${entry.key} 字号被钉住了');
      expect(entry.value?.height, isNull, reason: '${entry.key} 行高被钉住了');
      expect(entry.value?.fontWeight, isNull, reason: '${entry.key} 字重被钉住了');
    }
    // AppBar 标题跟着 titleLarge 走，同样一项没钉。
    expect(appBarTitleStyle(theme)?.fontWeight, isNull);
    expect(appBarTitleStyle(theme)?.fontFamily, 'Roboto');
  });

  for (final style in [ThemeStyle.paper, ThemeStyle.plain]) {
    final form = style.form;

    group('${style.name} 的排版', () {
      test('正文换衬线、按 readingFontScale 放大、字重抬到正文下限', () async {
        final text = (await themeFor(style)).textTheme;

        // M3 的字号/行高：几何里给的值，风格在它上面做缩放。
        final levels = <String, (TextStyle?, double, double)>{
          'bodyLarge': (text.bodyLarge, 16, 24 / 16),
          'bodyMedium': (text.bodyMedium, 14, 20 / 14),
          'bodySmall': (text.bodySmall, 12, 16 / 12),
        };
        levels.forEach((name, spec) {
          final (resolved, m3Size, m3Height) = spec;
          expect(
            resolved?.fontFamily,
            ThemeStyleForm.bundledSerif,
            reason: '$name 没换字体族',
          );
          expect(
            resolved?.fontSize,
            closeTo(m3Size * form.readingFontScale, 0.001),
            reason: '$name 没跟上 readingFontScale',
          );
          expect(
            resolved?.height,
            closeTo(
              m3Height *
                  form.bodyLineHeight /
                  ThemeStyleForm.material.bodyLineHeight,
              0.001,
            ),
            reason: '$name 没跟上 bodyLineHeight',
          );
          expect(
            resolved?.fontWeight,
            FontWeight(form.bodyWeightFloor),
            reason: '$name 没抬到正文字重下限',
          );
        });

        // bodyLarge 的「字号 × 行高」就是纸张横线间距，两边必须严格相等，
        // 否则文字会逐行相对横线漂移。
        expect(text.bodyLarge?.height, closeTo(form.bodyLineHeight, 0.001));
        final lineHeight = text.bodyLarge!.fontSize! * text.bodyLarge!.height!;
        if (form.ruleSpacing > 0) {
          expect(form.ruleSpacing, closeTo(lineHeight, 0.01));
        }
      });

      test('标题换衬线、和正文同幅放大、字重比正文高一档；大字只换族', () async {
        final text = (await themeFor(style)).textTheme;
        final titleWeight = FontWeight(form.titleWeightFloor);
        final titles = <String, (TextStyle?, double)>{
          'titleLarge': (text.titleLarge, 22),
          'titleMedium': (text.titleMedium, 16),
          'titleSmall': (text.titleSmall, 14),
        };
        titles.forEach((name, spec) {
          final (resolved, m3Size) = spec;
          expect(resolved?.fontFamily, ThemeStyleForm.bundledSerif,
              reason: '$name 没换字体族');
          // **标题必须和正文同幅放大**：只放大 body* 的话 bodyLarge(17) 会比它
          // 上面一级的 titleMedium(16) 还大，M3 的层级在衬线风格下是倒着的。
          expect(
            resolved?.fontSize,
            closeTo(m3Size * form.readingFontScale, 0.001),
            reason: '$name 没跟上 readingFontScale',
          );
          expect(resolved?.fontWeight, titleWeight, reason: '$name 没抬到标题字重下限');
        });
        // 层级的两条硬关系：标题比同级正文重一档，且不比它小。
        expect(text.titleMedium!.fontWeight!.value,
            greaterThan(text.bodyLarge!.fontWeight!.value));
        expect(text.titleMedium!.fontSize, text.bodyLarge!.fontSize);
        expect(text.titleSmall!.fontSize, text.bodyMedium!.fontSize);
        // 标题的行高不跟着正文放松——紧排是标题该有的样子，交给几何。
        expect(text.titleMedium?.height, isNull);
        // display / headline 只换族，字重留给几何，否则大标题会显得笨重。
        expect(text.headlineSmall?.fontFamily, ThemeStyleForm.bundledSerif);
        expect(text.headlineSmall?.fontWeight, isNull);
        expect(text.displaySmall?.fontFamily, ThemeStyleForm.bundledSerif);
        expect(text.displaySmall?.fontWeight, isNull);
      });

      test('label* 一项都不改，保持系统黑体', () async {
        final text = (await themeFor(style)).textTheme;
        // 按钮、胶囊、导航栏标签是 11–14sp 的功能性文字，中文衬线在这个尺寸下
        // 糊成一团，又不承担任何风格识别。换了才是 bug。
        for (final entry in {
          'labelLarge': text.labelLarge,
          'labelMedium': text.labelMedium,
          'labelSmall': text.labelSmall,
        }.entries) {
          expect(entry.value?.fontFamily, 'Roboto',
              reason: '${entry.key} 被换成衬线了');
          expect(entry.value?.fontSize, isNull, reason: '${entry.key} 字号被钉住了');
          expect(entry.value?.fontWeight, isNull,
              reason: '${entry.key} 字重被钉住了');
        }
      });

      test('AppBar 标题跟上字体族和字重', () async {
        final title = appBarTitleStyle(await themeFor(style));
        expect(title?.fontFamily, ThemeStyleForm.bundledSerif);
        expect(title?.fontWeight, FontWeight(form.titleWeightFloor));
      });

      test('排版令牌注册进了主题，富文本的加粗降档会整段跳过', () async {
        final tokens = (await themeFor(style)).extension<AppTypographyTokens>();
        expect(tokens, isNotNull, reason: '排版令牌没注册进主题');
        // 为 0 时 quote_content_widget 不会把 w700 降成 w500——只有
        // Regular/Bold 两档的衬线体会把 w500 匹配回 Regular，粗体会消失。
        expect(tokens!.variableWeightCompensation, 0);
      });
    });
  }
}
