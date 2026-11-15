import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/utils/lottie_animation_manager.dart';
import 'package:thoughtecho/widgets/app_loading_animation.dart';
import 'package:thoughtecho/widgets/enhanced_ai_loading_dialog.dart';
import 'package:thoughtecho/widgets/media_player_widget.dart';

Widget _buildTestApp(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('EnhancedAILoadingDialog & EnhancedAIProgressDialog 自绘动画验证', () {
    testWidgets('aiThinking 样式使用 AppLoadingStyle.inkWriting 且不使用 Lottie',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          const EnhancedAILoadingDialog(
            message: '正在思考...',
            animationType: LottieAnimationType.aiThinking,
          ),
        ),
      );

      final anim = tester.widget<AppLoadingAnimation>(
        find.byType(AppLoadingAnimation),
      );
      expect(anim.style, AppLoadingStyle.inkWriting);
      expect(find.byType(Lottie), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('modernLoading 样式使用 AppLoadingStyle.bookFlip 且不使用 Lottie',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          const EnhancedAILoadingDialog(
            message: '处理中...',
            animationType: LottieAnimationType.modernLoading,
          ),
        ),
      );

      final anim = tester.widget<AppLoadingAnimation>(
        find.byType(AppLoadingAnimation),
      );
      expect(anim.style, AppLoadingStyle.bookFlip);
      expect(find.byType(Lottie), findsNothing);
    });

    testWidgets('EnhancedAIProgressDialog 使用 AppLoadingAnimation 且不使用 Lottie',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          const EnhancedAIProgressDialog(
            message: '正在导出...',
            progress: 0.5,
          ),
        ),
      );

      final anim = tester.widget<AppLoadingAnimation>(
        find.byType(AppLoadingAnimation),
      );
      expect(anim.style, AppLoadingStyle.bookFlip);
      expect(find.text('50%'), findsOneWidget);
      expect(find.byType(Lottie), findsNothing);
    });
  });

  group('MediaPlayerWidget 视频加载状态验证', () {
    testWidgets('点击视频占位后加载态使用 AppLoadingAnimation(bookFlip) 且不使用 Lottie',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          const MediaPlayerWidget(
            filePath: '/nonexistent/test_video.mp4',
            mediaType: MediaType.video,
          ),
        ),
      );

      expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);

      await tester.tap(find.byType(MediaPlayerWidget));
      await tester.pump();

      final animFinder = find.byType(AppLoadingAnimation);
      expect(animFinder, findsOneWidget);
      expect(
        tester.widget<AppLoadingAnimation>(animFinder).style,
        AppLoadingStyle.bookFlip,
      );
      expect(find.byType(Lottie), findsNothing);

      // 清理 MediaPlayerWidget.dispose 中的 100ms 定时器
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
    });
  });
}
