import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/theme/theme_style.dart';
import 'package:thoughtecho/widgets/common/paper_rule_background.dart';

/// 纹理层的不变量：**没有纹理的风格不该在树里多一层绘制**。
///
/// 这条比「纸墨下有没有线」更重要——记录页滚动性能敏感，
/// 每张卡片多一个 CustomPaint 会实打实增加 build 与 raster 的量。
void main() {
  Widget host(ThemeStyle style, {Widget? child}) {
    final form = style.form;
    return MaterialApp(
      theme: ThemeData(
        extensions: [AppShapeTokens.fromForm(form, Brightness.light)],
      ),
      home: Scaffold(
        body: PaperRuleBackground(
          borderRadius: BorderRadius.circular(form.cardRadius),
          child: child ?? const SizedBox(width: 200, height: 200),
        ),
      ),
    );
  }

  Finder ruleLayer() => find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.painter.runtimeType.toString().contains('PaperRule'),
      );

  testWidgets('material 风格下不插入任何绘制层', (tester) async {
    await tester.pumpWidget(host(ThemeStyle.material));
    expect(ruleLayer(), findsNothing);
  });

  testWidgets('素笺不画横线', (tester) async {
    await tester.pumpWidget(host(ThemeStyle.plain));
    expect(ruleLayer(), findsNothing);
  });

  testWidgets('纸与墨画横线', (tester) async {
    await tester.pumpWidget(host(ThemeStyle.paper));
    expect(ruleLayer(), findsOneWidget);
  });

  testWidgets('主题里没注册令牌时安全降级，不崩也不画', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PaperRuleBackground(
          borderRadius: BorderRadius.circular(6),
          child: const SizedBox(width: 100, height: 100),
        ),
      ),
    );
    expect(ruleLayer(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('测试开关能关掉纹理', (tester) async {
    PaperRuleBackground.disableForTesting = true;
    addTearDown(() => PaperRuleBackground.disableForTesting = false);
    await tester.pumpWidget(host(ThemeStyle.paper));
    expect(ruleLayer(), findsNothing);
  });

  testWidgets('零高度和极端尺寸下不抛异常', (tester) async {
    await tester.pumpWidget(
      host(ThemeStyle.paper, child: const SizedBox(width: 200, height: 0)),
    );
    expect(tester.takeException(), isNull);
  });
}
