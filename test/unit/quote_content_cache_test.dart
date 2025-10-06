import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/widgets/quote_content_widget.dart';

class _StubSettingsService extends SettingsService {
  _StubSettingsService(super.prefs);

  bool _prioritizeBold = false;

  set prioritizeBold(bool value) => _prioritizeBold = value;

  @override
  bool get prioritizeBoldContentInCollapse => _prioritizeBold;

  @override
  Future<void> setPrioritizeBoldContentInCollapse(bool enabled) async {
    _prioritizeBold = enabled;
    notifyListeners();
  }
}

Quote _buildRichQuote({
  required String id,
  required String content,
}) {
  final delta = jsonEncode([
    {'insert': content},
    {'insert': '\n'},
  ]);

  return Quote(
    id: id,
    content: content,
    date: '2024-01-01',
    editSource: 'fullscreen',
    deltaContent: delta,
  );
}

Widget _wrapWithProviders({
  required SettingsService settings,
  required Quote quote,
  required bool showFullContent,
}) {
  return ChangeNotifierProvider<SettingsService>.value(
    value: settings,
    child: MaterialApp(
      home: Scaffold(
        body: QuoteContent(
          key: UniqueKey(),
          quote: quote,
          showFullContent: showFullContent,
        ),
      ),
    ),
  );
}

Future<void> _pumpQuoteContent(
  WidgetTester tester, {
  required SettingsService settings,
  required Quote quote,
  required bool showFullContent,
}) async {
  await tester.pumpWidget(
    _wrapWithProviders(
      settings: settings,
      quote: quote,
      showFullContent: showFullContent,
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, dynamic> _controllerStats() {
  final stats = QuoteContent.debugCacheStats();
  return Map<String, dynamic>.from(
    stats['controller'] as Map<String, dynamic>,
  );
}

Map<String, dynamic> _documentStats() {
  final stats = QuoteContent.debugCacheStats();
  return Map<String, dynamic>.from(
    stats['document'] as Map<String, dynamic>,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late _StubSettingsService settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    settings = _StubSettingsService(prefs);
    QuoteContent.resetCaches();
  });

  tearDown(() {
    QuoteContent.resetCaches();
  });

  testWidgets('reuses controller instances for identical rich text content',
      (tester) async {
    final quote = _buildRichQuote(id: 'q1', content: 'Hello world');

    await _pumpQuoteContent(
      tester,
      settings: settings,
      quote: quote,
      showFullContent: false,
    );

    var controllerStats = _controllerStats();
    expect(controllerStats['createCount'], 1);

    await _pumpQuoteContent(
      tester,
      settings: settings,
      quote: quote,
      showFullContent: false,
    );

    controllerStats = _controllerStats();
    final controllerHitCount = controllerStats['hitCount'] as int;

    final controllerCreateCount = controllerStats['createCount'] as int;

    expect(
      controllerCreateCount,
      1,
      reason: 'controller stats: $controllerStats',
    );
    expect(
      controllerHitCount,
      greaterThan(0),
      reason: 'controller stats: $controllerStats',
    );
  });

  testWidgets('document cache reused across identical delta content',
      (tester) async {
    final quoteA = _buildRichQuote(id: 'docA', content: 'Shared document');
    final quoteB = _buildRichQuote(id: 'docB', content: 'Shared document');

    await _pumpQuoteContent(
      tester,
      settings: settings,
      quote: quoteA,
      showFullContent: false,
    );

    await _pumpQuoteContent(
      tester,
      settings: settings,
      quote: quoteB,
      showFullContent: false,
    );

    final documentStats = _documentStats();
    final controllerStats = _controllerStats();

    expect(controllerStats['createCount'], 2,
        reason: 'controller stats: $controllerStats');
    expect(documentStats['hitCount'], greaterThan(0),
        reason: 'document stats: $documentStats');
    expect(documentStats['cacheSize'], 1,
        reason: 'document stats: $documentStats');
  });

  testWidgets('creates distinct controller variants when view changes',
      (tester) async {
    final quote = _buildRichQuote(id: 'q2', content: 'Variant test');

    await _pumpQuoteContent(
      tester,
      settings: settings,
      quote: quote,
      showFullContent: false,
    );

    await _pumpQuoteContent(
      tester,
      settings: settings,
      quote: quote,
      showFullContent: true,
    );

    final controllerStats = _controllerStats();
    final documentStats = _documentStats();

    expect(controllerStats['createCount'], 2);
    expect(controllerStats['hitCount'], 0);
    expect(documentStats['cacheSize'], 1,
        reason: 'document stats: $documentStats');
  });

  testWidgets('changing content invalidates cached controller', (tester) async {
    final quoteA = _buildRichQuote(id: 'q3', content: 'First content');
    final quoteB = _buildRichQuote(id: 'q3', content: 'Updated content');

    await _pumpQuoteContent(
      tester,
      settings: settings,
      quote: quoteA,
      showFullContent: false,
    );

    await _pumpQuoteContent(
      tester,
      settings: settings,
      quote: quoteB,
      showFullContent: false,
    );

    final controllerStats = _controllerStats();
    final documentStats = _documentStats();

    expect(controllerStats['createCount'], 2);
    expect(controllerStats['hitCount'], 0);
    expect(documentStats['hitCount'], 0,
        reason: 'document stats: $documentStats');
  });
}
