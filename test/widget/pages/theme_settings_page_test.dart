import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/pages/theme_settings_page.dart';
import 'package:thoughtecho/theme/app_theme.dart';
import 'package:thoughtecho/theme/theme_style.dart';
import 'package:thoughtecho/utils/theme_style_labels.dart';

import '../../test_harness.dart';

void main() {
  const brightnessKey = Key('theme-brightness-probe');
  const primaryColorKey = Key('theme-primary-color-probe');

  setUpAll(() async {
    await TestHarness.initialize();
  });

  Finder findColorSwatch(Color color) {
    return find.byWidgetPredicate((widget) {
      if (widget is! Container || widget.decoration is! BoxDecoration) {
        return false;
      }
      final decoration = widget.decoration! as BoxDecoration;
      return decoration.shape == BoxShape.circle &&
          decoration.color?.toARGB32() == color.toARGB32();
    });
  }

  Widget buildTestApp(AppTheme appTheme) {
    return ChangeNotifierProvider<AppTheme>.value(
      value: appTheme,
      child: Consumer<AppTheme>(
        builder: (context, theme, _) {
          return MaterialApp(
            theme: theme.createLightThemeData(),
            darkTheme: theme.createDarkThemeData(),
            themeMode: theme.themeMode,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) {
              return Stack(
                children: [
                  child ?? const SizedBox.shrink(),
                  Positioned(
                    left: 0,
                    top: 0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Theme.of(context).brightness.name,
                          key: brightnessKey,
                        ),
                        Container(
                          key: primaryColorKey,
                          width: 8,
                          height: 8,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
            home: const ThemeSettingsPage(),
          );
        },
      ),
    );
  }

  group('ThemeSettingsPage', () {
    testWidgets('accepts dynamic color updates during app rebuilds',
        (tester) async {
      final appTheme = AppTheme();
      final lightScheme = ColorScheme.fromSeed(seedColor: Colors.teal);
      final darkScheme = ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: Brightness.dark,
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AppTheme>.value(
          value: appTheme,
          child: Consumer<AppTheme>(
            builder: (context, theme, _) {
              theme.updateDynamicColorScheme(lightScheme, darkScheme);
              return MaterialApp(
                theme: theme.createLightThemeData(),
                darkTheme: theme.createDarkThemeData(),
                themeMode: theme.themeMode,
                home: const SizedBox.shrink(),
              );
            },
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('groups handmade styles apart from generated ones',
        (tester) async {
      final appTheme = AppTheme();

      await tester.pumpWidget(buildTestApp(appTheme));
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(ThemeSettingsPage)),
      );
      final signatureHeader = find.text(l10n.themeStyleGroupSignature);
      final systemHeader = find.text(l10n.themeStyleGroupSystem);
      expect(signatureHeader, findsOneWidget);
      expect(systemHeader, findsOneWidget);

      double top(Finder finder) => tester.getTopLeft(finder).dy;

      // 分组判据是 isGenerated 这个取值，不是硬编码的风格名单：
      // 手工色板必须全部落在「心迹特色」组里，取色风格全部落在「系统配色」组里。
      for (final style in ThemeStyle.values) {
        final name = find.text(themeStyleLabel(l10n, style).$1);
        expect(name, findsOneWidget, reason: '${style.name} 没有渲染出来');
        if (style.isGenerated) {
          expect(top(name), greaterThan(top(systemHeader)),
              reason: '${style.name} 应该在系统配色组里');
        } else {
          expect(top(name), greaterThan(top(signatureHeader)));
          expect(top(name), lessThan(top(systemHeader)),
              reason: '${style.name} 应该在心迹特色组里');
        }
      }
    });

    testWidgets('switches app theme mode to dark when dark option is tapped', (
      tester,
    ) async {
      final appTheme = AppTheme();

      await tester.pumpWidget(buildTestApp(appTheme));
      await tester.pumpAndSettle();

      expect(find.text('light'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.dark_mode));
      await tester.pumpAndSettle();

      expect(find.text('dark'), findsOneWidget);
      expect(appTheme.themeMode, ThemeMode.dark);
    });

    testWidgets('applies selected custom theme color to app theme', (
      tester,
    ) async {
      final appTheme = AppTheme();
      // 默认风格是手工色板，自定义色和动态取色卡片会被藏起来（只对取色风格生效），
      // 所以先切回 material 再测自定义色。
      await appTheme.setThemeStyle(ThemeStyle.material);

      await tester.pumpWidget(buildTestApp(appTheme));
      await tester.pumpAndSettle();

      // 顶部多了「主题风格」卡片（还带分组标题）后，自定义色卡片落在测试视口之外，
      // ListView 根本不会构建它，ensureVisible 会因为找不到 widget 而报错，
      // 必须先把列表滚过去。
      final l10n = AppLocalizations.of(
        tester.element(find.byType(ThemeSettingsPage)),
      );
      await tester.scrollUntilVisible(
        find.text(l10n.useCustomThemeColor),
        200,
      );
      await tester.pumpAndSettle();

      final customColorSwitch = find.byType(Switch).first;
      await tester.ensureVisible(customColorSwitch);
      await tester.pumpAndSettle();
      await tester.tap(customColorSwitch);
      await tester.pumpAndSettle();

      final redSwatch = findColorSwatch(Colors.red).first;
      await tester.ensureVisible(redSwatch);
      await tester.pumpAndSettle();
      await tester.tap(redSwatch);
      await tester.pumpAndSettle();

      final probe = tester.widget<Container>(find.byKey(primaryColorKey));
      final expected = ColorScheme.fromSeed(
        seedColor: Colors.red,
        brightness: Brightness.light,
      ).primary;

      expect(appTheme.useCustomColor, isTrue);
      expect(appTheme.customColor, Colors.red);
      expect(probe.color, expected);
    });
  });
}
