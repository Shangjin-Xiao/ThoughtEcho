import 'dart:ui';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/theme/app_theme.dart';
import 'package:thoughtecho/theme/theme_style.dart';

/// 手工色板没有 M3 tonal palette 那样的算法保证，任何一次手改色值都可能把
/// 某一对前景/背景压到看不清。这里把 WCAG AA 的要求钉成测试，改色板必须先过这一关。
///
/// 阈值取 WCAG 2.1：正文 4.5:1，大字与图形 3:1。
/// 卡片描边一类纯装饰性的边框不在校验范围内——WCAG 1.4.11 只要求「用于识别状态的」
/// 界面元素达到 3:1，强行拉高会把细边框逼成粗黑线。
void main() {
  group('主题风格色板对比度', () {
    for (final style in ThemeStyle.values) {
      final palette = style.palette;
      if (palette == null) {
        // material 由取色算法生成，对比度由 M3 的色调层级保证，不在此校验。
        continue;
      }

      for (final brightness in Brightness.values) {
        final colors = palette.forBrightness(brightness);
        final label = '${style.name} / ${brightness.name}';

        test('$label 正文与次要文字在纸和卡片上都可读', () {
          expectContrast(
              colors.ink, colors.background, 4.5, '$label 正文墨色 / 背景');
          expectContrast(colors.ink, colors.card, 4.5, '$label 正文墨色 / 卡片');
          expectContrast(
              colors.inkMuted, colors.background, 4.5, '$label 次要墨色 / 背景');
          expectContrast(colors.inkMuted, colors.card, 4.5, '$label 次要墨色 / 卡片');
        });

        test('$label 强调色与容器上的文字可读', () {
          expectContrast(colors.onAccent, colors.accent, 4.5, '$label 强调上的文字');
          expectContrast(colors.onAccentContainer, colors.accentContainer, 4.5,
              '$label 强调容器上的文字');
        });

        test('$label 危险状态可读', () {
          expectContrast(colors.onDanger, colors.danger, 4.5, '$label 危险上的文字');
          expectContrast(colors.onDangerContainer, colors.dangerContainer, 4.5,
              '$label 危险容器上的文字');
        });

        test('$label 强调色本身作为图标和大字可辨', () {
          expectContrast(
              colors.accent, colors.background, 3.0, '$label 强调 / 背景');
          expectContrast(colors.accent, colors.card, 3.0, '$label 强调 / 卡片');
          expectContrast(
              colors.danger, colors.background, 3.0, '$label 危险 / 背景');
        });
      }
    }
  });

  group('ColorScheme 映射', () {
    test('每种手工风格的亮暗都能产出对应亮度的 ColorScheme', () {
      for (final style in ThemeStyle.values) {
        final palette = style.palette;
        if (palette == null) continue;
        for (final brightness in Brightness.values) {
          final scheme =
              palette.forBrightness(brightness).toColorScheme(brightness);
          expect(scheme.brightness, brightness);
          expect(scheme.surface, palette.forBrightness(brightness).background);
          expect(scheme.onSurface, palette.forBrightness(brightness).ink);
        }
      }
    });

    // 卡片色刻意不落在 M3 的 surfaceContainer 梯度上。
    //
    // M3 在暗色下期望 surfaceContainerLowest 是整条梯度里最暗的一档，但这两套色板
    // 都让卡片比页面底色更亮——「纸叠在桌面上」的隐喻在亮暗两种模式下都成立，
    // 暗色模式不该把纸压得比桌面还暗。App 又把 cardTheme 绑在 surfaceContainerLowest
    // 上（`app_theme.dart` 的 createLight/DarkThemeData），所以这一档必须是卡片色。
    //
    // 因此这里校验两条真正的不变量，而不是 M3 的梯度假设：
    // 卡片始终比页面底色亮且可区分，且 surfaceContainer 往上那段仍然单调。
    test('卡片比页面底色亮且可区分', () {
      for (final style in ThemeStyle.values) {
        final palette = style.palette;
        if (palette == null) continue;
        for (final brightness in Brightness.values) {
          final colors = palette.forBrightness(brightness);
          final label = '${style.name} / ${brightness.name}';
          final cardLum = colors.card.computeLuminance();
          final bgLum = colors.background.computeLuminance();
          expect(
            cardLum,
            greaterThan(bgLum),
            reason: '$label 卡片没有比页面底色亮，纸张层次会塌掉',
          );
          expect(
            contrastRatio(colors.card, colors.background),
            greaterThan(1.03),
            reason: '$label 卡片和页面底色几乎一样，看不出卡片边界',
          );
        }
      }
    });

    test('surfaceContainer 往上的梯度单调', () {
      for (final style in ThemeStyle.values) {
        final palette = style.palette;
        if (palette == null) continue;
        for (final brightness in Brightness.values) {
          final scheme =
              palette.forBrightness(brightness).toColorScheme(brightness);
          final ramp = <Color>[
            scheme.surfaceContainer,
            scheme.surfaceContainerHigh,
            scheme.surfaceContainerHighest,
          ];
          final luminances = ramp.map((c) => c.computeLuminance()).toList();
          // 亮色模式越往上越深，暗色模式越往上越亮。
          final descending = brightness == Brightness.light;
          for (var i = 1; i < luminances.length; i++) {
            final ok = descending
                ? luminances[i] <= luminances[i - 1] + 1e-9
                : luminances[i] >= luminances[i - 1] - 1e-9;
            expect(
              ok,
              isTrue,
              reason: '${style.name} / ${brightness.name} '
                  'surfaceContainer 梯度在第 $i 档反向了：$luminances',
            );
          }
        }
      }
    });

    test('material 风格没有手工色板，走取色算法', () {
      expect(ThemeStyle.material.palette, isNull);
      expect(ThemeStyle.material.isGenerated, isTrue);
      expect(ThemeStyle.paper.isGenerated, isFalse);
      expect(ThemeStyle.plain.isGenerated, isFalse);
    });

    // 只换颜色的观感就是「换了一套 Material 主题色」。辨识度主要由形状、字体、
    // 阴影承担，这几条把它们钉住，防止后续无意中把手工风格退化回 Material 长相。
    test('FAB 有自己的圆角令牌，material 下保持 M3 的 16', () {
      // 16 不等于 cardRadius(18) 也不等于 buttonRadius(12)：M3 规范里 FAB 本来
      // 就独立，硬映射到别的令牌会让 material 出现可见的像素变化。
      expect(ThemeStyleForm.material.fabRadius, 16);
      for (final style in ThemeStyle.values) {
        if (style.isGenerated) continue;
        expect(
          style.form.fabRadius,
          lessThan(ThemeStyleForm.material.fabRadius),
          reason: '${style.name} 的 FAB 没有跟着方下来',
        );
      }
    });

    test('手工风格的圆角明显小于 Material', () {
      for (final style in ThemeStyle.values) {
        if (style.isGenerated) continue;
        final form = style.form;
        expect(
          form.cardRadius,
          lessThan(ThemeStyleForm.material.cardRadius / 2),
          reason: '${style.name} 的卡片圆角接近 Material，纸的方正感出不来',
        );
        expect(
            form.buttonRadius, lessThan(ThemeStyleForm.material.buttonRadius));
        expect(form.inputRadius, lessThan(ThemeStyleForm.material.inputRadius));
      }
    });

    test('手工风格用描边而不是投影做层次', () {
      for (final style in ThemeStyle.values) {
        final form = style.form;
        if (style.isGenerated) {
          expect(form.borderWidth, 0, reason: 'Material 保持原有投影层次');
          continue;
        }
        expect(form.borderWidth, greaterThan(0));
        for (final brightness in Brightness.values) {
          expect(
            form.shadowOpacity(brightness),
            lessThan(ThemeStyleForm.material.shadowOpacity(brightness)),
            reason: '${style.name} / ${brightness.name} 投影没有压下去',
          );
        }
      }
    });

    test('手工风格指向系统衬线体且不打包字体文件', () {
      for (final style in ThemeStyle.values) {
        final form = style.form;
        if (style.isGenerated) {
          expect(form.fontFamily, isNull, reason: 'Material 保持系统默认字体');
          continue;
        }
        // 首选族名必须是通用族 `serif`，具名字体只能待在回退链里。
        //
        // 反过来写（首选 Songti SC、serif 垫底）在 Android 上中文不会变衬线：
        // Flutter 的 fontFamilyFallback 不是 CSS 的 font-family，首选族名解析不到时
        // CJK 字符走引擎默认字体通道，排在后面的 serif 拿不到「要衬线」这个上下文，
        // 也就命中不了 AOSP 给 NotoSerifCJK 标的 fallbackFor="serif"。
        // 这是 2026-08-02 真机实测的结论，别把顺序调回去。
        expect(form.fontFamily, 'serif');
        expect(form.fontFamilyFallback, isNotNull);
        // 具名字体给不解析通用族名的平台兜底：iOS/macOS 的 Songti SC、Windows 的 SimSun。
        expect(form.fontFamilyFallback, contains('Songti SC'));
        expect(form.fontFamilyFallback, contains('SimSun'));
        expect(
          form.fontFamilyFallback,
          isNot(contains('serif')),
          reason: 'serif 已经是首选族名，回退链里重复一次没有意义',
        );
      }
    });

    test('AppShapeTokens 在两端之间插值，切换风格不会瞬跳', () {
      final a =
          AppShapeTokens.fromForm(ThemeStyleForm.material, Brightness.light);
      final b = AppShapeTokens.fromForm(ThemeStyleForm.paper, Brightness.light);
      final mid = a.lerp(b, 0.5);
      expect(mid.cardRadius, (a.cardRadius + b.cardRadius) / 2);
      expect(mid.borderWidth, (a.borderWidth + b.borderWidth) / 2);
      // 类型不匹配时原样返回，不能抛。
      expect(a.lerp(null, 0.5), same(a));
    });

    test('material 的令牌投影与原静态常量肉眼无差', () {
      // 这一条保护的是「迁移不改变 material 观感」：把 AppTheme.*Shadow 换成
      // AppShapeTokens 的 getter 之后，material 风格下不能有可见变化。
      final tokens =
          AppShapeTokens.fromForm(ThemeStyleForm.material, Brightness.light);
      final pairs = <String, (List<BoxShadow>, List<BoxShadow>)>{
        'rest': (tokens.restShadow, AppTheme.defaultShadow),
        'low': (tokens.lowShadow, AppTheme.lightShadow),
        'raised': (tokens.raisedShadow, AppTheme.hoverShadow),
        'accent': (tokens.accentShadow, AppTheme.accentShadow),
      };
      pairs.forEach((label, pair) {
        final (derived, legacy) = pair;
        expect(derived.length, legacy.length, reason: '$label 层数不一致');
        for (var i = 0; i < derived.length; i++) {
          expect(derived[i].color.a, closeTo(legacy[i].color.a, 0.002),
              reason: '$label 第 $i 层 alpha 偏离');
          expect(derived[i].blurRadius, closeTo(legacy[i].blurRadius, 0.01),
              reason: '$label 第 $i 层 blur 偏离');
          expect(derived[i].offset, legacy[i].offset);
          expect(derived[i].spreadRadius, legacy[i].spreadRadius);
        }
      });
    });

    test('手工风格的投影明显比 material 淡', () {
      for (final style in ThemeStyle.values) {
        if (style.isGenerated) continue;
        for (final brightness in Brightness.values) {
          final tokens = AppShapeTokens.fromForm(style.form, brightness);
          final baseline =
              AppShapeTokens.fromForm(ThemeStyleForm.material, brightness);
          expect(
            tokens.restShadow.first.color.a,
            lessThan(baseline.restShadow.first.color.a),
            reason: '${style.name} / ${brightness.name} 投影没压下去',
          );
          expect(tokens.restShadow.first.blurRadius,
              lessThan(baseline.restShadow.first.blurRadius));
        }
      }
    });

    test('纹理开关是令牌取值，只有纸与墨画横线', () {
      expect(ThemeStyleForm.material.ruleSpacing, 0, reason: 'Material 不该有纸纹');
      expect(ThemeStyleForm.plain.ruleSpacing, 0, reason: '素笺是素的');
      expect(ThemeStyleForm.paper.ruleSpacing, greaterThan(0));
      expect(ThemeStyleForm.paper.ruleOpacity, greaterThan(0));
      // opacity 是 alpha，越界会在 withValues 里断言。
      expect(ThemeStyleForm.paper.ruleOpacity, lessThanOrEqualTo(1));
      // spacing 为 0 的风格必须同时把 opacity 归零，两个判据不能打架。
      for (final style in ThemeStyle.values) {
        final form = style.form;
        if (form.ruleSpacing == 0) expect(form.ruleOpacity, 0);
      }
    });

    test('纸张横线间距必须等于正文字号乘行高，否则文字会逐行漂移', () {
      // 曾经 ruleSpacing 写死 26 而正文行高是 16×1.5=24，每行漂 2px，
      // 几行之后文字就骑到线上，看起来像「卡片背了一张格子图」。
      // 横线间距只能从「字号 × 行高」推导，不能各写各的——字号也进了这个乘积，
      // 因为衬线风格把正文放大了（bodyFontScale），只跟行高走会重新漂起来。
      for (final style in ThemeStyle.values) {
        final form = style.form;
        if (form.ruleSpacing == 0) continue;
        expect(
          form.ruleSpacing,
          closeTo(16.0 * form.bodyFontScale * form.bodyLineHeight, 0.01),
          reason: '${style.name} 的横线间距和正文行高对不上',
        );
      }
    });

    test('衬线风格不吃黑体的减重补偿，且正文行高比 Material 松', () {
      // 减重补偿是为黑体在 Impeller 下变粗做的；衬线体横画本来就细，
      // 再减 50 就发灰发虚——这是手工风格「可读性差」的直接原因。
      for (final style in ThemeStyle.values) {
        final form = style.form;
        if (form.fontFamily == null) continue;
        expect(
          form.variableWeightCompensation,
          0,
          reason: '${style.name} 用了衬线体却仍在减重',
        );
        expect(
          form.bodyLineHeight,
          greaterThan(ThemeStyleForm.material.bodyLineHeight),
          reason: '${style.name} 用衬线体就得比黑体的行高松',
        );
      }
      // Material 保持全额补偿，行为一行不变。
      expect(ThemeStyleForm.material.variableWeightCompensation, 1);
      expect(ThemeStyleForm.material.bodyLineHeight, 1.5);
    });

    test('衬线风格要同时加字重和字号，光关掉减重不够', () {
      // 「不减重」只是回到 M3 原生 w400，而 w400 的中文衬线横画本来就细到
      // 半个物理像素，抗锯齿后发灰——这正是用户说「比 Material 差很多」的地方。
      // 两个补偿的分工：字重在支持多档字重的设备上收益最大，字号是所有平台
      // 都一定生效的兜底，缺一个都不够。
      for (final style in ThemeStyle.values) {
        final form = style.form;
        if (form.fontFamily == null) continue;
        expect(
          form.readingWeightFloor,
          greaterThan(FontWeight.w400.value),
          reason: '${style.name} 用衬线体却没有抬字重下限',
        );
        expect(
          form.bodyFontScale,
          greaterThan(1),
          reason: '${style.name} 用衬线体却没有放大正文',
        );
      }
      // Material 两项都是恒等取值，像素一点不变。
      expect(ThemeStyleForm.material.readingWeightFloor, 0);
      expect(ThemeStyleForm.material.bodyFontScale, 1);
    });

    test('字重是下限不是增量：M3 已经 w500 的标题不会被顶成粗体', () {
      // 只有 Regular / Bold 两档的中文衬线体会把 w600 匹配成 Bold，
      // 列表标题会集体变粗。下限必须落在 w500——正好等于 titleMedium /
      // titleSmall 的 M3 默认值，对它们零影响。
      for (final style in ThemeStyle.values) {
        final floor = style.form.readingWeightFloor;
        if (floor == 0) continue;
        expect(
          floor,
          lessThanOrEqualTo(FontWeight.w500.value),
          reason: '${style.name} 的字重下限高过 M3 标题字重，标题会变粗体',
        );
      }

      // readingWeight 是这条规则的唯一实现，textTheme 和 AppBar 都走它。
      const paper = ThemeStyleForm.paper;
      expect(paper.readingWeight(FontWeight.w400), FontWeight.w500); // 抬起来
      expect(paper.readingWeight(FontWeight.w500), FontWeight.w500); // 不动
      expect(paper.readingWeight(FontWeight.w700), FontWeight.w700); // 不降
      // material 没有下限，任何输入原样返回——AppBar 标题一个像素不变。
      const material = ThemeStyleForm.material;
      for (final w in FontWeight.values) {
        expect(material.readingWeight(w), w);
      }
    });

    test('正文放大幅度有上限，不能靠字号硬堆可读性', () {
      // 字号是最好使的一根杠杆，也最容易滥用：正文一旦超过 Material 的 1.15 倍，
      // 列表密度、设置项、卡片折叠阈值全要跟着崩。
      for (final style in ThemeStyle.values) {
        expect(style.form.bodyFontScale, inInclusiveRange(1.0, 1.15));
      }
    });

    test('富文本的加粗降档跟着字重补偿走，不会在衬线风格下把粗体抹平', () {
      // quill 的 DefaultStyles 不继承 textTheme，加粗规则要单独喂。
      // 那套 w700→w500 的降档是给黑体做的；系统中文衬线常常只有 Regular/Bold
      // 两档，降到 w500 会匹配回 Regular，用户标的粗体直接消失。
      // 判据是这个令牌的取值，widget 里不允许出现 if (style == ...)。
      for (final style in ThemeStyle.values) {
        final tokens = AppTypographyTokens.fromForm(style.form);
        expect(
          tokens.variableWeightCompensation,
          style.form.variableWeightCompensation,
        );
      }
      // 过渡动画里粗体不能闪，所以走离散切换而不是插值。
      final material = AppTypographyTokens.fromForm(ThemeStyleForm.material);
      final paper = AppTypographyTokens.fromForm(ThemeStyleForm.paper);
      for (final t in const [0.0, 0.25, 0.49]) {
        expect(material.lerp(paper, t), same(material));
      }
      for (final t in const [0.5, 0.75, 1.0]) {
        expect(material.lerp(paper, t), same(paper));
      }
      expect(material.lerp(null, 0.5), same(material));
    });

    test('行距不插值，避免过渡中途出现极密的横线', () {
      final a =
          AppShapeTokens.fromForm(ThemeStyleForm.material, Brightness.light);
      final b = AppShapeTokens.fromForm(ThemeStyleForm.paper, Brightness.light);
      // 若行距参与线性插值，t 稍大于 0 时会得到接近 0 的行距，
      // 绘制循环次数按 1/spacing 爆炸。这里要求它始终等于某一端的取值。
      for (final t in const [0.01, 0.25, 0.49, 0.5, 0.75, 0.99]) {
        final spacing = a.lerp(b, t).ruleSpacing;
        expect(
          spacing == a.ruleSpacing || spacing == b.ruleSpacing,
          isTrue,
          reason: 't=$t 时行距被插值成了 $spacing',
        );
      }
      // 淡入淡出仍然交给 opacity，所以它必须是连续的。
      expect(a.lerp(b, 0.5).ruleOpacity, (a.ruleOpacity + b.ruleOpacity) / 2);
    });

    test('默认风格是纸与墨，未知或缺失的持久化取值回退到它', () {
      // 默认值只应写在 ThemeStyle.defaultStyle 一处。
      expect(ThemeStyle.defaultStyle, ThemeStyle.paper);
      expect(ThemeStyle.fromName(null), ThemeStyle.defaultStyle);
      expect(ThemeStyle.fromName('nope'), ThemeStyle.defaultStyle);
      expect(ThemeStyle.fromName('paper'), ThemeStyle.paper);
      expect(ThemeStyle.fromName('plain'), ThemeStyle.plain);
    });
  });
}

/// WCAG 2.1 相对对比度：(L1 + 0.05) / (L2 + 0.05)，L 为相对亮度，L1 为较亮的一方。
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void expectContrast(
    Color foreground, Color background, double min, String what) {
  final ratio = contrastRatio(foreground, background);
  expect(
    ratio,
    greaterThanOrEqualTo(min),
    reason: '$what 对比度 ${ratio.toStringAsFixed(2)}:1，低于要求的 $min:1',
  );
}
