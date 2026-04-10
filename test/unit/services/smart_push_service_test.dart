library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/smart_push_service.dart';

void main() {
  group('SmartPushService Daily Quote Normalization', () {
    test('normalizes homepage quote payload to shared push payload', () {
      final normalized = SmartPushService.normalizeDailyQuoteData({
        'content': '同一句话',
        'author': '作者',
        'source': '出处',
        'type': 'd',
      });

      expect(normalized, isNotNull);
      expect(normalized!['hitokoto'], equals('同一句话'));
      expect(normalized['from_who'], equals('作者'));
      expect(normalized['from'], equals('出处'));
      expect(normalized['type'], equals('d'));
    });

    test('preserves provider metadata for notification quick add', () {
      final normalized = SmartPushService.normalizeDailyQuoteData({
        'content': 'Stay hungry',
        'author': 'Steve Jobs',
        'provider': 'zenquotes',
      });

      expect(normalized, isNotNull);
      expect(normalized!['provider'], equals('zenquotes'));
    });

    test('returns null when quote content is empty', () {
      final normalized = SmartPushService.normalizeDailyQuoteData({
        'content': '   ',
        'author': '作者',
      });

      expect(normalized, isNull);
    });
  });

  group('SmartPushService notification helpers', () {
    test('buildNotificationPayload includes route target for note list', () {
      final payload = SmartPushService.buildNotificationPayload(
        noteId: '12345678-1234-1234-1234-1234567890ab',
        contentType: 'monthAgoToday',
        routeTarget: 'noteList',
      );

      expect(
        payload,
        equals(
          'contentType:monthAgoToday|noteId:12345678-1234-1234-1234-1234567890ab|routeTarget:noteList',
        ),
      );
    });

    test('notification summary is removed even for historical notes', () {
      final note = Quote(
        id: '12345678-1234-1234-1234-1234567890ab',
        content: '春天会再来。',
        date: DateTime(2025, 10, 15, 9, 0).toIso8601String(),
      );

      expect(SmartPushService.notificationSummaryForTest(note), isNull);
    });

    testWidgets('replaces the full navigation stack for notification routes', (
      WidgetTester tester,
    ) async {
      final navigatorKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const _TestPage(title: 'root'),
        ),
      );

      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const _TestPage(title: 'middle'),
        ),
      );
      await tester.pumpAndSettle();

      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const _TestPage(title: 'top'),
        ),
      );
      await tester.pumpAndSettle();

      SmartPushService.replaceAppStackForNotification(
        navigator: navigatorKey.currentState!,
        route: MaterialPageRoute<void>(
          builder: (_) => const _TestPage(title: 'target'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('target'), findsOneWidget);
      expect(find.text('root'), findsNothing);
      expect(find.text('middle'), findsNothing);
      expect(find.text('top'), findsNothing);
      expect(navigatorKey.currentState!.canPop(), isFalse);
    });
  });
}

class _TestPage extends StatelessWidget {
  final String title;

  const _TestPage({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(title),
      ),
    );
  }
}
