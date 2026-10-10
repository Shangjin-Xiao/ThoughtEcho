import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/pages/note_full_editor_page.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/utils/app_scroll_behavior.dart';
import 'package:thoughtecho/widgets/quote_content_widget.dart';
import '../test_harness.dart';

class _FakeSettingsService extends ChangeNotifier implements SettingsService {
  @override
  String get noteCardMediaStyle => 'thumbnail';

  @override
  bool get prioritizeBoldContentInCollapse => false;

  @override
  String? get defaultAuthor => null;

  @override
  String? get defaultSource => null;

  @override
  List<String> get defaultTagIds => const [];

  @override
  bool get autoAttachLocation => false;

  @override
  bool get autoAttachWeather => false;

  @override
  String? get localeCode => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    await TestHarness.initialize();
  });

  group('EditorScrollBehavior tests', () {
    test('EditorScrollBehavior excludes mouse from dragDevices', () {
      const behavior = EditorScrollBehavior();
      expect(behavior.dragDevices, isNot(contains(PointerDeviceKind.mouse)));
      expect(behavior.dragDevices, contains(PointerDeviceKind.touch));
      expect(behavior.dragDevices, contains(PointerDeviceKind.trackpad));
      expect(behavior.dragDevices, contains(PointerDeviceKind.stylus));
      expect(behavior.dragDevices, contains(PointerDeviceKind.invertedStylus));
    });

    testWidgets(
        'Mouse drag with PointerDeviceKind.mouse does NOT scroll when wrapped in EditorScrollBehavior',
        (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          home: Scaffold(
            body: ScrollConfiguration(
              behavior: const EditorScrollBehavior(),
              child: ListView.builder(
                controller: controller,
                itemCount: 50,
                itemExtent: 80.0,
                itemBuilder: (context, index) => ListTile(
                  title: Text('Item $index'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(controller.offset, equals(0.0));

      // Attempt mouse drag gesture
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ListView)),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, -200));
      await gesture.up();
      await tester.pumpAndSettle();

      // Scroll offset must remain 0 because mouse drag is excluded in EditorScrollBehavior
      expect(controller.offset, equals(0.0));
    });

    testWidgets(
        'Touch drag with PointerDeviceKind.touch DOES scroll when wrapped in EditorScrollBehavior',
        (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          home: Scaffold(
            body: ScrollConfiguration(
              behavior: const EditorScrollBehavior(),
              child: ListView.builder(
                controller: controller,
                itemCount: 50,
                itemExtent: 80.0,
                itemBuilder: (context, index) => ListTile(
                  title: Text('Item $index'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(controller.offset, equals(0.0));

      // Touch drag gesture
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ListView)),
        kind: PointerDeviceKind.touch,
      );
      await gesture.moveBy(const Offset(0, -200));
      await gesture.up();
      await tester.pumpAndSettle();

      // Scroll offset must increase for touch drag
      expect(controller.offset, greaterThan(0.0));
    });

    testWidgets(
        'NoteFullEditorPage wraps QuillEditor with EditorScrollBehavior',
        (tester) async {
      final settingsService = _FakeSettingsService();

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: settingsService,
          child: MaterialApp(
            localizationsDelegates: const [
              ...AppLocalizations.localizationsDelegates,
              quill.FlutterQuillLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            scrollBehavior: const AppScrollBehavior(),
            home: const NoteFullEditorPage(
              initialContent: 'Test note editor content',
              skipDefaultMetadataAutofill: true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));

      final quillEditorFinder = find.byType(quill.QuillEditor);
      expect(quillEditorFinder, findsOneWidget);

      final scrollConfigFinder = find.ancestor(
        of: quillEditorFinder,
        matching: find.byType(ScrollConfiguration),
      );
      expect(scrollConfigFinder, findsAtLeastNWidgets(1));

      final ScrollConfiguration scrollConfig =
          tester.widget(scrollConfigFinder.first);
      expect(scrollConfig.behavior, isA<EditorScrollBehavior>());
    });

    testWidgets(
        'QuoteContent in expanded state wraps QuillEditor with EditorScrollBehavior',
        (tester) async {
      final settingsService = _FakeSettingsService();
      final quote = Quote(
        id: 'test_q1',
        content: 'Test content',
        date: DateTime.now().toIso8601String(),
        deltaContent: '[{"insert":"Test expanded content\\n"}]',
        editSource: 'fullscreen',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: settingsService,
          child: MaterialApp(
            localizationsDelegates: const [
              ...AppLocalizations.localizationsDelegates,
              quill.FlutterQuillLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            scrollBehavior: const AppScrollBehavior(),
            home: Scaffold(
              body: QuoteContent(
                quote: quote,
                showFullContent: true,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final quillEditorFinder = find.byType(quill.QuillEditor);
      expect(quillEditorFinder, findsOneWidget);

      final scrollConfigFinder = find.ancestor(
        of: quillEditorFinder,
        matching: find.byType(ScrollConfiguration),
      );
      expect(scrollConfigFinder, findsAtLeastNWidgets(1));

      final ScrollConfiguration scrollConfig =
          tester.widget(scrollConfigFinder.first);
      expect(scrollConfig.behavior, isA<EditorScrollBehavior>());
    });
  });
}
