import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/controllers/search_controller.dart';
import 'dart:async';

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
}
