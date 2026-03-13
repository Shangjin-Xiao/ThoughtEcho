import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/pages/theme_settings_page.dart';
import 'package:thoughtecho/theme/app_theme.dart';

import '../../test_setup.dart';

void main() {
  const brightnessKey = Key('theme-brightness-probe');
  const primaryColorKey = Key('theme-primary-color-probe');

  setUpAll(() async {
    await TestSetup.setupWidgetTest();
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

      await tester.pumpWidget(buildTestApp(appTheme));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      await tester.tap(findColorSwatch(Colors.red).first);
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
