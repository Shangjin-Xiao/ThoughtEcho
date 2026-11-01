import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/app_settings.dart';
import 'package:thoughtecho/models/local_ai_settings.dart';
import 'package:thoughtecho/models/note_tag.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/feature_guide_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/weather_service.dart';
import 'package:thoughtecho/widgets/add_note_dialog.dart';
import 'package:thoughtecho/widgets/add_note_dialog_parts.dart';

Position _testPosition() => Position(
      latitude: 10.0,
      longitude: 20.0,
      timestamp: DateTime(2026, 1, 1),
      accuracy: 0.0,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
    );

class _MockSettingsService extends ChangeNotifier implements SettingsService {
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
  bool get enableFirstOpenScrollPerfMonitor => false;

  @override
  LocalAISettings get localAISettings => const LocalAISettings();

  @override
  bool get addNoteDialogDeferAutoMetadata => false;

  @override
  bool get addNoteDialogAutoFocus => false;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockLocationService extends ChangeNotifier implements LocationService {
  Position? _position = _testPosition();
  String _formattedLocation = '示例省·示例市';
  String? _poiName;

  @override
  bool get hasLocationPermission => true;

  @override
  bool get isLocationServiceEnabled => true;

  @override
  Position? get currentPosition => _position;

  @override
  String? get currentPoiName => _poiName;

  @override
  Future<Position?> getCurrentLocation({
    bool highAccuracy = false,
    skipPermissionRequest = false,
  }) async {
    _position = _testPosition();
    return _position;
  }

  @override
  String? currentLocaleCode;

  @override
  void setCoordinates(double lat, double lng, {String? address}) {
    _position = Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime(2026, 1, 1),
      accuracy: 0.0,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
    );
  }

  @override
  Future<void> getAddressFromLatLng() async {
    _formattedLocation = '示例省·示例市2';
  }

