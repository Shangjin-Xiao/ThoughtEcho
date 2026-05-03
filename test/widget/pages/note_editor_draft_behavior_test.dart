import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/note_category.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/pages/note_full_editor_page.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/draft_service.dart';
import 'package:thoughtecho/services/mmkv_service.dart';
import 'package:thoughtecho/services/settings_service.dart';

import '../../test_setup.dart';

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
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestDatabaseService extends ChangeNotifier implements DatabaseService {
  _TestDatabaseService({required this.fullQuote});

  final Quote fullQuote;
  int getQuoteByIdCallCount = 0;

  @override
  Future<Quote?> getQuoteById(String id, {bool includeDeleted = false}) async {
    getQuoteByIdCallCount += 1;
    return fullQuote;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DraftService draftService;
  late _TestDatabaseService databaseService;
  late MMKVService mmkvService;

  setUpAll(() async {
    await TestSetup.setupWidgetTest();
    await MMKVService().init();
  });

  setUp(() async {
    draftService = DraftService();
    databaseService = _TestDatabaseService(
      fullQuote: Quote(
        id: 'quote-1',
        content: 'Body',
        date: '2026-03-29T00:00:00.000Z',
        aiAnalysis: 'Existing AI analysis',
        editSource: 'fullscreen',
      ),
    );
    mmkvService = MMKVService();
    await mmkvService.clear();
  });

  testWidgets('clearing the editor body removes the recoverable draft', (
    tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(
            value: _TestSettingsService(),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: NoteFullEditorPage(
            initialContent: '',
            initialQuote: Quote(content: '', date: '2026-03-29T00:00:00.000Z'),
            skipDefaultMetadataAutofill: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final editor = find.byType(QuillEditor);
    expect(editor, findsOneWidget);
    final controller = tester.widget<QuillEditor>(editor).controller;

    controller.replaceText(
      0,
      0,
      'Draft body',
      const TextSelection.collapsed(offset: 10),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    final savedDraft = await draftService.getLatestDraft();
    expect(savedDraft, isNotNull);
    expect(savedDraft!['plainText'], 'Draft body');

    controller.clear();
    expect(controller.document.toPlainText().trim(), isEmpty);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(await draftService.getLatestDraft(), isNull);
  });

  testWidgets('back exits cleanly after full quote hydration without edits', (
    tester,
  ) async {
    final partialQuote = Quote(
      id: 'quote-1',
      content: 'Body',
      date: '2026-03-29T00:00:00.000Z',
      editSource: 'fullscreen',
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<DatabaseService>.value(value: databaseService),
          ChangeNotifierProvider<SettingsService>.value(
            value: _TestSettingsService(),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => NoteFullEditorPage(
                          initialContent: partialQuote.content,
                          initialQuote: partialQuote,
                          skipDefaultMetadataAutofill: true,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open editor'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();

    expect(databaseService.getQuoteByIdCallCount, 1);
    expect(find.byType(NoteFullEditorPage), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(NoteFullEditorPage), findsNothing);
    expect(find.text('Open editor'), findsOneWidget);
  });

  testWidgets('metadata tag taps update the sheet immediately', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(
            value: _TestSettingsService(),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: NoteFullEditorPage(
            initialContent: '',
            allTags: [
              NoteCategory(id: 'tag-1', name: 'Mood', iconName: 'label'),
            ],
            skipDefaultMetadataAutofill: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit Metadata'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Metadata'), findsOneWidget);

    final selectTagsTile = find.text('Select Tags', skipOffstage: false);
    await tester.ensureVisible(selectTagsTile);
    await tester.tap(selectTagsTile);
    await tester.pumpAndSettle();

    expect(find.text('0 tags selected'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Mood'));
    await tester.pumpAndSettle();

    expect(find.text('1 tags selected'), findsOneWidget);
    expect(find.text('Mood'), findsNWidgets(2));
  });
}
