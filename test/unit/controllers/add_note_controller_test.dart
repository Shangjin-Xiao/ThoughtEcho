import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/controllers/add_note_controller.dart';
import 'package:thoughtecho/models/note_tag.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/database_service.dart';
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

  group(
      'AddNoteController.addDefaultHitokotoTagsAsync performance & query count',
      () {
    test('addDefaultHitokotoTagsAsync adds tags correctly and batches DB reads',
        () async {
      final db = _CountingDatabaseService();
      final controller = AddNoteController(
        context: FakeBuildContext(),
        hitokotoData: {
          'type': 'a',
          'provider': 'hitokoto',
        },
      )..updateServices(dbService: db);

      NoteTag? updatedCategory;
      await controller.addDefaultHitokotoTagsAsync((cat) {
        updatedCategory = cat;
      });

      // Ensure correctness
      expect(controller.selectedTagIds,
          containsAll(['default_hitokoto', 'default_anime']));
      expect(updatedCategory?.id, equals('default_anime'));
      expect(controller.selectedCategory?.id, equals('default_anime'));

      // Check query counts
      // Under optimized implementation, db.getTagById should NOT be called N times in a loop.
      expect(db.getTagByIdCallCount, equals(0),
          reason:
              'getTagById should not be called inside loop when cached/batched tags are used');
      expect(db.getTagsCallCount, lessThanOrEqualTo(1),
          reason: 'getTags should be called at most once to prefetch tags');
    });

    test(
        'updateServices with a new dbService resets allCategoriesCache and reloads from new db',
        () async {
      final db1 = _CountingDatabaseService();
      final db2 = _CountingDatabaseService();

      final controller = AddNoteController(context: FakeBuildContext())
        ..updateServices(dbService: db1);

      await controller.ensureTagExists(db1, '每日一言', '💭');
      expect(controller.allCategoriesCache, isNotNull);
      expect(db1.getTagsCallCount, equals(1));

      controller.updateServices(dbService: db2);
      expect(controller.allCategoriesCache, isNull,
          reason:
              'allCategoriesCache should be reset when switching databaseService');

      await controller.ensureTagExists(db2, '每日一言', '💭');
      expect(db2.getTagsCallCount, equals(1));
    });
  });
}

class _CountingDatabaseService extends DatabaseService {
  _CountingDatabaseService() : super.forTesting();

  int getTagByIdCallCount = 0;
  int getTagsCallCount = 0;

  final Map<String, NoteTag> _tags = {
    'default_hitokoto':
        NoteTag(id: 'default_hitokoto', name: '每日一言', iconName: '💭'),
    'default_anime': NoteTag(id: 'default_anime', name: '动画', iconName: '🎬'),
  };

  @override
  Future<NoteTag?> getTagById(String id) async {
    getTagByIdCallCount++;
    return _tags[id];
  }

  @override
  Future<List<NoteTag>> getTags() async {
    getTagsCallCount++;
    return _tags.values.toList();
  }

  @override
  Future<void> addTagWithId(String id, String name, {String? iconName}) async {
    _tags[id] = NoteTag(id: id, name: name, iconName: iconName ?? '');
  }

  @override
  Future<void> addTag(String name, {String? iconName}) async {
    final id = name;
    _tags[id] = NoteTag(id: id, name: name, iconName: iconName ?? '');
  }

  @override
  bool get isInitialized => true;
}
