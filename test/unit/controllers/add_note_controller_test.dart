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

  group('AddNoteController 自动附加抓取标志', () {
    test('armAutoMetadataFetch 预约后 isFetchingMetadata 立即为真', () {
      final controller = AddNoteController(context: FakeBuildContext());
      var notified = 0;
      controller.addListener(() => notified++);

      controller.armAutoMetadataFetch(location: true, weather: true);

      expect(controller.isFetchingLocation, isTrue);
      expect(controller.isFetchingWeather, isTrue);
      expect(controller.isFetchingMetadata, isTrue);
      expect(notified, 1);
    });

    test('armAutoMetadataFetch 状态没变时不通知', () {
      final controller = AddNoteController(context: FakeBuildContext());
      var notified = 0;
      controller.addListener(() => notified++);

      controller.armAutoMetadataFetch(location: false, weather: false);

      expect(notified, 0);
    });

    test('服务缺失时按失败处理：放掉标志并取消勾选，不留虚假的已附加状态', () async {
      final controller = AddNoteController(context: FakeBuildContext())
        ..includeLocation = true
        ..includeWeather = true
        ..armAutoMetadataFetch(location: true, weather: true);

      await controller.fetchLocationForNewNote();
      expect(controller.isFetchingLocation, isFalse);
      expect(controller.includeLocation, isFalse,
          reason: '拿不到位置服务就不该保留「已附加位置」的勾');
      expect(controller.isFetchingWeather, isTrue);

      await controller.fetchWeatherForNewNote();
      expect(controller.isFetchingWeather, isFalse);
      expect(controller.includeWeather, isFalse,
          reason: '拿不到天气服务时保留勾选，保存会把上一次的天气写进这条笔记');
      expect(controller.isFetchingMetadata, isFalse);
    });

    test('用户主动移除位置/天气时清掉在途标志', () {
      final controller = AddNoteController(context: FakeBuildContext())
        ..armAutoMetadataFetch(location: true, weather: true);

      controller.removeNewLocation();
      expect(controller.isFetchingLocation, isFalse);

      controller.removeNewWeather();
      expect(controller.includeWeather, isFalse);
      expect(controller.isFetchingWeather, isFalse);
    });
  });
}
