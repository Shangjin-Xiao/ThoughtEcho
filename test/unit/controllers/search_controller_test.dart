import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
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

  group('NoteSearchController - updateSearch', () {
    late NoteSearchController controller;

    setUp(() {
      controller = NoteSearchController();
    });

    test('should handle empty string query', () {
      controller.updateSearchImmediate('test');
      expect(controller.searchQuery, 'test');

      controller.updateSearch('');
      expect(controller.searchQuery, '');
      expect(controller.isSearching, false);
      expect(controller.searchError, null);
    });

    test('should handle short string query (< 2 chars)', () {
      controller.updateSearch('a');
      expect(controller.searchQuery, 'a');
      expect(controller.isSearching, false);
      expect(controller.searchError, null);
    });

    test('should debounce normal query', () {
      fakeAsync((async) {
        bool notified = false;
        controller.addListener(() {
          notified = true;
        });

        controller.updateSearch('test query');

        // Immediately sets isSearching to true
        expect(controller.isSearching, true);
        expect(controller.searchQuery, ''); // Query not updated yet

        // Advance time by 400ms (less than 500ms debounce)
        async.elapse(const Duration(milliseconds: 400));
        expect(controller.searchQuery, '');

        // Advance time by 100ms (total 500ms)
        async.elapse(const Duration(milliseconds: 100));
        expect(controller.searchQuery, 'test query');
        expect(notified, true);
      });
    });

    test('should cancel previous debounce timer if updated quickly', () {
      fakeAsync((async) {
        controller.updateSearch('test1');

        async.elapse(const Duration(milliseconds: 300));

        controller.updateSearch('test2');

        // Advance 300ms, first query would have resolved if not cancelled,
        // but now it's cancelled, so query should remain empty.
        async.elapse(const Duration(milliseconds: 300));
        expect(controller.searchQuery, '');

        // Advance another 200ms (total 500ms for test2)
        async.elapse(const Duration(milliseconds: 200));
        expect(controller.searchQuery, 'test2');
      });
    });

    test('should set timeout error if search takes too long', () {
      fakeAsync((async) {
        controller.updateSearch('test timeout');

        // Advance past debounce
        async.elapse(const Duration(milliseconds: 500));
        expect(controller.searchQuery, 'test timeout');
        expect(controller.isSearching, true);

        // Advance past timeout (5 seconds)
        async.elapse(const Duration(seconds: 5));

        expect(controller.isSearching, false);
        expect(controller.searchError, '搜索超时，请重试');
      });
    });

    test('should ignore delayed results if query changes', () {
      // Actually, timeout timer checks version.
      fakeAsync((async) {
        controller.updateSearch('first');

        // Advance past debounce
        async.elapse(const Duration(milliseconds: 500));

        // Now it's searching 'first'. We start a new search.
        controller.updateSearch('second');

        // Advance 5 seconds to trigger first search timeout.
        // It should NOT affect the current search because version/query changed.
        async.elapse(const Duration(seconds: 5));

        expect(controller.searchError, null);
      });
    });
  });

  group('NoteSearchController - other methods', () {
    late NoteSearchController controller;

    setUp(() {
      controller = NoteSearchController();
    });

    test('updateSearchImmediate should update immediately without debounce', () {
      fakeAsync((async) {
        controller.updateSearchImmediate('immediate test');
        expect(controller.searchQuery, 'immediate test');
        expect(controller.isSearching, false);
        expect(controller.searchError, null);
      });
    });

    test('clearSearch should clear query immediately', () {
      controller.updateSearchImmediate('test');
      expect(controller.searchQuery, 'test');

      controller.clearSearch();
      expect(controller.searchQuery, '');
      expect(controller.isSearching, false);
      expect(controller.searchError, null);
    });

    test('resetSearchState should reset state and cancel timers', () {
      fakeAsync((async) {
        controller.updateSearch('test search');

        controller.resetSearchState();

        expect(controller.isSearching, false);
        expect(controller.searchError, null);

        // Advance past debounce to ensure it was cancelled/ignored
        async.elapse(const Duration(milliseconds: 500));
        expect(controller.searchQuery, ''); // Query not updated because timer/version changed
      });
    });
  });
}
