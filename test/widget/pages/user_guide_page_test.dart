import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/pages/user_guide_page.dart';
import 'package:thoughtecho/theme/app_semantic_colors.dart';
import 'package:thoughtecho/theme/theme_style.dart';
import 'package:thoughtecho/widgets/app_empty_animation.dart';

Widget _buildTestApp({
  bool disableAnimations = true,
}) {
  return MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(
      useMaterial3: true,
      extensions: [
        AppShapeTokens.fromForm(ThemeStyleForm.material, Brightness.light),
        AppSemanticColors.light,
      ],
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: disableAnimations,
      ),
      child: child!,
    ),
    home: const UserGuidePage(),
  );
}

Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pump();
    if (find.byType(SearchBar).evaluate().isNotEmpty) {
      break;
    }
  }
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    rootBundle.clear();
  });

  tearDown(() {
    rootBundle.clear();
  });

  testWidgets('搜索用户指南无结果时展示 AppEmptyAnimation 与未找到提示', (tester) async {
    await tester.pumpWidget(_buildTestApp());
    await _pumpUntilLoaded(tester);
    expect(find.byType(SearchBar), findsOneWidget);

    await tester.enterText(find.byType(SearchBar), '不存在的指南关键词xyz');
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(UserGuidePage)),
    );
    expect(find.byType(AppEmptyAnimation), findsOneWidget);
    final anim = tester.widget<AppEmptyAnimation>(
      find.byType(AppEmptyAnimation),
    );
    expect(anim.style, AppEmptyStyle.searchNoResult);
    expect(find.text(l10n.userGuideNoResults), findsOneWidget);
    expect(find.byIcon(Icons.search_off_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('短视口下搜索用户指南无结果不发生溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 420);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_buildTestApp());
    await _pumpUntilLoaded(tester);
    expect(find.byType(SearchBar), findsOneWidget);

    await tester.enterText(find.byType(SearchBar), '不存在的指南关键词xyz');
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pumpAndSettle();

    expect(find.byType(AppEmptyAnimation), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
