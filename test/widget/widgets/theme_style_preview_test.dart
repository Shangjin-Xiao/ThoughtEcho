import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/theme/app_theme.dart';
import 'package:thoughtecho/theme/theme_style.dart';
import 'package:thoughtecho/widgets/theme_style_preview.dart';

import '../../test_harness.dart';

/// 预览卡画的是「[ThemeStylePreview.style] 这套风格长什么样」，
/// 和当前生效的是哪套风格无关。颜色和形状本来就由外部传入 / 从令牌取，
/// 唯一会漏的是**字体族**——这里就盯这一件事。
void main() {
  setUpAll(() async {
    await TestHarness.initialize();
  });

  /// 把预览卡放进 [current] 这套风格的主题里渲染，取出样张「永」的最终样式。
  Future<TextStyle> sampleStyleOf(
    WidgetTester tester, {
    required ThemeStyle preview,
    required ThemeStyle current,
  }) async {
    final appTheme = AppTheme();
    await appTheme.setThemeStyle(current);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme.createLightThemeData(),
        home: Scaffold(
          body: ThemeStylePreview(
            style: preview,
            brightness: Brightness.light,
            colorScheme: appTheme.colorSchemeFor(preview, Brightness.light),
          ),
        ),
      ),
    );
    final text = tester.widget<Text>(find.text('永'));
    // Text.style 里没写的项由外层 DefaultTextStyle 补——「继承外层」这件事
    // 正是这里要验的，所以必须看合并之后的结果，不能只看 Text.style。
    final defaultStyle = DefaultTextStyle.of(
      tester.element(find.text('永')),
    ).style;
    return defaultStyle.merge(text.style);
  }

  testWidgets('material 的预览卡在衬线风格下仍然是黑体', (tester) async {
    // 这是真出过的 bug：material 的 fontFamily 令牌是 null，而 null 在 TextStyle
    // 里的意思是「继承外层」。用户切到纸墨之后，material 那张卡的样张跟着变成宋体，
    // 三张卡字体一模一样——预览最该说清楚的那件事反而看不出来了。
    for (final current in [ThemeStyle.paper, ThemeStyle.plain]) {
      final style = await sampleStyleOf(
        tester,
        preview: ThemeStyle.material,
        current: current,
      );
      expect(
        style.fontFamily,
        isNot(ThemeStyleForm.bundledSerif),
        reason: '当前风格是 ${current.name} 时，material 的样张被继承成了衬线',
      );
      expect(style.fontFamily, isNotNull, reason: 'material 的样张字体族没落位');
    }
  });

  testWidgets('手工风格的预览卡在 material 下就是衬线', (tester) async {
    // 反过来同样要成立：预览跟着 style 走，不跟着当前主题走。
    for (final preview in [ThemeStyle.paper, ThemeStyle.plain]) {
      final style = await sampleStyleOf(
        tester,
        preview: preview,
        current: ThemeStyle.material,
      );
      expect(style.fontFamily, ThemeStyleForm.bundledSerif);
      // 样张的字重要和真正的正文一致，否则预览里的「永」比正文细一档。
      expect(style.fontWeight, FontWeight(preview.form.bodyWeightFloor));
    }
  });
}
