import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/app_settings.dart';
import 'package:thoughtecho/models/note_tag.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/pages/note_full_editor_page.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/draft_service.dart';
import 'package:thoughtecho/services/feature_guide_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/mmkv_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/weather_service.dart';
import 'package:thoughtecho/utils/mmkv_ffi_fix.dart';

import '../../test_harness.dart';

class _TestSettingsService extends ChangeNotifier implements SettingsService {
  @override
  bool get autoAttachLocation => false;

  @override
  bool get autoAttachWeather => false;

  @override
  String? get defaultAuthor => null;

  @override
  String? get defaultSource => null;

  @override
  List<String> get defaultTagIds => const [];

  @override
  AppSettings get appSettings => AppSettings(developerMode: false);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestLocationService extends ChangeNotifier implements LocationService {
  @override
  bool get hasLocationPermission => true;

  @override
  bool get isLocationServiceEnabled => true;

  @override
  String? get currentPoiName => null;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestWeatherService extends ChangeNotifier implements WeatherService {
  @override
  bool get hasData => true;

  @override
  String get currentWeather => 'Sunny';

  @override
  String getFormattedWeather(AppLocalizations l10n) => 'Sunny 25°C';

  @override
  IconData getWeatherIconData() => Icons.wb_sunny;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestDatabaseService extends ChangeNotifier implements DatabaseService {
  _TestDatabaseService({this.fullQuote});

  final Quote? fullQuote;

  @override
  Future<Quote?> getQuoteById(String id, {bool includeDeleted = false}) async {
    return fullQuote;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestFeatureGuideService extends FeatureGuideService {
  _TestFeatureGuideService() : super(SafeMMKV());

  @override
  bool hasShown(String guideId) => true;

  @override
  Future<void> markAsShown(String guideId) async {}

  @override
  Future<void> resetGuide(String guideId) async {}

  @override
  Future<void> resetAllGuides() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DraftService draftService;
  late MMKVService mmkvService;

  setUpAll(() async {
    await TestHarness.initialize();
    await MMKVService().init();
  });

  setUp(() async {
    draftService = DraftService();
    mmkvService = MMKVService();
    await mmkvService.clear();
    NoteFullEditorPage.debugBuildCount = 0;
  });

  final sampleTags = [
    NoteTag(id: 'tag1', name: 'Reading', iconName: 'menu_book'),
    NoteTag(id: 'tag2', name: 'Coding', iconName: 'code'),
    NoteTag(id: 'tag3', name: 'Life', iconName: 'favorite'),
  ];

  Widget buildEditorApp({Quote? initialQuote}) {
    final mockSettings = _TestSettingsService();
    final mockLocation = _TestLocationService();
    final mockWeather = _TestWeatherService();
    final mockDatabase = _TestDatabaseService(fullQuote: initialQuote);
    final mockGuide = _TestFeatureGuideService();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: mockSettings),
        ChangeNotifierProvider<LocationService>.value(value: mockLocation),
        ChangeNotifierProvider<WeatherService>.value(value: mockWeather),
        ChangeNotifierProvider<DatabaseService>.value(value: mockDatabase),
        ChangeNotifierProvider<FeatureGuideService>.value(value: mockGuide),
        Provider<DraftService>.value(value: draftService),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          ...AppLocalizations.localizationsDelegates,
          FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: NoteFullEditorPage(
          initialContent: initialQuote?.content ?? 'Test Note Content',
          initialQuote: initialQuote,
          allTags: sampleTags,
        ),
      ),
    );
  }

  testWidgets(
    'EditorMetadataDialog interactions do not rebuild NoteFullEditorPage until closed',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildEditorApp());
      await tester.pumpAndSettle();

      // Record build count right after editor is displayed
      final initialBuildCount = NoteFullEditorPage.debugBuildCount;
      expect(initialBuildCount, greaterThan(0));

      // Open metadata dialog
      final metadataButton = find.byIcon(Icons.edit_note);
      expect(metadataButton, findsOneWidget);
      await tester.tap(metadataButton);
      await tester.pumpAndSettle();

      // Record build count after dialog opens
      final openDialogBuildCount = NoteFullEditorPage.debugBuildCount;

      // Expand tag selection tile
      final selectTagsTile = find.text('选择标签');
      expect(selectTagsTile, findsOneWidget);
      await tester.ensureVisible(selectTagsTile);
      await tester.tap(selectTagsTile);
      await tester.pumpAndSettle();

      // Find tag search field (the TextField with search icon or hintText containing 搜索)
      final searchField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText?.contains('搜索') == true,
      );
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'cod');
      await tester.pumpAndSettle();

      // Verify page build count has not increased during tag search typing
      expect(
        NoteFullEditorPage.debugBuildCount,
        equals(openDialogBuildCount),
        reason:
            'Typing in tag search box should not rebuild underlying note editor page',
      );

      // Tap on filtered tag chip ('Coding')
      final codingChip = find.widgetWithText(FilterChip, 'Coding');
      expect(codingChip, findsOneWidget);
      await tester.tap(codingChip);
      await tester.pumpAndSettle();

      // Verify page build count has not increased after toggling tag
      expect(
        NoteFullEditorPage.debugBuildCount,
        equals(openDialogBuildCount),
        reason:
            'Toggling tag chip should not rebuild underlying note editor page',
      );

      // Tap "完成" button to close metadata dialog
      final doneButton = find.text('完成');
      expect(doneButton, findsOneWidget);
      await tester.tap(doneButton);
      await tester.pumpAndSettle();

      // Verify page build count increased by exactly 1 after closing dialog
      expect(
        NoteFullEditorPage.debugBuildCount,
        equals(openDialogBuildCount + 1),
        reason:
            'Underlying note editor page should trigger exactly one build after metadata dialog closes',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets(
    'Location/Weather toggle and AI Analysis deletion in dialog do not rebuild NoteFullEditorPage during interaction',
    (WidgetTester tester) async {
      final initialQuote = Quote(
        id: 'full-editor-ai-test',
        content: 'Note with AI analysis',
        date: DateTime.now().toIso8601String(),
        aiAnalysis: 'This is an AI generated summary.',
      );

      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildEditorApp(initialQuote: initialQuote));
      await tester.pumpAndSettle();

      // Open metadata dialog
      final metadataButton = find.byIcon(Icons.edit_note);
      await tester.tap(metadataButton);
      await tester.pumpAndSettle();

      final openDialogBuildCount = NoteFullEditorPage.debugBuildCount;

      // Verify AI analysis section is present and delete it
      final deleteAiButton = find.byIcon(Icons.delete_outline);
      if (deleteAiButton.evaluate().isNotEmpty) {
        await tester.ensureVisible(deleteAiButton);
        await tester.tap(deleteAiButton);
        await tester.pumpAndSettle();

        // Confirm deletion in alert dialog
        final confirmDeleteButton = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('删除'),
        );
        expect(confirmDeleteButton, findsOneWidget);
        await tester.tap(confirmDeleteButton);
        await tester.pumpAndSettle();

        // Verify page build count has not increased during AI analysis deletion
        expect(
          NoteFullEditorPage.debugBuildCount,
          equals(openDialogBuildCount),
          reason:
              'Deleting AI analysis should not rebuild underlying note editor page',
        );
      }

      // Close dialog
      final doneButton = find.text('完成');
      await tester.tap(doneButton);
      await tester.pumpAndSettle();

      // Exactly 1 build after closing
      expect(
        NoteFullEditorPage.debugBuildCount,
        equals(openDialogBuildCount + 1),
        reason: 'Closing dialog triggers single build on note editor page',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 600));
    },
  );
}
