import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/widgets/anniversary_animation_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AnniversaryAnimationOverlay', () {
    testWidgets('首帧不应通过整屏 FadeTransition 延后显示背景遮罩', (tester) async {
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

    testWidgets('通过弹窗显示时不应额外引入整屏 FadeTransition', (tester) async {
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
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  showAnniversaryAnimationOverlay(context);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is FadeTransition &&
              (widget.opacity.toString().contains('DialogRoute<void>') ||
                  widget.opacity.toString().contains('RawDialogRoute<void>')) &&
              !widget.opacity.toString().contains('1.000; paused'),
        ),
        findsNothing,
      );

      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('显示浮层时不应主动切换 system UI mode', (tester) async {
      final platformCalls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        platformCalls.add(call);
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

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
        platformCalls.where(
          (call) => call.method == 'SystemChrome.setEnabledSystemUIMode',
        ),
        isEmpty,
      );

      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
