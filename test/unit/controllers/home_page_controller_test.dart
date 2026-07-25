import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/controllers/home_page_controller.dart';
import 'package:thoughtecho/models/note_category.dart';

void main() {
  group('HomePageController', () {
    test('tab and note-list choices change through one observable seam', () {
      final controller = HomePageController(initialPage: 0);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller
        ..selectPage(1)
        ..setSelectedTagIds(const ['tag-1'])
        ..setSort(type: 'content', ascending: true)
        ..setFilters(
          weathers: const ['sunny'],
          dayPeriods: const ['morning'],
        );

      expect(controller.currentIndex, 1);
      expect(controller.selectedTagIds, const ['tag-1']);
      expect(controller.sortType, 'content');
      expect(controller.sortAscending, isTrue);
      expect(controller.selectedWeathers, const ['sunny']);
      expect(controller.selectedDayPeriods, const ['morning']);
      expect(notifications, 4);
    });

    test('tag loading owns its loading and result lifecycle', () async {
      final controller = HomePageController(initialPage: 0);
      final pending = Completer<List<NoteCategory>>();

      final load = controller.loadTags(() => pending.future);

      expect(controller.isLoadingTags, isTrue);
      pending.complete([
        NoteCategory(id: 'tag-1', name: 'Tag 1'),
      ]);
      await load;

      expect(controller.isLoadingTags, isFalse);
      expect(controller.tags.map((tag) => tag.id), ['tag-1']);
    });

    test('an older overlapping tag load cannot replace the latest result',
        () async {
      final controller = HomePageController(initialPage: 0);
      final older = Completer<List<NoteCategory>>();
      final latest = Completer<List<NoteCategory>>();

      final olderLoad = controller.loadTags(() => older.future);
      final latestLoad = controller.loadTags(() => latest.future);
      latest.complete([NoteCategory(id: 'latest', name: 'Latest')]);
      await latestLoad;
      older.complete([NoteCategory(id: 'older', name: 'Older')]);
      await olderLoad;

      expect(controller.tags.map((tag) => tag.id), ['latest']);
      expect(controller.isLoadingTags, isFalse);
    });

    test('does not notify listeners when state does not change', () {
      final controller = HomePageController(initialPage: 0);

      controller
          .setFilters(weathers: const ['sunny'], dayPeriods: const ['morning']);
      controller.setSelectedTagIds(const ['tag-1']);
      controller.setSort(type: 'time', ascending: false);

      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.selectPage(0);
      controller.setSelectedTagIds(const ['tag-1']);
      controller.setSort(type: 'time', ascending: false);
      controller
          .setFilters(weathers: const ['sunny'], dayPeriods: const ['morning']);

      expect(notifications, 0);
    });

    test('loadTags notifies if not already loading tags', () async {
      final controller = HomePageController(initialPage: 0);

      // Complete initial load to set isLoadingTags to false
      await controller.loadTags(() async => []);
      expect(controller.isLoadingTags, isFalse);

      var notifications = 0;
      controller.addListener(() => notifications++);

      final load = controller.loadTags(() async => []);

      // Should immediately notify that loading started
      expect(controller.isLoadingTags, isTrue);
      expect(notifications, 1);

      await load;

      // Should notify again that loading finished
      expect(controller.isLoadingTags, isFalse);
      expect(notifications, 2);
    });

    test('dispose increments generation and prevents state updates', () async {
      final controller = HomePageController(initialPage: 0);
      final pending = Completer<List<NoteCategory>>();

      final load = controller.loadTags(() => pending.future);
      controller.dispose();

      pending.complete([NoteCategory(id: 'tag-1', name: 'Tag 1')]);
      await load;

      expect(controller.tags, isEmpty);
      // Because it's disposed, it shouldn't update tags
    });
  });
}
