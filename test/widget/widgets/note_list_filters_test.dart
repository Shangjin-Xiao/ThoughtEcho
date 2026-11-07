library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/controllers/search_controller.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/app_settings.dart';
import 'package:thoughtecho/models/local_ai_settings.dart';
import 'package:thoughtecho/models/note_tag.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/widgets/note_list_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AnimatedFilterChip Unit & Widget Tests', () {
    testWidgets(
      'renders child wrapped in Opacity and Transform during entry animation',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: AnimatedFilterChip(
                child: Text('Test Chip'),
              ),
            ),
          ),
        );

        // Initially at t=0ms, value is 0.0, Opacity and Transform wrappers exist under AnimatedFilterChip.
        expect(find.text('Test Chip'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(Opacity),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(Transform),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(RepaintBoundary),
          ),
          findsNWidgets(2),
        );
        // Verify inner RepaintBoundary inside Opacity isolates animChild
        expect(
          find.descendant(
            of: find.byType(Opacity),
            matching: find.byType(RepaintBoundary),
          ),
          findsOneWidget,
        );

        // Pump mid-way through 250ms animation (e.g. 100ms)
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(Opacity),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(Transform),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(RepaintBoundary),
          ),
          findsNWidgets(2),
        );
        expect(
          find.descendant(
            of: find.byType(Opacity),
            matching: find.byType(RepaintBoundary),
          ),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'prunes Opacity and Transform layers after animation completes (value >= 1.0)',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: AnimatedFilterChip(
                child: Text('Test Chip'),
              ),
            ),
          ),
        );

        // Advance past the 250ms animation duration
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Test Chip'), findsOneWidget);
        // Verify Opacity, Transform and RepaintBoundary are no longer wrapping the child under AnimatedFilterChip
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(Opacity),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(Transform),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(RepaintBoundary),
          ),
          findsNothing,
        );

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'verifies RenderRepaintBoundary render objects and progression values during entry animation',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: AnimatedFilterChip(
                child: Text('Render Boundary Chip'),
              ),
            ),
          ),
        );

        // At t=0ms
        final opacityWidget0 = tester.widget<Opacity>(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(Opacity),
          ),
        );
        expect(opacityWidget0.opacity, 0.0);

        final transformWidget0 = tester.widget<Transform>(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(Transform),
          ),
        );
        expect(
          transformWidget0.transform.entry(0, 0),
          closeTo(0.8, 0.001),
        );

        final boundaries0 = tester.renderObjectList<RenderRepaintBoundary>(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(RepaintBoundary),
          ),
        );
        expect(boundaries0.length, 2);
        for (final boundary in boundaries0) {
          expect(boundary.isRepaintBoundary, isTrue);
        }

        // Pump 100ms
        await tester.pump(const Duration(milliseconds: 100));
        final opacityWidget100 = tester.widget<Opacity>(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(Opacity),
          ),
        );
        expect(opacityWidget100.opacity, greaterThan(0.0));
        expect(opacityWidget100.opacity, lessThan(1.0));

        final transformWidget100 = tester.widget<Transform>(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(Transform),
          ),
        );
        expect(
          transformWidget100.transform.entry(0, 0),
          greaterThan(0.8),
        );
        expect(
          transformWidget100.transform.entry(0, 0),
          lessThan(1.0),
        );

        final boundaries100 = tester.renderObjectList<RenderRepaintBoundary>(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(RepaintBoundary),
          ),
        );
        expect(boundaries100.length, 2);
        for (final boundary in boundaries100) {
          expect(boundary.isRepaintBoundary, isTrue);
        }

        // Complete animation past 250ms
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(RepaintBoundary),
          ),
          findsNothing,
        );

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'updates child content dynamically during ongoing tween animation',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: AnimatedFilterChip(
                child: Text('Version 1'),
              ),
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Version 1'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(RepaintBoundary),
          ),
          findsNWidgets(2),
        );

        // Rebuild with updated child while animation is midway
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: AnimatedFilterChip(
                child: Text('Version 2'),
              ),
            ),
          ),
        );
        expect(find.text('Version 2'), findsOneWidget);
        expect(find.text('Version 1'), findsNothing);
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(RepaintBoundary),
          ),
          findsNWidgets(2),
        );

        // Complete animation
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('Version 2'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(RepaintBoundary),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(Opacity),
          ),
          findsNothing,
        );

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'updates child content immediately after animation has completed without adding RepaintBoundary',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: AnimatedFilterChip(
                child: Text('Initial Version'),
              ),
            ),
          ),
        );

        // Advance past completion
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Initial Version'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(RepaintBoundary),
          ),
          findsNothing,
        );

        // Rebuild with new child after animation finished
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: AnimatedFilterChip(
                child: Text('Settled Version'),
              ),
            ),
          ),
        );

        expect(find.text('Settled Version'), findsOneWidget);
        expect(find.text('Initial Version'), findsNothing);
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(RepaintBoundary),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(Opacity),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(Transform),
          ),
          findsNothing,
        );

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'maintains local isolation between multiple chips animating at different times',
      (tester) async {
        Widget buildTwoChips({required bool showSecond}) {
          return MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  const AnimatedFilterChip(
                    key: ValueKey('chip_1'),
                    child: Text('Chip 1'),
                  ),
                  if (showSecond)
                    const AnimatedFilterChip(
                      key: ValueKey('chip_2'),
                      child: Text('Chip 2'),
                    ),
                ],
              ),
            ),
          );
        }

        // Render first chip only
        await tester.pumpWidget(buildTwoChips(showSecond: false));
        // Settle first chip animation
        await tester.pump(const Duration(milliseconds: 300));

        final chip1Finder = find.byKey(const ValueKey('chip_1'));
        expect(
          find.descendant(
            of: chip1Finder,
            matching: find.byType(RepaintBoundary),
          ),
          findsNothing,
        );

        // Now introduce second chip
        await tester.pumpWidget(buildTwoChips(showSecond: true));
        await tester.pump(); // t=0ms for chip_2

        final chip2Finder = find.byKey(const ValueKey('chip_2'));
        // Chip 1 remains settled with 0 RepaintBoundary layers
        expect(
          find.descendant(
            of: chip1Finder,
            matching: find.byType(RepaintBoundary),
          ),
          findsNothing,
        );
        // Chip 2 has 2 RepaintBoundary layers for its entry animation
        expect(
          find.descendant(
            of: chip2Finder,
            matching: find.byType(RepaintBoundary),
          ),
          findsNWidgets(2),
        );

        // Advance 100ms
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          find.descendant(
            of: chip1Finder,
            matching: find.byType(RepaintBoundary),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: chip2Finder,
            matching: find.byType(RepaintBoundary),
          ),
          findsNWidgets(2),
        );

        // Advance past chip 2 completion
        await tester.pump(const Duration(milliseconds: 250));
        expect(
          find.descendant(
            of: chip1Finder,
            matching: find.byType(RepaintBoundary),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: chip2Finder,
            matching: find.byType(RepaintBoundary),
          ),
          findsNothing,
        );

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });

  group('NoteListFiltersExtension and AnimatedFilterChip Integration', () {
    testWidgets(
      'renders filter chips with keys and correct localized labels',
      (tester) async {
        final databaseService = _FakeDatabaseService();
        final settingsService = _FakeSettingsService();

        await tester.pumpWidget(
          _FilterTestApp(
            databaseService: databaseService,
            settingsService: settingsService,
            tags: [
              NoteTag(id: 'tag-1', name: '工作', iconName: '💼'),
            ],
            selectedTagIds: const ['tag-1'],
            selectedWeathers: const ['clear', 'other_weather'],
            selectedDayPeriods: const ['morning'],
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Verify keys
        expect(find.byKey(const ValueKey('tag_tag-1')), findsOneWidget);
        expect(find.byKey(const ValueKey('weather_cat_sunny')), findsOneWidget);
        expect(find.byKey(const ValueKey('weather_other_weather')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('period_morning')), findsOneWidget);

        // Verify AnimatedFilterChip widgets (1 tag + 1 weather cat + 1 other weather + 1 period = 4)
        expect(find.byType(AnimatedFilterChip), findsNWidgets(4));

        // Verify layer pruning after animation completes
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(Opacity),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(Transform),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(RepaintBoundary),
          ),
          findsNothing,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'triggers callbacks correctly on chip deletion and clear all',
      (tester) async {
        final databaseService = _FakeDatabaseService();
        final settingsService = _FakeSettingsService();

        List<String>? updatedTags;
        List<String>? updatedWeathers;
        List<String>? updatedDayPeriods;

        await tester.pumpWidget(
          _FilterTestApp(
            databaseService: databaseService,
            settingsService: settingsService,
            tags: [
              NoteTag(id: 'tag-1', name: '工作', iconName: '💼'),
            ],
            selectedTagIds: const ['tag-1'],
            selectedWeathers: const ['clear'],
            selectedDayPeriods: const ['morning'],
            onTagSelectionChanged: (tags) => updatedTags = tags,
            onFilterChanged: (weathers, dayPeriods) {
              updatedWeathers = weathers;
              updatedDayPeriods = dayPeriods;
            },
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Tap delete on tag-1
        final tagCloseButton = find.descendant(
          of: find.byKey(const ValueKey('tag_tag-1')),
          matching: find.byIcon(Icons.close),
        );
        await tester.tap(tagCloseButton);
        await tester.pump();

        expect(updatedTags, isEmpty);

        // Tap delete on sunny weather chip
        final weatherCloseButton = find.descendant(
          of: find.byKey(const ValueKey('weather_cat_sunny')),
          matching: find.byIcon(Icons.close),
        );
        await tester.tap(weatherCloseButton);
        await tester.pump();

        expect(updatedWeathers, isEmpty);
        expect(updatedDayPeriods, ['morning']);

        // Tap clear all button (the last Icons.close button in filter bar)
        updatedTags = null;
        updatedWeathers = null;
        updatedDayPeriods = null;

        final clearAllButton = find.byIcon(Icons.close).last;
        await tester.tap(clearAllButton);
        await tester.pump();

        expect(updatedTags, isEmpty);
        expect(updatedWeathers, isEmpty);
        expect(updatedDayPeriods, isEmpty);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'handles rapid addition and removal of tags with ValueKey element reuse',
      (tester) async {
        final databaseService = _FakeDatabaseService();
        final settingsService = _FakeSettingsService();

        Widget buildApp(List<String> tags) {
          return _FilterTestApp(
            databaseService: databaseService,
            settingsService: settingsService,
            tags: [
              NoteTag(id: 'tag-1', name: 'Tag 1', iconName: '🏷️'),
              NoteTag(id: 'tag-2', name: 'Tag 2', iconName: '🏷️'),
            ],
            selectedTagIds: tags,
            selectedWeathers: const [],
            selectedDayPeriods: const [],
          );
        }

        await tester.pumpWidget(buildApp(['tag-1', 'tag-2']));
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byKey(const ValueKey('tag_tag-1')), findsOneWidget);
        expect(find.byKey(const ValueKey('tag_tag-2')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(RepaintBoundary),
          ),
          findsNWidgets(4),
        );

        // Rapidly remove tag-1 before animation finishes
        await tester.pumpWidget(buildApp(['tag-2']));
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byKey(const ValueKey('tag_tag-1')), findsNothing);
        expect(find.byKey(const ValueKey('tag_tag-2')), findsOneWidget);

        // Advance past animation
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const ValueKey('tag_tag-2')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(Opacity),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(RepaintBoundary),
          ),
          findsNothing,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'animates filter bar expansion and collapse using SizeTransition with RepaintBoundary layer isolation',
      (tester) async {
        final databaseService = _FakeDatabaseService();
        final settingsService = _FakeSettingsService();

        Widget buildApp(List<String> selectedTags) {
          return _FilterTestApp(
            databaseService: databaseService,
            settingsService: settingsService,
            tags: [
              NoteTag(id: 'tag-1', name: '工作', iconName: '💼'),
            ],
            selectedTagIds: selectedTags,
            selectedWeathers: const [],
            selectedDayPeriods: const [],
          );
        }

        // Start with no filters selected
        await tester.pumpWidget(buildApp([]));
        await tester.pump();

        // SizeTransition should exist with sizeFactor 0.0 or SizedBox.shrink when no filters
        expect(find.byType(SizeTransition), findsNothing);

        // Add a tag filter -> expand filter display
        await tester.pumpWidget(buildApp(['tag-1']));
        await tester.pump(); // Start animation (t=0ms)

        expect(find.byType(SizeTransition), findsOneWidget);
        expect(
          find.ancestor(
            of: find.byType(SizeTransition),
            matching: find.byType(RepaintBoundary),
          ),
          findsAtLeastNWidgets(1),
        );

        final SizeTransition sizeTransition1 =
            tester.widget(find.byType(SizeTransition));
        expect(sizeTransition1.sizeFactor.value, 0.0);

        // Advance 150ms -> sizeFactor ~ 0.5
        await tester.pump(const Duration(milliseconds: 150));
        final SizeTransition sizeTransition2 =
            tester.widget(find.byType(SizeTransition));
        expect(sizeTransition2.sizeFactor.value, greaterThan(0.0));
        expect(sizeTransition2.sizeFactor.value, lessThan(1.0));

        // Advance past 300ms -> sizeFactor = 1.0
        await tester.pump(const Duration(milliseconds: 200));
        final SizeTransition sizeTransition3 =
            tester.widget(find.byType(SizeTransition));
        expect(sizeTransition3.sizeFactor.value, 1.0);

        // Remove tag filter -> reverse animation collapse
        await tester.pumpWidget(buildApp([]));
        await tester.pump(); // t=0ms of reverse

        final SizeTransition sizeTransition4 =
            tester.widget(find.byType(SizeTransition));
        expect(sizeTransition4.sizeFactor.value, 1.0);

        // Mid-way through collapse (150ms)
        await tester.pump(const Duration(milliseconds: 150));
        final SizeTransition sizeTransition5 =
            tester.widget(find.byType(SizeTransition));
        expect(sizeTransition5.sizeFactor.value, lessThan(1.0));
        expect(sizeTransition5.sizeFactor.value, greaterThan(0.0));

        // Finish collapse animation (past 300ms)
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(SizeTransition), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'verifies RepaintBoundary layer isolation on Expanded note list area',
      (tester) async {
        final databaseService = _FakeDatabaseService();
        final settingsService = _FakeSettingsService();

        await tester.pumpWidget(
          _FilterTestApp(
            databaseService: databaseService,
            settingsService: settingsService,
            tags: [
              NoteTag(id: 'tag-1', name: '工作', iconName: '💼'),
            ],
            selectedTagIds: const ['tag-1'],
            selectedWeathers: const [],
            selectedDayPeriods: const [],
          ),
        );

        await tester.pumpAndSettle();

        // Find RepaintBoundary wrapping the note list animation layer
        final listOpacityFinder = find.byType(AnimatedOpacity);
        expect(listOpacityFinder, findsAtLeastNWidgets(1));

        final repaintBoundaryUnderList = find.ancestor(
          of: listOpacityFinder,
          matching: find.byType(RepaintBoundary),
        );
        expect(repaintBoundaryUnderList, findsAtLeastNWidgets(1));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'handles deletion of unclassified weather chips and day period chips',
      (tester) async {
        final databaseService = _FakeDatabaseService();
        final settingsService = _FakeSettingsService();

        List<String>? updatedWeathers;
        List<String>? updatedDayPeriods;

        await tester.pumpWidget(
          _FilterTestApp(
            databaseService: databaseService,
            settingsService: settingsService,
            tags: const [],
            selectedTagIds: const [],
            selectedWeathers: const ['other_fog', 'clear'],
            selectedDayPeriods: const ['morning', 'night'],
            onFilterChanged: (weathers, dayPeriods) {
              updatedWeathers = weathers;
              updatedDayPeriods = dayPeriods;
            },
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byKey(const ValueKey('weather_other_fog')), findsOneWidget);
        expect(find.byKey(const ValueKey('weather_cat_sunny')), findsOneWidget);
        expect(find.byKey(const ValueKey('period_morning')), findsOneWidget);
        expect(find.byKey(const ValueKey('period_night')), findsOneWidget);

        // Delete unclassified weather chip
        final otherFogCloseButton = find.descendant(
          of: find.byKey(const ValueKey('weather_other_fog')),
          matching: find.byIcon(Icons.close),
        );
        await tester.tap(otherFogCloseButton);
        await tester.pump();

        expect(updatedWeathers, ['clear']);
        expect(updatedDayPeriods, ['morning', 'night']);

        // Delete day period chip
        updatedWeathers = null;
        updatedDayPeriods = null;

        final nightCloseButton = find.descendant(
          of: find.byKey(const ValueKey('period_night')),
          matching: find.byIcon(Icons.close),
        );
        await tester.tap(nightCloseButton);
        await tester.pump();

        expect(updatedWeathers, ['clear']);
        expect(updatedDayPeriods, ['morning']);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'deletes all weather keys mapped to a single weather category when category chip is removed',
      (tester) async {
        final databaseService = _FakeDatabaseService();
        final settingsService = _FakeSettingsService();

        List<String>? updatedWeathers;
        List<String>? updatedDayPeriods;

        await tester.pumpWidget(
          _FilterTestApp(
            databaseService: databaseService,
            settingsService: settingsService,
            tags: const [],
            selectedTagIds: const [],
            selectedWeathers: const ['rain', 'drizzle', 'thunderstorm'],
            selectedDayPeriods: const ['afternoon'],
            onFilterChanged: (weathers, dayPeriods) {
              updatedWeathers = weathers;
              updatedDayPeriods = dayPeriods;
            },
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // All 3 rainy keys aggregate into single weather_cat_rainy chip
        expect(find.byKey(const ValueKey('weather_cat_rainy')), findsOneWidget);
        expect(find.byType(AnimatedFilterChip), findsNWidgets(2));

        final rainyCloseButton = find.descendant(
          of: find.byKey(const ValueKey('weather_cat_rainy')),
          matching: find.byIcon(Icons.close),
        );
        await tester.tap(rainyCloseButton);
        await tester.pump();

        // All weather keys belonging to category 'rainy' should be removed
        expect(updatedWeathers, isEmpty);
        expect(updatedDayPeriods, ['afternoon']);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'renders unknown tag fallback label and handles deletion when tag is missing from effective tags',
      (tester) async {
        final databaseService = _FakeDatabaseService();
        final settingsService = _FakeSettingsService();

        List<String>? updatedTags;

        await tester.pumpWidget(
          _FilterTestApp(
            databaseService: databaseService,
            settingsService: settingsService,
            tags: [
              NoteTag(id: 'known-tag', name: '工作', iconName: '💼'),
            ],
            selectedTagIds: const ['known-tag', 'unregistered-tag'],
            selectedWeathers: const [],
            selectedDayPeriods: const [],
            onTagSelectionChanged: (tags) => updatedTags = tags,
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byKey(const ValueKey('tag_known-tag')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('tag_unregistered-tag')),
          findsOneWidget,
        );
        expect(find.text('未知标签'), findsOneWidget);

        final unknownCloseButton = find.descendant(
          of: find.byKey(const ValueKey('tag_unregistered-tag')),
          matching: find.byIcon(Icons.close),
        );
        await tester.tap(unknownCloseButton);
        await tester.pump();

        expect(updatedTags, ['known-tag']);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'renders tag with non-emoji icon correctly',
      (tester) async {
        final databaseService = _FakeDatabaseService();
        final settingsService = _FakeSettingsService();

        await tester.pumpWidget(
          _FilterTestApp(
            databaseService: databaseService,
            settingsService: settingsService,
            tags: [
              NoteTag(id: 'tag-work', name: '工作任务', iconName: 'work'),
            ],
            selectedTagIds: const ['tag-work'],
            selectedWeathers: const [],
            selectedDayPeriods: const [],
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byKey(const ValueKey('tag_tag-work')), findsOneWidget);
        expect(find.text('工作任务'), findsOneWidget);
        // Verify IconData Icons.work is rendered rather than emoji text
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('tag_tag-work')),
            matching: find.byIcon(Icons.work),
          ),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'preserves cached child in _FilterDisplayContainer during reverse collapse animation to prevent flicker',
      (tester) async {
        final databaseService = _FakeDatabaseService();
        final settingsService = _FakeSettingsService();

        Widget buildApp(List<String> tags) {
          return _FilterTestApp(
            databaseService: databaseService,
            settingsService: settingsService,
            tags: [
              NoteTag(id: 'tag-1', name: '持久标签', iconName: '🏷️'),
            ],
            selectedTagIds: tags,
            selectedWeathers: const [],
            selectedDayPeriods: const [],
          );
        }

        // Initially open with tag-1
        await tester.pumpWidget(buildApp(['tag-1']));
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(SizeTransition), findsOneWidget);
        expect(find.text('持久标签'), findsOneWidget);

        // Remove all tags -> triggers reverse collapse animation
        await tester.pumpWidget(buildApp([]));
        await tester.pump(); // t=0ms of reverse

        final SizeTransition stStart =
            tester.widget(find.byType(SizeTransition));
        expect(stStart.sizeFactor.value, 1.0);
        // Cached child still preserves chip content
        expect(find.text('持久标签'), findsOneWidget);

        // Advance 150ms mid-way through collapse
        await tester.pump(const Duration(milliseconds: 150));
        final SizeTransition stMid = tester.widget(find.byType(SizeTransition));
        expect(stMid.sizeFactor.value, greaterThan(0.0));
        expect(stMid.sizeFactor.value, lessThan(1.0));
        // Chip remains visible during collapse
        expect(find.text('持久标签'), findsOneWidget);

        // Advance past collapse (200ms more -> 350ms total)
        await tester.pump(const Duration(milliseconds: 200));
        // SizeTransition disappears (renders SizedBox.shrink())
        expect(find.byType(SizeTransition), findsNothing);
        expect(find.text('持久标签'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'handles rapid toggling of filter bar expansion and collapse smoothly without error',
      (tester) async {
        final databaseService = _FakeDatabaseService();
        final settingsService = _FakeSettingsService();

        Widget buildApp(List<String> tags) {
          return _FilterTestApp(
            databaseService: databaseService,
            settingsService: settingsService,
            tags: [
              NoteTag(id: 'tag-1', name: '快速切换', iconName: '⚡'),
            ],
            selectedTagIds: tags,
            selectedWeathers: const [],
            selectedDayPeriods: const [],
          );
        }

        // Start empty
        await tester.pumpWidget(buildApp([]));
        await tester.pump();
        expect(find.byType(SizeTransition), findsNothing);

        // Rapidly expand
        await tester.pumpWidget(buildApp(['tag-1']));
        await tester.pump(const Duration(milliseconds: 150));
        expect(find.byType(SizeTransition), findsOneWidget);

        // Rapidly reverse collapse before expansion completes
        await tester.pumpWidget(buildApp([]));
        await tester.pump(const Duration(milliseconds: 30));
        expect(find.byType(SizeTransition), findsOneWidget);

        // Re-expand before collapse finishes
        await tester.pumpWidget(buildApp(['tag-1']));
        await tester.pump(const Duration(milliseconds: 350));

        // Settles cleanly at fully expanded
        final SizeTransition stFinal =
            tester.widget(find.byType(SizeTransition));
        expect(stFinal.sizeFactor.value, 1.0);
        expect(find.text('快速切换'), findsOneWidget);
        // All temporary layers are pruned after settling
        expect(
          find.descendant(
            of: find.byType(AnimatedFilterChip),
            matching: find.byType(RepaintBoundary),
          ),
          findsNothing,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      },
    );
  });
}

class _FilterTestApp extends StatefulWidget {
  final _FakeDatabaseService databaseService;
  final _FakeSettingsService settingsService;
  final List<NoteTag> tags;
  final List<String> selectedTagIds;
  final List<String> selectedWeathers;
  final List<String> selectedDayPeriods;
  final ValueChanged<List<String>>? onTagSelectionChanged;
  final void Function(List<String> weathers, List<String> dayPeriods)?
      onFilterChanged;

  const _FilterTestApp({
    required this.databaseService,
    required this.settingsService,
    required this.tags,
    required this.selectedTagIds,
    required this.selectedWeathers,
    required this.selectedDayPeriods,
    this.onTagSelectionChanged,
    this.onFilterChanged,
  });

  @override
  State<_FilterTestApp> createState() => _FilterTestAppState();
}

class _FilterTestAppState extends State<_FilterTestApp> {
  late List<String> _selectedTagIds;
  late List<String> _selectedWeathers;
  late List<String> _selectedDayPeriods;

  @override
  void initState() {
    super.initState();
    _selectedTagIds = widget.selectedTagIds;
    _selectedWeathers = widget.selectedWeathers;
    _selectedDayPeriods = widget.selectedDayPeriods;
  }

  @override
  void didUpdateWidget(covariant _FilterTestApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    _selectedTagIds = widget.selectedTagIds;
    _selectedWeathers = widget.selectedWeathers;
    _selectedDayPeriods = widget.selectedDayPeriods;
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<DatabaseService>.value(
          value: widget.databaseService,
        ),
        ChangeNotifierProvider<SettingsService>.value(
          value: widget.settingsService,
        ),
        ChangeNotifierProvider(create: (_) => NoteSearchController()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Material(
          child: NoteListView(
            tags: widget.tags,
            selectedTagIds: _selectedTagIds,
            onTagSelectionChanged: (tagIds) {
              setState(() {
                _selectedTagIds = tagIds;
              });
              widget.onTagSelectionChanged?.call(tagIds);
            },
            searchQuery: '',
            sortType: 'time',
            sortAscending: false,
            onSortChanged: (_, __) {},
            onSearchChanged: (_) {},
            onEdit: (_) {},
            onDelete: (_) {},
            onAskAI: (_) {},
            selectedWeathers: _selectedWeathers,
            selectedDayPeriods: _selectedDayPeriods,
            onFilterChanged: (weathers, dayPeriods) {
              setState(() {
                _selectedWeathers = weathers;
                _selectedDayPeriods = dayPeriods;
              });
              widget.onFilterChanged?.call(weathers, dayPeriods);
            },
          ),
        ),
      ),
    );
  }
}

class _FakeSettingsService extends ChangeNotifier implements SettingsService {
  @override
  AppSettings get appSettings => AppSettings.defaultSettings();

  @override
  LocalAISettings get localAISettings => LocalAISettings.defaultSettings();

  @override
  bool get requireBiometricForHidden => false;

  @override
  String get noteCardMediaStyle => NoteCardMediaStyle.thumbnail;

  @override
  bool get showFavoriteButton => true;

  @override
  bool get enableFirstOpenScrollPerfMonitor => false;

  @override
  bool get noteListDisableCardShadows => false;

  @override
  bool get noteListDisableBackdropBlur => false;

  @override
  bool get showExactTime => false;

  @override
  bool get showNoteEditTime => false;

  @override
  String get exportFormat => 'pdf';

  @override
  bool get prioritizeBoldContentInCollapse => false;

  @override
  String get noteInsertAnimationType => 'slide';

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('SettingsService.${invocation.memberName} 未实现');
}

class _FakeDatabaseService extends DatabaseService {
  _FakeDatabaseService() : super.forTesting();

  @override
  bool get isInitialized => true;

  @override
  bool get hasMoreQuotes => false;

  @override
  Stream<List<Quote>> watchQuotes({
    List<String>? tagIds,
    String? categoryId,
    int limit = 20,
    String orderBy = 'date DESC',
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    bool includeDeleted = false,
  }) {
    return Stream<List<Quote>>.value(const []);
  }

  @override
  Future<void> loadMoreQuotes({
    List<String>? tagIds,
    String? categoryId,
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    bool? includeDeleted,
    int? refillCount,
    bool suppressNotify = false,
  }) async {}

  @override
  Future<List<NoteTag>> getTags() async => const [];
}
