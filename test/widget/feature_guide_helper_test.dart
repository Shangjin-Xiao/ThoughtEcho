import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/services/feature_guide_service.dart';
import 'package:thoughtecho/utils/feature_guide_helper.dart';
import 'package:thoughtecho/widgets/feature_guide_popover.dart';

/// 记在内存里的引导状态，避开 MMKV。
class _FakeFeatureGuideService extends ChangeNotifier
    implements FeatureGuideService {
  final Set<String> shown = <String>{};

  @override
  bool hasShown(String guideId) => shown.contains(guideId);

  @override
  Future<void> markAsShown(String guideId) async {
    shown.add(guideId);
    notifyListeners();
  }

  @override
  bool hasShownAll(List<String> guideIds) => guideIds.every(hasShown);

  @override
  bool hasShownAny(List<String> guideIds) => guideIds.any(hasShown);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('showFirstAvailable 一次只弹一个，剩下的留到下次', (tester) async {
    final service = _FakeFeatureGuideService();
    late BuildContext hostContext;

    await tester.pumpWidget(
      ChangeNotifierProvider<FeatureGuideService>.value(
        value: service,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                hostContext = context;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );

    final pending = FeatureGuideHelper.showFirstAvailable(
      context: hostContext,
      guides: const [
        ('note_page_filter', null),
        ('note_page_favorite', null),
        ('note_page_expand', null),
      ],
      autoDismissDuration: const Duration(milliseconds: 50),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // 同一时刻只允许存在一个气泡。
    expect(find.byType(FeatureGuidePopover), findsOneWidget);

    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(await pending, isTrue);

    // 只消费掉第一个，后两个留给下次进入这个页面。
    expect(service.shown, {'note_page_filter'});
    expect(find.byType(FeatureGuidePopover), findsNothing);
  });

  testWidgets('已显示过的会被跳过，顺延到下一个未显示的', (tester) async {
    final service = _FakeFeatureGuideService()..shown.add('note_page_filter');
    late BuildContext hostContext;

    await tester.pumpWidget(
      ChangeNotifierProvider<FeatureGuideService>.value(
        value: service,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                hostContext = context;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );

    final pending = FeatureGuideHelper.showFirstAvailable(
      context: hostContext,
      guides: const [
        ('note_page_filter', null),
        ('note_page_favorite', null),
      ],
      autoDismissDuration: const Duration(milliseconds: 50),
    );

    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(await pending, isTrue);
    expect(service.shown, {'note_page_filter', 'note_page_favorite'});
  });
}
