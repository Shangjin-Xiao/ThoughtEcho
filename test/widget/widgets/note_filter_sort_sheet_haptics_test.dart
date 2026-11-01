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
    List<String> selectedTagIds = const [],
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
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
          sortType: 'time',
          sortAscending: false,
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
  });
}
