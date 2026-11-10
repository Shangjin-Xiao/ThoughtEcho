import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mockito/mockito.dart';
import 'package:thoughtecho/services/ai_service.dart';
import 'package:thoughtecho/utils/ai_dialog_helper.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'dart:convert';
import 'dart:async';

class MockAIService extends Mock implements AIService {
  @override
  Future<String> analyzeSource(
    String content, {
    String? existingAuthor,
    String? existingWork,
    bool updateDailyUsage = true,
  }) {
    return super.noSuchMethod(
      Invocation.method(#analyzeSource, [content], {
        #existingAuthor: existingAuthor,
        #existingWork: existingWork,
        #updateDailyUsage: updateDailyUsage,
      }),
      returnValue: Future.value(jsonEncode({'author': 'a', 'work': 'b', 'confidence': 90})),
    );
  }

  @override
  Stream<String> streamPolishText(
    String text, {
    bool updateDailyUsage = true,
  }) {
    return super.noSuchMethod(
      Invocation.method(#streamPolishText, [text], {
        #updateDailyUsage: updateDailyUsage,
      }),
      returnValue: Stream.value('polished'),
    );
  }

  @override
  Stream<String> streamContinueText(
    String text, {
    bool updateDailyUsage = true,
  }) {
    return super.noSuchMethod(
      Invocation.method(#streamContinueText, [text], {
        #updateDailyUsage: updateDailyUsage,
      }),
      returnValue: Stream.value('continued'),
    );
  }

  @override
  Stream<String> streamSummarizeNote(
    Quote note, {
    List<String>? tagNames,
    bool updateDailyUsage = true,
  }) {
    return super.noSuchMethod(
      Invocation.method(#streamSummarizeNote, [note], {
        #tagNames: tagNames,
        #updateDailyUsage: updateDailyUsage,
      }),
      returnValue: Stream.value('summarized'),
    );
  }
}

void main() {
  group('AiDialogHelper Tests', () {
    late MockAIService mockAIService;

    setUp(() {
      Provider.debugCheckInvalidValueType = null;
      mockAIService = MockAIService();
    });

    Widget createWidgetUnderTest(Widget child) {
      return MultiProvider(
        providers: [
          Provider<AIService>.value(value: mockAIService),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(body: child),
        ),
      );
    }

    testWidgets('analyzeSource should show pleaseEnterContent snackbar when content is empty', (WidgetTester tester) async {
      final contentController = TextEditingController();
      final authorController = TextEditingController();
      final workController = TextEditingController();

      await tester.pumpWidget(createWidgetUnderTest(Builder(
        builder: (context) {
          return ElevatedButton(
            onPressed: () {
              AiDialogHelper(context).analyzeSource(contentController, authorController, workController);
            },
            child: const Text('Analyze'),
          );
        }
      )));

      await tester.tap(find.text('Analyze'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('analyzeSource should call aiService and show loading dialog', (WidgetTester tester) async {
      final contentController = TextEditingController(text: 'test content');
      final authorController = TextEditingController(text: 'test author');
      final workController = TextEditingController(text: 'test work');

      final completer = Completer<String>();

      when(mockAIService.analyzeSource(
        'test content',
        existingAuthor: 'test author',
        existingWork: 'test work',
      )).thenAnswer((_) => completer.future);

      await tester.pumpWidget(createWidgetUnderTest(Builder(
        builder: (context) {
          return ElevatedButton(
            onPressed: () {
              AiDialogHelper(context).analyzeSource(contentController, authorController, workController);
            },
            child: const Text('Analyze'),
          );
        }
      )));

      await tester.tap(find.text('Analyze'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(jsonEncode({'author': 'a', 'work': 'b', 'confidence': 90}));
      await tester.pumpAndSettle();
    });

    testWidgets('polishText should show pleaseEnterContent snackbar when content is empty', (WidgetTester tester) async {
      final contentController = TextEditingController();

      await tester.pumpWidget(createWidgetUnderTest(Builder(
        builder: (context) {
          return ElevatedButton(
            onPressed: () {
              AiDialogHelper(context).polishText(contentController);
            },
            child: const Text('Polish'),
          );
        }
      )));

      await tester.tap(find.text('Polish'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('continueText should show pleaseEnterContent snackbar when content is empty', (WidgetTester tester) async {
      final contentController = TextEditingController();

      await tester.pumpWidget(createWidgetUnderTest(Builder(
        builder: (context) {
          return ElevatedButton(
            onPressed: () {
              AiDialogHelper(context).continueText(contentController);
            },
            child: const Text('Continue'),
          );
        }
      )));

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('analyzeContent should show pleaseEnterContent snackbar when quote content is empty', (WidgetTester tester) async {
      final quote = Quote(id: '1', content: '', date: DateTime.now().toIso8601String());

      await tester.pumpWidget(createWidgetUnderTest(Builder(
        builder: (context) {
          return ElevatedButton(
            onPressed: () {
              AiDialogHelper(context).analyzeContent(quote, onFinish: (_) {});
            },
            child: const Text('Analyze Content'),
          );
        }
      )));

      await tester.tap(find.text('Analyze Content'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
    });
  });
}
