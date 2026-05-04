import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/controllers/search_controller.dart';

void main() {
  group('NoteSearchController - setSearchState', () {
    late NoteSearchController controller;

    setUp(() {
      controller = NoteSearchController();
    });

    test('should update isSearching flag correctly', () {
      expect(controller.isSearching, false);

      controller.setSearchState(true);
      expect(controller.isSearching, true);

      controller.setSearchState(false);
      expect(controller.isSearching, false);
    });

    test('should notify listeners when state changes', () {
      bool notified = false;
      controller.addListener(() {
        notified = true;
      });

      controller.setSearchState(true);
      expect(notified, true);
    });

    test('should not notify listeners when state is unchanged', () {
      controller.setSearchState(true);

      bool notified = false;
      controller.addListener(() {
        notified = true;
      });

      controller.setSearchState(true);
      expect(notified, false);
    });
  });

  group('NoteSearchController - updateSearchImmediate', () {
    late NoteSearchController controller;

    setUp(() {
      controller = NoteSearchController();
    });

    test('should update query, reset states, and notify listeners when query is new', () {
      controller.setSearchState(true);
      // It's hard to set _searchError, but we can verify it becomes null.

      bool notified = false;
      controller.addListener(() {
        notified = true;
      });

      controller.updateSearchImmediate('immediate query');

      expect(controller.searchQuery, 'immediate query');
      expect(controller.isSearching, false);
      expect(controller.searchError, null);
      expect(notified, true);
    });

    test('should not notify listeners if query is unchanged', () {
      controller.updateSearchImmediate('test query');
      expect(controller.searchQuery, 'test query');

      bool notified = false;
      controller.addListener(() {
        notified = true;
      });

      controller.updateSearchImmediate('test query');
      expect(notified, false);
    });

    test('should cancel pending debounce timer', () {
      fakeAsync((async) {
        // Trigger a search that will start a 500ms debounce timer
        controller.updateSearch('delayed query');
        expect(controller.searchQuery, ''); // Query hasn't updated yet due to debounce
        expect(controller.isSearching, true);

        // Call updateSearchImmediate before the debounce timer fires
        controller.updateSearchImmediate('immediate query');

        // Check immediate update worked
        expect(controller.searchQuery, 'immediate query');
        expect(controller.isSearching, false);

        // Fast forward time past the debounce period
        async.elapse(const Duration(milliseconds: 600));

        // The delayed update should have been cancelled, so the query remains 'immediate query'
        expect(controller.searchQuery, 'immediate query');
        // And it should not have become isSearching again due to delayed task firing
        expect(controller.isSearching, false);
      });
    });
  });

  group('NoteSearchController - clearSearch', () {
    late NoteSearchController controller;

    setUp(() {
      controller = NoteSearchController();
    });

    test('should reset state and notify listeners when query is not empty', () {
      // First set some state
      controller.updateSearchImmediate('test query');
      controller.setSearchState(true);
      // Wait for immediate state change, note error is not directly settable here but clearing should reset it.

      expect(controller.searchQuery, 'test query');
      expect(controller.isSearching, true);

      bool notified = false;
      controller.addListener(() {
        notified = true;
      });

      controller.clearSearch();

      expect(controller.searchQuery, '');
      expect(controller.isSearching, false);
      expect(controller.searchError, null);
      expect(notified, true);
    });

    test('should not notify listeners when query is already empty', () {
      expect(controller.searchQuery, '');

      bool notified = false;
      controller.addListener(() {
        notified = true;
      });

      controller.clearSearch();

      expect(notified, false);
    });

    test('should cancel pending debounce timer', () {
      fakeAsync((async) {
        // Trigger a search that will start a 500ms debounce timer
        controller.updateSearch('delayed query');

        expect(controller.searchQuery,
            ''); // Query hasn't updated yet due to debounce

        // Check that isSearching was set to true immediately by updateSearch
        expect(controller.isSearching, true);

        // Call clearSearch before the debounce timer fires
        controller.clearSearch();

        // Fast forward time past the debounce period
        async.elapse(const Duration(milliseconds: 600));

        // The delayed update should have been cancelled, so the query remains empty
        expect(controller.searchQuery, '');
        // clearSearch immediately sets isSearching back to false
        expect(controller.isSearching, false);
      });
    });
  });
}
