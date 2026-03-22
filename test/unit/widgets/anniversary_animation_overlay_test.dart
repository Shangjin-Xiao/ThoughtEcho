import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/widgets/anniversary_animation_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AnniversaryAnimationOverlay', () {
    testWidgets('首帧不应通过整屏 FadeTransition 延后显示背景遮罩', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: AnniversaryAnimationOverlay(onDismiss: () {}),
        ),
      );

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is FadeTransition &&
              widget.child is AnnotatedRegion<SystemUiOverlayStyle>,
        ),
        findsNothing,
      );

      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
