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

    test(
        'should update query, reset states, and notify listeners when query is new',
        () {
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

    test('should cancel pending timers and update immediately', () {
      // Trigger a search
      controller.updateSearch('test query');
      expect(controller.searchQuery, 'test query');
      expect(controller.isSearching, true);

      // Call updateSearchImmediate
      controller.updateSearchImmediate('immediate query');

      // Check immediate update worked
      expect(controller.searchQuery, 'immediate query');
      expect(controller.isSearching, false);
    });
  });

  group('NoteSearchController - updateSearch', () {
    late NoteSearchController controller;

    setUp(() {
      controller = NoteSearchController();
    });

    test('should do nothing if query is unchanged', () {
      controller.updateSearchImmediate('test');

      bool notified = false;
      controller.addListener(() {
        notified = true;
      });

      controller.updateSearch('test');
      expect(notified, false);
      expect(controller.searchQuery, 'test');
    });

    test('should clear search if query is empty', () {
      controller.updateSearchImmediate('test');
      expect(controller.searchQuery, 'test');

      controller.updateSearch('');
      expect(controller.searchQuery, '');
      expect(controller.isSearching, false);
      expect(controller.searchError, null);
    });

    test('should only update query if length < 2', () {
      controller.updateSearch('a');
      expect(controller.searchQuery, 'a');
      expect(controller.isSearching, false);
      expect(controller.searchError, null);
    });

    test('should update query and set searching if length >= 2', () {
      controller.updateSearch('test');
      expect(controller.searchQuery, 'test');
      expect(controller.isSearching, true);
      expect(controller.searchError, null);
    });

    test('should set timeout error after 5 seconds of searching', () {
      fakeAsync((async) {
        controller.updateSearch('test query');
        expect(controller.isSearching, true);
        expect(controller.searchError, null);

        // Advance time by 4 seconds (no timeout yet)
        async.elapse(const Duration(seconds: 4));
        expect(controller.isSearching, true);
        expect(controller.searchError, null);

        // Advance time by 1 more second (timeout hits)
        async.elapse(const Duration(seconds: 1));
        expect(controller.isSearching, false);
        expect(controller.searchError, '搜索超时，请重试');
      });
    });

    test('should not set timeout error if search completed before 5 seconds',
        () {
      fakeAsync((async) {
        controller.updateSearch('test query');

        // Advance time by 2 seconds
        async.elapse(const Duration(seconds: 2));

        // Simulate search completing
        controller.setSearchState(false);

        // Advance time past 5 seconds
        async.elapse(const Duration(seconds: 4));

        expect(controller.searchError, null);
      });
    });
  });

  group('NoteSearchController - resetSearchState', () {
    late NoteSearchController controller;

    setUp(() {
      controller = NoteSearchController();
    });

    test('should reset state flags and notify listeners', () {
      controller.updateSearch('test');
      expect(controller.isSearching, true);

      bool notified = false;
      controller.addListener(() {
        notified = true;
      });

      controller.resetSearchState();

      expect(controller.isSearching, false);
      expect(controller.searchError, null);
      expect(notified, true);
    });

    test('should invalidate pending timeout timer', () {
      fakeAsync((async) {
        controller.updateSearch('test query');
        expect(controller.isSearching, true);

        controller.resetSearchState();
        expect(controller.isSearching, false);

        // Advance time past 5 seconds
        async.elapse(const Duration(seconds: 6));

        // Error should not be set because the version changed and timer was cancelled
        expect(controller.searchError, null);
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

    test('should cancel pending timers and clear search', () {
      // Trigger a search
      controller.updateSearch('test query');
      expect(controller.searchQuery, 'test query');
      expect(controller.isSearching, true);

      // Call clearSearch
      controller.clearSearch();

      // The query remains empty
      expect(controller.searchQuery, '');
      expect(controller.isSearching, false);
    });
  });
}
