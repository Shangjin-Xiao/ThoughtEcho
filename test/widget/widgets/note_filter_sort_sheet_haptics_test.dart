library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/note_tag.dart';
import 'package:thoughtecho/widgets/interactive_animated_filter_chip.dart';
import 'package:thoughtecho/widgets/note_filter_sort_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<NoteTag> testTags = [
    NoteTag(id: 'tag_1', name: 'Work', iconName: 'work'),
    NoteTag(id: 'tag_2', name: 'Life', iconName: 'favorite'),
  ];

  Widget buildSheet({
    List<NoteTag>? tags,
    List<String>? selectedTagIds = const [],
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    String sortType = 'time',
    bool sortAscending = false,
    void Function(
      List<String> tagIds,
      String sortType,
      bool sortAscending,
      List<String> selectedWeathers,
      List<String> selectedDayPeriods,
    )? onApply,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(
        body: NoteFilterSortSheet(
          allTags: tags ?? testTags,
          selectedTagIds: selectedTagIds,
          sortType: sortType,
          sortAscending: sortAscending,
          selectedWeathers: selectedWeathers ?? ['sunny'],
          selectedDayPeriods: selectedDayPeriods ?? ['morning'],
          onApply: onApply ?? (_, __, ___, ____, _____) {},
        ),
      ),
    );
  }

  group(
      'NoteFilterSortSheet HapticFeedback & InteractiveAnimatedFilterChip Tests',
      () {
    late List<MethodCall> hapticCalls;

    setUp(() {
      hapticCalls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (
        MethodCall methodCall,
      ) async {
        if (methodCall.method == 'HapticFeedback.vibrate') {
          hapticCalls.add(methodCall);
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets(
        'all FilterChips in sheet are wrapped in InteractiveAnimatedFilterChip',
        (
      tester,
    ) async {
      await tester.pumpWidget(buildSheet());
      await tester.pumpAndSettle();

      final filterChips = find.byType(FilterChip);
      expect(filterChips, findsWidgets);

      final animatedChips = find.byType(InteractiveAnimatedFilterChip);
      expect(animatedChips, findsWidgets);

      // Verify that every FilterChip is an ancestor descendant of InteractiveAnimatedFilterChip
      final filterChipCount = tester.widgetList(filterChips).length;
      final animatedChipCount = tester.widgetList(animatedChips).length;
      expect(filterChipCount, greaterThan(0));
      expect(animatedChipCount, equals(filterChipCount));
    });

    testWidgets('tapping tag FilterChip triggers HapticFeedback.selectionClick',
        (
      tester,
    ) async {
      await tester.pumpWidget(buildSheet());
      await tester.pumpAndSettle();

      hapticCalls.clear();

      final tagChip = find.widgetWithText(FilterChip, 'Work');
      expect(tagChip, findsOneWidget);

      await tester.tap(tagChip);
      await tester.pumpAndSettle();

      expect(hapticCalls, isNotEmpty);
      expect(
        hapticCalls.any(
          (call) =>
              call.method == 'HapticFeedback.vibrate' &&
              call.arguments == 'HapticFeedbackType.selectionClick',
        ),
        isTrue,
      );
    });

    testWidgets(
        'tapping weather FilterChip triggers HapticFeedback.selectionClick', (
      tester,
    ) async {
      await tester.pumpWidget(buildSheet());
      await tester.pumpAndSettle();

      hapticCalls.clear();

      // Find first weather chip
      final weatherChips = find.descendant(
        of: find.byType(InteractiveAnimatedFilterChip),
        matching: find.byType(FilterChip),
      );
      expect(weatherChips, findsWidgets);

      // The 3rd chip is the first weather category chip (after 2 tags)
      await tester.tap(weatherChips.at(2));
      await tester.pumpAndSettle();

      expect(
        hapticCalls.any(
          (call) =>
              call.method == 'HapticFeedback.vibrate' &&
              call.arguments == 'HapticFeedbackType.selectionClick',
        ),
        isTrue,
      );
    });

    testWidgets(
        'tapping day period FilterChip triggers HapticFeedback.selectionClick',
        (
      tester,
    ) async {
      await tester.pumpWidget(buildSheet());
      await tester.pumpAndSettle();

      hapticCalls.clear();

      // Find day period chip (around index 7+)
      final chips = find.descendant(
        of: find.byType(InteractiveAnimatedFilterChip),
        matching: find.byType(FilterChip),
      );
      // Tap one of the day period chips
      await tester.tap(chips.at(tester.widgetList(chips).length - 1));
      await tester.pumpAndSettle();

      expect(
        hapticCalls.any(
          (call) =>
              call.method == 'HapticFeedback.vibrate' &&
              call.arguments == 'HapticFeedbackType.selectionClick',
        ),
        isTrue,
      );
    });

    testWidgets('clicking reset button triggers HapticFeedback.lightImpact', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSheet(
          selectedTagIds: ['tag_1'],
        ),
      );
      await tester.pumpAndSettle();

      hapticCalls.clear();

      final resetButton = find.widgetWithText(TextButton, '重置');
      expect(resetButton, findsOneWidget);

      await tester.tap(resetButton);
      await tester.pumpAndSettle();

      expect(
        hapticCalls.any(
          (call) =>
              call.method == 'HapticFeedback.vibrate' &&
              call.arguments == 'HapticFeedbackType.lightImpact',
        ),
        isTrue,
      );
    });

    testWidgets('clicking apply button triggers HapticFeedback.mediumImpact', (
      tester,
    ) async {
      bool applied = false;
      await tester.pumpWidget(
        buildSheet(
          selectedTagIds: ['tag_1'],
          onApply: (tags, sortType, sortAsc, weathers, periods) {
            applied = true;
          },
        ),
      );
      await tester.pumpAndSettle();

      // Change a filter so the Apply button becomes enabled
      final workChip = find.widgetWithText(FilterChip, 'Work');
      await tester.tap(workChip); // unselect 'tag_1'
      await tester.pumpAndSettle();

      hapticCalls.clear();

      final applyButton = find.byType(FilledButton);
      await tester.ensureVisible(applyButton);
      await tester.pumpAndSettle();
      expect(applyButton, findsOneWidget);
      expect(find.descendant(of: applyButton, matching: find.text('应用')),
          findsOneWidget);

      await tester.tap(applyButton);
      await tester.pumpAndSettle();

      expect(applied, isTrue);
      expect(
        hapticCalls.any(
          (call) =>
              call.method == 'HapticFeedback.vibrate' &&
              call.arguments == 'HapticFeedbackType.mediumImpact',
        ),
        isTrue,
      );
    });

    testWidgets(
        'gracefully degrades without exceptions if haptic platform throws', (
      tester,
    ) async {
      // Setup mock to throw PlatformException
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (
        MethodCall methodCall,
      ) async {
        if (methodCall.method == 'HapticFeedback.vibrate') {
          throw PlatformException(
            code: 'UNSUPPORTED',
            message: 'Haptics not supported on device',
          );
        }
        return null;
      });

      await tester.pumpWidget(
        buildSheet(
          selectedTagIds: ['tag_1'],
        ),
      );
      await tester.pumpAndSettle();

      // Reset button click should not throw
      final resetButton = find.widgetWithText(TextButton, '重置');
      await tester.tap(resetButton);
      await tester.pumpAndSettle();

      // Chip click should not throw
      final tagChip = find.widgetWithText(FilterChip, 'Work');
      await tester.tap(tagChip);
      await tester.pumpAndSettle();

      // Apply button click should not throw
      final applyButton = find.byType(FilledButton);
      await tester.ensureVisible(applyButton);
      await tester.pumpAndSettle();
      await tester.tap(applyButton);
      await tester.pumpAndSettle();
    });

    testWidgets(
        'modifying default filter and resetting keeps Apply button enabled and calls onApply',
        (tester) async {
      List<String>? appliedTags;
      String? appliedSortType;
      bool? appliedSortAsc;
      List<String>? appliedWeathers;
      List<String>? appliedPeriods;

      await tester.pumpWidget(
        buildSheet(
          selectedTagIds: const [],
          selectedWeathers: const [],
          selectedDayPeriods: const [],
          onApply: (tags, sortType, sortAsc, weathers, periods) {
            appliedTags = tags;
            appliedSortType = sortType;
            appliedSortAsc = sortAsc;
            appliedWeathers = weathers;
            appliedPeriods = periods;
          },
        ),
      );
      await tester.pumpAndSettle();

      final applyButtonFinder = find.byType(FilledButton);
      // Initially, Apply button should be disabled
      expect(tester.widget<FilledButton>(applyButtonFinder).onPressed, isNull);

      // Modify by selecting 'Work'
      final workChip = find.widgetWithText(FilterChip, 'Work');
      await tester.ensureVisible(workChip);
      await tester.pumpAndSettle();
      await tester.tap(workChip);
      await tester.pumpAndSettle();

      // Apply button should be enabled after modification
      expect(
        tester.widget<FilledButton>(applyButtonFinder).onPressed,
        isNotNull,
      );

      // Tap Reset button
      final resetButton = find.widgetWithText(TextButton, '重置');
      await tester.ensureVisible(resetButton);
      await tester.pumpAndSettle();
      await tester.tap(resetButton);
      await tester.pumpAndSettle();

      // Even though temp matches initial default parameters, explicit reset must keep Apply enabled
      expect(
        tester.widget<FilledButton>(applyButtonFinder).onPressed,
        isNotNull,
      );

      // Tapping Apply triggers onApply callback with default parameters
      await tester.ensureVisible(applyButtonFinder);
      await tester.pumpAndSettle();
      await tester.tap(applyButtonFinder);
      await tester.pumpAndSettle();

      expect(appliedTags, isEmpty);
      expect(appliedSortType, equals('time'));
      expect(appliedSortAsc, isFalse);
      expect(appliedWeathers, isEmpty);
      expect(appliedPeriods, isEmpty);
    });

    testWidgets(
        'unchecking and re-checking tag does not trigger false-positive Apply button enablement (unordered Set equality)',
        (tester) async {
      await tester.pumpWidget(
        buildSheet(
          selectedTagIds: const ['tag_1', 'tag_2'],
          selectedWeathers: const [],
          selectedDayPeriods: const [],
        ),
      );
      await tester.pumpAndSettle();

      final applyButtonFinder = find.byType(FilledButton);
      // Initially disabled
      expect(tester.widget<FilledButton>(applyButtonFinder).onPressed, isNull);

      // Uncheck 'Work' ('tag_1')
      final workChip = find.widgetWithText(FilterChip, 'Work');
      await tester.ensureVisible(workChip);
      await tester.pumpAndSettle();
      await tester.tap(workChip);
      await tester.pumpAndSettle();

      // Changes exist, Apply is enabled
      expect(
        tester.widget<FilledButton>(applyButtonFinder).onPressed,
        isNotNull,
      );

      // Re-check 'Work' ('tag_1') -> internal list order becomes ['tag_2', 'tag_1']
      await tester.ensureVisible(workChip);
      await tester.pumpAndSettle();
      await tester.tap(workChip);
      await tester.pumpAndSettle();

      // Set equality recognizes {'tag_2', 'tag_1'} == {'tag_1', 'tag_2'}, Apply button is disabled
      expect(tester.widget<FilledButton>(applyButtonFinder).onPressed, isNull);
    });

    testWidgets(
        'unchecking and re-checking single tag resets Apply button to disabled',
        (tester) async {
      await tester.pumpWidget(
        buildSheet(
          selectedTagIds: const ['tag_1'],
          selectedWeathers: const [],
          selectedDayPeriods: const [],
        ),
      );
      await tester.pumpAndSettle();

      final applyButtonFinder = find.byType(FilledButton);
      expect(tester.widget<FilledButton>(applyButtonFinder).onPressed, isNull);

      final workChip = find.widgetWithText(FilterChip, 'Work');
      await tester.ensureVisible(workChip);
      await tester.pumpAndSettle();
      await tester.tap(workChip);
      await tester.pumpAndSettle();

      expect(
        tester.widget<FilledButton>(applyButtonFinder).onPressed,
        isNotNull,
      );

      await tester.ensureVisible(workChip);
      await tester.pumpAndSettle();
      await tester.tap(workChip);
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(applyButtonFinder).onPressed, isNull);
    });

    testWidgets(
        'manually re-checking options back to initial config after reset clears dirty state and disables Apply',
        (tester) async {
      await tester.pumpWidget(
        buildSheet(
          selectedTagIds: const ['tag_1'],
          selectedWeathers: const [],
          selectedDayPeriods: const [],
        ),
      );
      await tester.pumpAndSettle();

      final applyButtonFinder = find.byType(FilledButton);
      expect(tester.widget<FilledButton>(applyButtonFinder).onPressed, isNull);

      // Tap Reset
      final resetButton = find.widgetWithText(TextButton, '重置');
      await tester.ensureVisible(resetButton);
      await tester.pumpAndSettle();
      await tester.tap(resetButton);
      await tester.pumpAndSettle();

      // Apply is enabled after reset
      expect(
        tester.widget<FilledButton>(applyButtonFinder).onPressed,
        isNotNull,
      );

      // Manually select 'Work' ('tag_1') again, returning to initial config
      final workChip = find.widgetWithText(FilterChip, 'Work');
      await tester.ensureVisible(workChip);
      await tester.pumpAndSettle();
      await tester.tap(workChip);
      await tester.pumpAndSettle();

      // Should synchronously reset _hasExplicitlyReset and disable Apply to prevent invalid submission
      expect(tester.widget<FilledButton>(applyButtonFinder).onPressed, isNull);
    });

    testWidgets(
        'rapid repeated clicks on reset button avoid redundant haptics and state jitter',
        (tester) async {
      await tester.pumpWidget(
        buildSheet(
          selectedTagIds: const ['tag_1'],
        ),
      );
      await tester.pumpAndSettle();

      hapticCalls.clear();
      final resetButton = find.widgetWithText(TextButton, '重置');
      await tester.ensureVisible(resetButton);
      await tester.pumpAndSettle();

      // First click
      await tester.tap(resetButton);
      await tester.pumpAndSettle();

      expect(
        hapticCalls.where(
          (call) =>
              call.method == 'HapticFeedback.vibrate' &&
              call.arguments == 'HapticFeedbackType.lightImpact',
        ),
        hasLength(1),
      );

      // Second click in rapid succession
      hapticCalls.clear();
      await tester.tap(resetButton);
      await tester.pumpAndSettle();

      // Redundant click should be ignored
      expect(hapticCalls, isEmpty);
    });

    testWidgets(
        'external null selectedTagIds is safely handled without throwing',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: NoteFilterSortSheet(
              allTags: testTags,
              selectedTagIds: null,
              sortType: 'time',
              sortAscending: false,
              onApply: (_, __, ___, ____, _____) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final workChip = find.widgetWithText(FilterChip, 'Work');
      expect(workChip, findsOneWidget);

      final applyButtonFinder = find.byType(FilledButton);
      // Initially disabled
      expect(tester.widget<FilledButton>(applyButtonFinder).onPressed, isNull);

      // Select tag
      await tester.ensureVisible(workChip);
      await tester.pumpAndSettle();
      await tester.tap(workChip);
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(applyButtonFinder).onPressed,
        isNotNull,
      );

      // Reset
      final resetButton = find.widgetWithText(TextButton, '重置');
      await tester.ensureVisible(resetButton);
      await tester.pumpAndSettle();
      await tester.tap(resetButton);
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(applyButtonFinder).onPressed,
        isNotNull,
      );
    });
  });
}
