import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/controllers/add_note_controller.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/location_service.dart';

class FakeBuildContext extends Fake implements BuildContext {}

void main() {
  group('AddNoteController location metadata', () {
    test('removeNewLocation clears pending coordinates before save', () {
      final controller = AddNoteController(context: FakeBuildContext())
        ..includeLocation = true
        ..setNewLocationData(null, 39.9042, 116.4074);

      controller.removeNewLocation();

      expect(controller.includeLocation, isFalse);
      expect(controller.newLocation, isNull);
      expect(controller.newLatitude, isNull);
      expect(controller.newLongitude, isNull);
    });

    test('removeOriginalLocation clears persisted coordinates before save', () {
      final controller = AddNoteController(
        context: FakeBuildContext(),
        initialQuote: Quote(
          id: 'note-1',
          content: 'content',
          date: DateTime(2026).toIso8601String(),
          location: LocationService.kAddressPending,
          latitude: 39.9042,
          longitude: 116.4074,
        ),
      );

      controller.removeOriginalLocation();

      expect(controller.includeLocation, isFalse);
      expect(controller.originalLocation, isNull);
      expect(controller.originalLatitude, isNull);
      expect(controller.originalLongitude, isNull);
    });
  });
}