  @override
  String getFormattedLocation() => _formattedLocation;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockWeatherService extends ChangeNotifier implements WeatherService {
  final String _weather = '晴';
  final String _temperature = '22°C';
  final bool _hasData = true;

  @override
  bool get hasData => _hasData;

  @override
  String get currentWeather => _weather;

  @override
  String get temperature => _temperature;

  @override
  String getFormattedWeather(AppLocalizations l10n) => ' ';

  @override
  IconData getWeatherIconData() => Icons.wb_sunny;

  @override
  Future<void> getWeatherData(
    double latitude,
    double longitude, {
    bool forceRefresh = false,
    Duration? timeout,
  }) async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockFeatureGuideService extends ChangeNotifier
    implements FeatureGuideService {
  @override
  bool hasShown(String guideId) => true;

  @override
  bool hasShownAll(List<String> guideIds) => true;

  @override
  bool hasShownAny(List<String> guideIds) => true;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestDatabaseService extends DatabaseService {
  _TestDatabaseService() : super.forTesting();

  final Map<String, NoteTag> _tags = {
    'default_hitokoto':
        NoteTag(id: 'default_hitokoto', name: '每日一言', iconName: '💭'),
    'default_anime': NoteTag(id: 'default_anime', name: '动画', iconName: '🎬'),
    'custom_tag_1': NoteTag(id: 'custom_tag_1', name: '自定义标签', iconName: '🏷️'),
  };

  @override
  bool get isInitialized => true;

  @override
  Future<List<NoteTag>> getTags() async => _tags.values.toList();

  @override
  Future<NoteTag?> getTagById(String id) async => _tags[id];

  @override
  Future<void> addTagWithId(String id, String name, {String? iconName}) async {
    _tags[id] = NoteTag(
      id: id,
      name: name,
      isDefault: DatabaseService.systemTagIds.contains(id),
      iconName: iconName ?? '',
    );
  }

  @override
  Future<Quote?> getQuoteById(String id, {bool includeDeleted = false}) async =>
      null;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _buildTestApp({
  required void Function(Quote) onSave,
  Map<String, dynamic>? hitokotoData,
  String? prefilledContent,
  String? prefilledAuthor,
  String? prefilledWork,
  List<String>? prefilledTagIds,
  List<NoteTag> availableTags = const [],
}) {
  final content = prefilledContent ??
      (hitokotoData != null ? (hitokotoData['hitokoto'] as String?) : null);
  final author = prefilledAuthor ??
      (hitokotoData != null ? (hitokotoData['from_who'] as String?) : null);
  final work = prefilledWork ??
      (hitokotoData != null ? (hitokotoData['from'] as String?) : null);

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsService>.value(
        value: _MockSettingsService(),
      ),
      ChangeNotifierProvider<LocationService>.value(
        value: _MockLocationService(),
      ),
      ChangeNotifierProvider<WeatherService>.value(
        value: _MockWeatherService(),
      ),
      ChangeNotifierProvider<DatabaseService>.value(
        value: _TestDatabaseService(),
      ),
      ChangeNotifierProvider<FeatureGuideService>.value(
        value: _MockFeatureGuideService(),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  child: AddNoteDialog(
                    tags: availableTags,
                    hitokotoData: hitokotoData,
                    prefilledContent: content,
                    prefilledAuthor: author,
                    prefilledWork: work,
                    prefilledTagIds: prefilledTagIds,
                    onSave: onSave,
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'double click daily quote hitokotoData adds tags and centers SelectedTagsDisplay and saves with tags',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    Quote? savedQuote;
    await tester.pumpWidget(
      _buildTestApp(
        hitokotoData: const {
          'hitokoto': '一言测试内容',
          'from_who': '作者',
          'from': '作品',
          'type': 'a',
          'provider': 'hitokoto',
        },
        onSave: (quote) {
          savedQuote = quote;
        },
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 1. Tags should be automatically populated and visible in SelectedTagsDisplay
    expect(find.byType(SelectedTagsDisplay), findsOneWidget);
    expect(find.text('每日一言'), findsOneWidget);
    expect(find.text('动画'), findsOneWidget);

    // 2. SelectedTagsDisplay should be centered horizontally within AddNoteDialog
    final dialogCenter = tester.getCenter(find.byType(AddNoteDialog));
    final selectedTagsCenter =
        tester.getCenter(find.byType(SelectedTagsDisplay));
    expect(
      selectedTagsCenter.dx,
      closeTo(dialogCenter.dx, 1.0),
      reason: 'SelectedTagsDisplay should be horizontally centered',
    );

    // 3. Save quote and verify tagIds are properly passed
    await tester.tap(find.byKey(const ValueKey('add_note_save_button')));
    await tester.pumpAndSettle();

    expect(savedQuote, isNotNull);
    expect(
      savedQuote!.tagIds,
      containsAll(['default_hitokoto', 'default_anime']),
    );
  });

  testWidgets(
      'removing an auto-populated hitokoto tag updates display and excludes tag when saving',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    Quote? savedQuote;
    await tester.pumpWidget(
      _buildTestApp(
        hitokotoData: const {
          'hitokoto': '一言测试内容',
          'from_who': '作者',
          'from': '作品',
          'type': 'a',
          'provider': 'hitokoto',
        },
        onSave: (quote) {
          savedQuote = quote;
        },
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('每日一言'), findsOneWidget);
    expect(find.text('动画'), findsOneWidget);

    // Delete '每日一言' tag by tapping its cancel icon within SelectedTagsDisplay
    final hitokotoChip = find.ancestor(
      of: find.text('每日一言'),
      matching: find.byType(Chip),
    );
    expect(hitokotoChip, findsOneWidget);

    final cancelIcon = find.descendant(
      of: hitokotoChip,
      matching: find.byIcon(Icons.cancel),
    );
    expect(cancelIcon, findsOneWidget);

    await tester.tap(cancelIcon);
    await tester.pumpAndSettle();

    // '每日一言' tag should be gone, '动画' should remain
    expect(find.text('每日一言'), findsNothing);
    expect(find.text('动画'), findsOneWidget);

    // Save and verify tagIds
    await tester.tap(find.byKey(const ValueKey('add_note_save_button')));
    await tester.pumpAndSettle();

    expect(savedQuote, isNotNull);
    expect(savedQuote!.tagIds, equals(['default_anime']));
  });

  testWidgets(
      'user can expand TagSelectionSection and manually select additional tag alongside hitokoto tags',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    Quote? savedQuote;
    await tester.pumpWidget(
      _buildTestApp(
        hitokotoData: const {
          'hitokoto': '一言测试内容',
          'from_who': '作者',
          'from': '作品',
          'type': 'a',
          'provider': 'hitokoto',
        },
        onSave: (quote) {
          savedQuote = quote;
        },
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('每日一言'), findsOneWidget);
    expect(find.text('动画'), findsOneWidget);

    // Expand TagSelectionSection ExpansionTile
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();

    // Find custom_tag_1 in the list and tap it
    expect(find.text('自定义标签'), findsOneWidget);
    await tester.tap(find.text('自定义标签'));
    await tester.pumpAndSettle();

    // Verify all 3 tags are now present in SelectedTagsDisplay
    expect(
      find.descendant(
        of: find.byType(SelectedTagsDisplay),
        matching: find.text('自定义标签'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(SelectedTagsDisplay),
        matching: find.text('每日一言'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(SelectedTagsDisplay),
        matching: find.text('动画'),
      ),
      findsOneWidget,
    );

    // Save and verify all 3 tags are saved
    await tester.tap(find.byKey(const ValueKey('add_note_save_button')));
    await tester.pumpAndSettle();

    expect(savedQuote, isNotNull);
    expect(
      savedQuote!.tagIds,
      containsAll(['default_hitokoto', 'default_anime', 'custom_tag_1']),
    );
  });
}
