import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/theme/app_semantic_colors.dart';
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

        // 手工风格用衬线体，横画细，同一个对比度看着比黑体虚。所以次要文字
        // 单独加一条比 AA 更严的线，而且**纸和卡片两种底色都要过**——次要文字
        // 大量渲染在卡片上，只按页面底色验算会漏（纸墨暗色就漏过一次：
        // 底色 7.66 达标、卡片只有 6.76）。
        test('$label 次要文字在两种底色上都达到 7:1', () {
          expectContrast(
              colors.inkMuted, colors.background, 7.0, '$label 次要墨色 / 背景');
          expectContrast(colors.inkMuted, colors.card, 7.0, '$label 次要墨色 / 卡片');
        });

        // 墨色是和风格正交的一维，所以「风格 × 墨色 × 亮暗」每一格都要单独验算：
        // 容器色是由墨色和纸色调出来的，只验默认那一支等于没验。
        for (final option in ThemeAccent.values) {
          final accent = ThemeAccentColors.resolve(option, colors, brightness);
          final accentLabel = '$label / ${option.name}';

          test('$accentLabel 强调色与容器上的文字可读', () {
            expectContrast(
                accent.onAccent, accent.accent, 4.5, '$accentLabel 强调上的文字');
            expectContrast(accent.onContainer, accent.container, 4.5,
                '$accentLabel 强调容器上的文字');
          });

          // 强调色不只做大色块：它还是链接文字、小图标和 12sp 的标签色
          // （首页「今日思考」、探索页「全部」都是），按图形的 3:1 配会糊掉。
          // 这条要求它在纸和卡片两种底色上都达到正文的 4.5:1。
          test('$accentLabel 强调色当小字用也够实', () {
            expectContrast(
                accent.accent, colors.background, 4.5, '$accentLabel 强调 / 背景');
            expectContrast(
                accent.accent, colors.card, 4.5, '$accentLabel 强调 / 卡片');
          });
        }

        // 第二三辅助色不随墨色变，但 `toColorScheme` 把 onSecondary / onTertiary
        // 映射到了强调族的 onAccent（也就是纸色）。那一对过去没有任何断言覆盖，
        // 改 secondary 的色值时不会有人发现文字已经压在底下了。
        test('$label 辅助色上的文字可读', () {
          final onAuxiliary =
              brightness == Brightness.dark ? colors.background : colors.card;
          expectContrast(
              onAuxiliary, colors.secondary, 4.5, '$label 第二辅助色上的文字');
          expectContrast(onAuxiliary, colors.tertiary, 4.5, '$label 第三辅助色上的文字');
        });

        test('$label 危险状态可读', () {
          expectContrast(colors.onDanger, colors.danger, 4.5, '$label 危险上的文字');
          expectContrast(colors.onDangerContainer, colors.dangerContainer, 4.5,
              '$label 危险容器上的文字');
          expectContrast(
              colors.danger, colors.background, 3.0, '$label 危险 / 背景');
        });

        // 状态色过去是全局固定的 M3 取值，落在暖色纸面上是三块外来色。
        // 现在它们进了色板，就得和色板里其它颜色一样接受验算。
        test('$label 状态色在纸和卡片上都可辨', () {
          for (final (name, fg) in <(String, Color)>[
            ('成功', colors.success),
            ('警告', colors.warning),
            ('收藏', colors.favorite),
          ]) {
            expectContrast(fg, colors.background, 3.0, '$label $name / 背景');
            expectContrast(fg, colors.card, 3.0, '$label $name / 卡片');
          }
          expectContrast(colors.onSuccessContainer, colors.successContainer,
              4.5, '$label 成功容器上的文字');
          expectContrast(colors.onWarningContainer, colors.warningContainer,
              4.5, '$label 警告容器上的文字');
          // 收藏是实心小色块（红心徽章里的数字），不是浅色容器。
          expectContrast(
              colors.onFavorite, colors.favorite, 4.5, '$label 收藏徽章上的数字');
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
          final colors = palette.forBrightness(brightness);
          final scheme = colors.toColorScheme(
            brightness,
            ThemeAccentColors.resolve(style.defaultAccent, colors, brightness),
          );
          expect(scheme.brightness, brightness);
          expect(scheme.surface, colors.background);
          expect(scheme.onSurface, colors.ink);
        }
      }
    });

    test('换墨色只换强调族，纸色一格不动', () {
      // 这是「墨色」这一维成立的前提：如果换墨顺带把 surface 或 outline 改了，
      // 那它就不是强调色维度，而是第四套、第五套风格。
      for (final style in ThemeStyle.values) {
        final palette = style.palette;
        if (palette == null) continue;
        for (final brightness in Brightness.values) {
          final colors = palette.forBrightness(brightness);
          final schemes = [
            for (final accent in ThemeAccent.values)
              colors.toColorScheme(
                brightness,
                ThemeAccentColors.resolve(accent, colors, brightness),
              ),
          ];
          for (final scheme in schemes) {
            expect(scheme.surface, schemes.first.surface);
            expect(scheme.surfaceContainerLowest,
                schemes.first.surfaceContainerLowest);
            expect(scheme.onSurface, schemes.first.onSurface);
            expect(scheme.onSurfaceVariant, schemes.first.onSurfaceVariant);
            expect(scheme.outline, schemes.first.outline);
            expect(scheme.outlineVariant, schemes.first.outlineVariant);
            expect(scheme.error, schemes.first.error);
          }
          // 而强调色本身必须真的各不相同，否则这个设置就是个摆设。
          final primaries = schemes.map((s) => s.primary).toSet();
          expect(primaries.length, ThemeAccent.values.length,
              reason: '${style.name} / ${brightness.name} 有两支墨色长得一样');
        }
      }
    });

    test('墨色默认值：纸墨是赭石，素笺是黛青', () {
      expect(ThemeStyle.paper.defaultAccent, ThemeAccent.umber);
      expect(ThemeStyle.plain.defaultAccent, ThemeAccent.celadon);
    });

    test('墨色解析认不出就返回 null，不在解析里兜底到某一支', () {
      // 「用户没选过」只能由 null 表达。解析时兜底到具体某一支，会让存储里的坏值
      // 把这个状态永久抹掉：之后切到另一套风格，拿到的还是上一套的默认墨。
      expect(ThemeAccent.tryFromName(null), isNull);
      expect(ThemeAccent.tryFromName('nope'), isNull);
      expect(ThemeAccent.tryFromName(''), isNull);
      for (final accent in ThemeAccent.values) {
        expect(ThemeAccent.tryFromName(accent.name), accent);
      }
    });

    test('没选过墨色时，每套风格各自跟随自己的默认支', () {
      // 兜底发生在 accentFor 而不是解析里，所以「跟随风格」对每套风格都成立：
      // 同一个未设置状态，问纸墨得到赭石，问素笺得到黛青。
      final appTheme = AppTheme();
      expect(appTheme.accentFor(ThemeStyle.paper), ThemeAccent.umber);
      expect(appTheme.accentFor(ThemeStyle.plain), ThemeAccent.celadon);
    });

    test('状态色随色板下发，手工风格不再借用 Material 的那套', () {
      for (final style in ThemeStyle.values) {
        final palette = style.palette;
        if (palette == null) continue;
        for (final brightness in Brightness.values) {
          final colors = palette.forBrightness(brightness);
          final semantic = colors.toSemanticColors();
          final label = '${style.name} / ${brightness.name}';
          // 八个字段全部对一遍：漏掉任何一个，那一项悄悄改回 M3 取值都测不出来。
          expect(semantic.success, colors.success, reason: '$label success');
          expect(semantic.successContainer, colors.successContainer,
              reason: '$label successContainer');
          expect(semantic.onSuccessContainer, colors.onSuccessContainer,
              reason: '$label onSuccessContainer');
          expect(semantic.warning, colors.warning, reason: '$label warning');
          expect(semantic.warningContainer, colors.warningContainer,
              reason: '$label warningContainer');
          expect(semantic.onWarningContainer, colors.onWarningContainer,
              reason: '$label onWarningContainer');
          expect(semantic.favorite, colors.favorite, reason: '$label favorite');
          expect(semantic.onFavorite, colors.onFavorite,
              reason: '$label onFavorite');

          // 借用 M3 那套固定值正是这次要修的问题：三个前景色都不能等于它。
          final m3 = brightness == Brightness.dark
              ? AppSemanticColors.dark
              : AppSemanticColors.light;
          expect(semantic.favorite, isNot(m3.favorite),
              reason: '$label 的收藏色还是 M3 那支');
          expect(semantic.success, isNot(m3.success),
              reason: '$label 的成功色还是 M3 那支');
          expect(semantic.warning, isNot(m3.warning),
              reason: '$label 的警告色还是 M3 那支');
        }
      }
    });

    test('手工风格的自绘表面全部落在色板给的纸上', () {
      for (final style in ThemeStyle.values) {
        final palette = style.palette;
        if (palette == null) continue;
        for (final brightness in Brightness.values) {
          final colors = palette.forBrightness(brightness);
          final surfaces = AppSurfaceTokens.fromPalette(colors);
          expect(surfaces.card, colors.card);
          expect(surfaces.page, colors.background);
          // 暗色下曾经写死 0xFF2A2A2A，把整套暖色纸换成一块与色板无关的灰。
          expect(surfaces.noteList, colors.background);
          expect(surfaces.searchBox,
              Color.lerp(colors.card, colors.background, 0.5));
        }
      }
    });

    test('material 的自绘表面保持迁移前 ColorUtils 的算法', () {
      // 这一条保护的是「迁移不改变 material 观感」：四个系数都是从
      // ColorUtils 逐字搬过来的，改动其中任何一个都会让 material 的页面变色。
      const surface = Color(0xFF102030);
      const white = Color(0xFFFFFFFF);

      final dark = AppSurfaceTokens.fromScheme(
        const ColorScheme.dark(surface: surface),
        Brightness.dark,
      );
      expect(dark.page, surface);
      expect(dark.card, surface);
      expect(dark.noteList, const Color(0xFF2A2A2A));
      expect(dark.searchBox, Color.lerp(surface, white, 0.05));

      final light = AppSurfaceTokens.fromScheme(
        const ColorScheme.light(surface: surface),
        Brightness.light,
      );
      expect(light.page,
          Color.alphaBlend(surface.withValues(alpha: 0.82), Colors.white));
      expect(light.card, Color.lerp(surface, white, 0.08));
      expect(light.noteList,
          Color.alphaBlend(surface.withValues(alpha: 0.3), Colors.white));
      expect(light.searchBox, Color.lerp(surface, white, 0.04));
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
          // 门槛从 1.03 抬到 1.12：纸墨曾经是 1.06，配上被压到 0.03 的投影，
          // 首页那张大卡在真机上就是一个「空框」——过了旧门槛，但层次实际是塌的。
          expect(
            contrastRatio(colors.card, colors.background),
            greaterThan(1.12),
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
          final colors = palette.forBrightness(brightness);
          final scheme = colors.toColorScheme(
            brightness,
            ThemeAccentColors.resolve(style.defaultAccent, colors, brightness),
          );
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

    test('手工风格指向随包衬线体，通用族名不再出现在任何位置', () {
      for (final style in ThemeStyle.values) {
        final form = style.form;
        if (style.isGenerated) {
          expect(form.fontFamily, isNull, reason: 'Material 保持系统默认字体');
          continue;
        }
        // 首选族名必须是随包字体的族名。
        //
        // 这里曾经是通用族 `serif`，靠 AOSP 给 NotoSerifCJK 标的
        // fallbackFor="serif" 命中系统衬线体。那条路只在 Android 上成立：
        // iOS 的 CoreText 不解析通用族名，`serif` 解析不到时 CJK 直接走引擎默认
        // 字体（苹方），而 fontFamilyFallback 只在首选族缺某个字形时才逐个回退，
        // 首选族整个解析不到时排在后面的 Songti SC 根本没机会被查询——
        // 两套手工风格的正文在 iOS 上一直是黑体。
        expect(form.fontFamily, ThemeStyleForm.bundledSerif);
        expect(form.fontFamilyFallback, isNotNull);
        // 回退链的角色变了：不再是「首选没命中的备胎」，而是「子集里没这个字时去哪找」。
        // 排系统衬线体，好让混排出来的生僻字至少还是衬线。
        expect(form.fontFamilyFallback, contains('Songti SC'));
        expect(form.fontFamilyFallback, contains('SimSun'));
        expect(
          form.fontFamilyFallback,
          isNot(contains('serif')),
          reason: '通用族名在 iOS 上解析不到，留在回退链里只是噪音',
        );
      }
    });

    test('随包字体的族名和 pubspec 声明一致', () {
      // 族名对不上 = 字体加载不到 = 悄悄退回系统默认字体，界面上看不出报错。
      // 这条断言把 pubspec 和 Dart 常量钉在一起。
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(
        pubspec,
        contains('family: ${ThemeStyleForm.bundledSerif}'),
        reason: 'pubspec.yaml 里没有声明这个字体族',
      );
      expect(
        pubspec,
        contains('asset: ${ThemeStyleForm.bundledSerifAsset}'),
        reason: 'pubspec.yaml 声明的 asset 路径和常量对不上',
      );
      expect(
        File(ThemeStyleForm.bundledSerifAsset).existsSync(),
        isTrue,
        reason: '字体产物不在仓库里，跑 scripts/fonts/build_serif_subset.py 生成',
      );
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

    test('横线是底纹不是表格线：透明度收着给', () {
      // 横线曾经铺满整张笔记卡（穿过日期行、图片、标签胶囊和按钮行），
      // 那时 0.55 的浓度看着就是一张糊在卡片上的格子图。现在它只画在正文块里
      // （见 quote_item_widget 的 _buildQuoteContentSection），要收着画。
      expect(ThemeStyleForm.paper.ruleOpacity, lessThanOrEqualTo(0.45));
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

    test('默认风格是 material，未知或缺失的持久化取值回退到它', () {
      // 默认值只应写在 ThemeStyle.defaultStyle 一处。
      //
      // 钉死具体是哪一套，是因为改它等于**让所有没选过风格的老用户在升级后
      // 外观直接变**——这套主题没有迁移逻辑。改这一行前先想清楚这件事。
      expect(ThemeStyle.defaultStyle, ThemeStyle.material);
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
