import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:thoughtecho/controllers/add_note_controller.dart';
import 'package:thoughtecho/models/note_tag.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/weather_service.dart';

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

  group('AddNoteController.resolvePickedLocationForSave', () {
    test('已选定四级串时直接采用', () {
      expect(
        AddNoteController.resolvePickedLocationForSave(
          pickedLocation: '中国,北京市,北京市,西城区',
          pickedPoiName: '景山公园',
          pickedLatitude: 39.9242,
          pickedLongitude: 116.4014,
          deviceLocation: '中国,北京市,北京市,东城区',
          deviceLatitude: 39.9042,
          deviceLongitude: 116.4074,
        ),
        '中国,北京市,北京市,西城区',
      );
    });

    test('异地 POI 缺行政区时不拿设备行政区顶，退回待解析标记', () {
      expect(
        AddNoteController.resolvePickedLocationForSave(
          pickedLocation: null,
          pickedPoiName: '景山公园',
          pickedLatitude: 39.9242,
          pickedLongitude: 116.4014,
          deviceLocation: '中国,北京市,北京市,东城区',
          deviceLatitude: 39.9042,
          deviceLongitude: 116.4074,
        ),
        LocationService.kAddressPending,
      );
    });

    test('同坐标 POI 缺行政区时仍可用设备行政区', () {
      expect(
        AddNoteController.resolvePickedLocationForSave(
          pickedLocation: null,
          pickedPoiName: '故宫角楼',
          pickedLatitude: 39.9042,
          pickedLongitude: 116.4074,
          deviceLocation: '中国,北京市,北京市,东城区',
          deviceLatitude: 39.9042,
          deviceLongitude: 116.4074,
        ),
        '中国,北京市,北京市,东城区',
      );
    });

    test('无 POI 纯设备定位时沿用旧兜底', () {
      expect(
        AddNoteController.resolvePickedLocationForSave(
          pickedLocation: null,
          pickedPoiName: null,
          pickedLatitude: 39.9042,
          pickedLongitude: 116.4074,
          deviceLocation: '中国,北京市,北京市,东城区',
          deviceLatitude: 39.9042,
          deviceLongitude: 116.4074,
        ),
        '中国,北京市,北京市,东城区',
      );
    });

    test('都没有时有坐标则待解析，无坐标则空', () {
      expect(
        AddNoteController.resolvePickedLocationForSave(
          pickedLocation: null,
          pickedPoiName: null,
          pickedLatitude: 39.9042,
          pickedLongitude: 116.4074,
          deviceLocation: null,
          deviceLatitude: null,
          deviceLongitude: null,
        ),
        LocationService.kAddressPending,
      );
      expect(
        AddNoteController.resolvePickedLocationForSave(
          pickedLocation: null,
          pickedPoiName: null,
          pickedLatitude: null,
          pickedLongitude: null,
          deviceLocation: null,
          deviceLatitude: null,
          deviceLongitude: null,
        ),
        isNull,
      );
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
      expect(controller.includeLocation, isFalse);
      expect(controller.isFetchingLocation, isFalse);
      expect(
        controller.isFetchingWeather,
        isTrue,
        reason: 'removeNewLocation 不会意外影响在途天气状态',
      );

      controller.removeNewWeather();
      expect(controller.includeWeather, isFalse);
      expect(controller.isFetchingWeather, isFalse);
    });

    test('在途位置抓取被 clearPendingLocationFetch/setNewLocationData 作废后不会覆盖手动设置的位置',
        () async {
      final completer = Completer<Position?>();
      final locService = _MockLocationServiceForRace(completer);
      final controller = AddNoteController(context: FakeBuildContext())
        ..updateServices(locService: locService)
        ..includeLocation = true;

      // 启动在途异步位置抓取
      final fetchFuture = controller.fetchLocationForNewNote();
      expect(controller.isFetchingLocation, isTrue);

      // 先让异步推进跨过权限检查，真正进入 getCurrentLocation 的 await
      await pumpEventQueue();

      // 用户手动选择地点（例如通过 NearbyLocationPicker）
      controller.clearPendingLocationFetch();
      controller.setNewLocationData(
        '中国,北京市,北京市,东城区',
        39.9042,
        116.4074,
        poiName: '故宫博物院',
      );
      expect(controller.isFetchingLocation, isFalse);
      expect(controller.newPoiName, '故宫博物院');

      // 此时延迟到达的自动抓取完成
      completer.complete(Position(
        latitude: 40.0,
        longitude: 116.0,
        timestamp: DateTime(2026),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      ));
      await fetchFuture;

      // 验证手动设置的位置未被在途任务覆盖
      expect(controller.newPoiName, '故宫博物院');
      expect(controller.newLatitude, 39.9042);
      expect(controller.newLongitude, 116.4074);
      expect(controller.newLocation, '中国,北京市,北京市,东城区');
    });

    test('fetchLocationForNewNote 从 LocationSnapshot 严格同源获取坐标与 poiName',
        () async {
      final completer = Completer<Position?>();
      final locService = _MockLocationServiceForRace(completer);
      final controller = AddNoteController(context: FakeBuildContext())
        ..updateServices(locService: locService)
        ..includeLocation = true;

      final fetchFuture = controller.fetchLocationForNewNote();
      await pumpEventQueue();

      completer.complete(Position(
        latitude: 39.9042,
        longitude: 116.4074,
        timestamp: DateTime(2026),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      ));
      await fetchFuture;

      expect(controller.newPoiName, '自动定位地名');
      expect(controller.newLatitude, 39.9042);
      expect(controller.newLongitude, 116.4074);
      expect(controller.newLocation, '中国,北京市,北京市,海淀区');
      expect(controller.isFetchingLocation, isFalse);
    });

    test('在途天气抓取被取消并重新发起后，旧请求的迟到完成不会错误重置新抓取的在途标志', () async {
      final completer1 = Completer<void>();
      final completer2 = Completer<void>();
      final weaService =
          _MockWeatherServiceForRace(completer1, completer2, false);
      var emptyCallbackCount = 0;
      final controller = AddNoteController(
        context: FakeBuildContext(),
        onWeatherFetchEmpty: () => emptyCallbackCount++,
      )
        ..updateServices(weaService: weaService)
        ..includeWeather = true
        ..setNewLocationData(null, 39.9042, 116.4074);

      // 1. 启动第一次在途异步天气抓取
      final fetchFuture1 = controller.fetchWeatherForNewNote();
      expect(controller.isFetchingWeather, isTrue);

      // 2. 用户在弹窗中取消勾选天气，作废第一次抓取
      controller.removeNewWeather();
      expect(controller.includeWeather, isFalse);
      expect(
        controller.isFetchingWeather,
        isFalse,
        reason: 'isFetchingWeather 在 removeNewWeather() 后立即为 false',
      );

      // 3. 用户重新勾选天气并重新发起第二次抓取
      controller.includeWeather = true;
      final fetchFuture2 = controller.fetchWeatherForNewNote();
      expect(controller.isFetchingWeather, isTrue);

      // 4. 旧的第一次天气请求延迟到达并完成 (hasData = false)
      completer1.complete();
      await fetchFuture1;

      // 验证：旧请求返回因 epoch 不匹配直接退出，绝不会将第二次抓取的在途标志误设为 false，也不会触发错误回调
      expect(controller.isFetchingWeather, isTrue);
      expect(controller.includeWeather, isTrue);
      expect(emptyCallbackCount, 0);

      // 5. 第二次天气请求完成
      completer2.complete();
      await fetchFuture2;

      // 验证：第二次请求正常收尾（hasData 为 false 时置 includeWeather 为 false 并触发回调）
      expect(controller.isFetchingWeather, isFalse);
      expect(controller.includeWeather, isFalse);
      expect(emptyCallbackCount, 1);
    });

    test(
        '在途天气抓取期间调用 removeNewWeather 立即置 false，旧请求迟到完成 (hasData = false) 不触发回调或改写状态',
        () async {
      final completer = Completer<void>();
      final weaService = _MockWeatherServiceForRace(completer, null, false);
      var emptyCallbackCalled = false;
      final controller = AddNoteController(
        context: FakeBuildContext(),
        onWeatherFetchEmpty: () => emptyCallbackCalled = true,
      )
        ..updateServices(weaService: weaService)
        ..includeWeather = true
        ..setNewLocationData(null, 39.9042, 116.4074);

      final fetchFuture = controller.fetchWeatherForNewNote();
      expect(controller.isFetchingWeather, isTrue);

      controller.removeNewWeather();
      expect(controller.includeWeather, isFalse);
      expect(
        controller.isFetchingWeather,
        isFalse,
        reason: 'isFetchingWeather 在 removeNewWeather() 后立即为 false',
      );

      // 模拟用户后续重新开启 includeWeather
      controller.includeWeather = true;

      // 旧请求迟到完成 (hasData = false)
      completer.complete();
      await fetchFuture;

      expect(
        emptyCallbackCalled,
        isFalse,
        reason: '旧的迟到完成因 epoch 不匹配直接退出，绝不触发 onWeatherFetchEmpty',
      );
      expect(
        controller.includeWeather,
        isTrue,
        reason: '旧的迟到完成不应改写用户的当前状态',
      );
      expect(controller.isFetchingWeather, isFalse);
    });

    test('在途天气抓取不会因用户移除位置 (removeNewLocation) 被意外中断或影响状态', () async {
      final completer = Completer<void>();
      final weaService = _MockWeatherServiceForRace(completer);
      final controller = AddNoteController(context: FakeBuildContext())
        ..updateServices(weaService: weaService)
        ..includeWeather = true
        ..includeLocation = true
        ..setNewLocationData('北京市', 39.9042, 116.4074);

      final fetchFuture = controller.fetchWeatherForNewNote();
      expect(controller.isFetchingWeather, isTrue);

      // 用户主动移除位置：验证它将 includeLocation 置为 false，但不会意外影响在途天气状态
      controller.removeNewLocation();
      expect(controller.includeLocation, isFalse);
      expect(
        controller.isFetchingWeather,
        isTrue,
        reason: 'removeNewLocation 不会意外影响在途天气状态',
      );
      expect(controller.includeWeather, isTrue);

      completer.complete();
      await fetchFuture;

      expect(controller.isFetchingWeather, isFalse);
      expect(controller.includeWeather, isTrue);
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

    test(
        'ensureTagExists binds databaseService when initially null and returns existing tag',
        () async {
      final db = _CountingDatabaseService();
      final controller = AddNoteController(context: FakeBuildContext());
      expect(controller.databaseService, isNull);

      final tagId = await controller.ensureTagExists(db, '每日一言', '💭');
      expect(tagId, equals('default_hitokoto'));
      expect(controller.databaseService, equals(db));
      expect(controller.allCategoriesCache, isNotNull);
      expect(db.getTagsCallCount, equals(1));
    });

    test(
        'ensureTagExists returns null when passed db does not match controller databaseService',
        () async {
      final db1 = _CountingDatabaseService();
      final db2 = _CountingDatabaseService();
      final controller = AddNoteController(context: FakeBuildContext())
        ..updateServices(dbService: db1);

      // 传入与 controller 绑定的 databaseService 不一致的 db2
      final tagId = await controller.ensureTagExists(db2, '每日一言', '💭');
      expect(tagId, isNull);
      expect(controller.allCategoriesCache, isNull);
      expect(db2.getTagsCallCount, equals(0));
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

class _MockLocationServiceForRace extends ChangeNotifier
    implements LocationService {
  _MockLocationServiceForRace(this.completer);

  final Completer<Position?> completer;

  @override
  bool get hasLocationPermission => true;

  @override
  bool get isLocationServiceEnabled => true;

  @override
  Position? get currentPosition => null;

  @override
  String? get currentPoiName => '自动定位地名';

  @override
  String getFormattedLocation() => '中国,北京市,北京市,海淀区';

  @override
  Future<Position?> getCurrentLocation({
    bool highAccuracy = false,
    bool skipPermissionRequest = false,
  }) =>
      completer.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockWeatherServiceForRace extends ChangeNotifier
    implements WeatherService {
  _MockWeatherServiceForRace(
    this.completer, [
    this.secondCompleter,
    this.hasData = true,
  ]);

  final Completer<void> completer;
  final Completer<void>? secondCompleter;
  @override
  final bool hasData;
  int _callCount = 0;

  @override
  Future<void> getWeatherData(
    double latitude,
    double longitude, {
    bool forceRefresh = false,
    Duration? timeout,
  }) {
    _callCount++;
    if (_callCount > 1 && secondCompleter != null) {
      return secondCompleter!.future;
    }
    return completer.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
