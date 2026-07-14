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
  });
}
