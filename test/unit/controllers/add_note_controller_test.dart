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
  group('AddNoteController Initialization & Hydration', () {
    test('Constructor with initialQuote handles non-display location markers',
        () {
      final quotePending = Quote(
        id: '1',
        content: 'Test',
        date: DateTime.now().toIso8601String(),
        location: LocationService.kAddressPending,
        latitude: 30.0,
        longitude: 120.0,
        weather: '晴',
      );

      final controllerPending = AddNoteController(
        context: FakeBuildContext(),
        initialQuote: quotePending,
      );

      expect(controllerPending.originalLocation, isNull);
      expect(controllerPending.originalLatitude, equals(30.0));
      expect(controllerPending.originalLongitude, equals(120.0));
      expect(controllerPending.includeLocation, isTrue);
      expect(controllerPending.includeWeather, isTrue);

      final quoteNormal = Quote(
        id: '2',
        content: 'Test 2',
        date: DateTime.now().toIso8601String(),
        location: '杭州市',
      );

      final controllerNormal = AddNoteController(
        context: FakeBuildContext(),
        initialQuote: quoteNormal,
      );

      expect(controllerNormal.originalLocation, equals('杭州市'));
      expect(controllerNormal.includeLocation, isTrue);
      expect(controllerNormal.includeWeather, isFalse);
    });

    test('hydrateFromQuote populates original metadata and toggles flags', () {
      final controller = AddNoteController(context: FakeBuildContext());

      final quote = Quote(
        id: '10',
        content: 'Hydrate test',
        date: DateTime.now().toIso8601String(),
        location: '上海市',
        latitude: 31.23,
        longitude: 121.47,
        poiName: '人民广场',
        weather: '多云',
        temperature: '22°C',
      );

      controller.hydrateFromQuote(quote);

      expect(controller.originalLocation, equals('上海市'));
      expect(controller.originalLatitude, equals(31.23));
      expect(controller.originalLongitude, equals(121.47));
      expect(controller.originalPoiName, equals('人民广场'));
      expect(controller.originalWeather, equals('多云'));
      expect(controller.originalTemperature, equals('22°C'));
      expect(controller.includeLocation, isTrue);
      expect(controller.includeWeather, isTrue);
    });
  });

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

    test('setIncludeLocation and setOriginalLocationData update state properly',
        () {
      final controller = AddNoteController(context: FakeBuildContext())
        ..setNewLocationData('北京市', 39.9, 116.4, poiName: '天安门');

      expect(controller.newLocation, '北京市');
      expect(controller.newLatitude, 39.9);
      expect(controller.newLongitude, 116.4);
      expect(controller.newPoiName, '天安门');

      controller.setIncludeLocation(false);

      expect(controller.includeLocation, isFalse);
      expect(controller.newLocation, isNull);
      expect(controller.newLatitude, isNull);

      controller.setOriginalLocationData('南京市', 32.0, 118.7, poiName: '新街口');
      expect(controller.originalLocation, '南京市');
      expect(controller.originalLatitude, 32.0);
      expect(controller.originalLongitude, 118.7);
      expect(controller.originalPoiName, '新街口');
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

    test('fetchLocationForNewNote 快速定位仅保留行政区与坐标，不自动附带 poiName', () async {
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

      expect(controller.newPoiName, isNull);
      expect(controller.newLatitude, 39.9042);
      expect(controller.newLongitude, 116.4074);
      expect(controller.newLocation, '中国,北京市,北京市,海淀区');
      expect(controller.isFetchingLocation, isFalse);
    });

    test('fetchLocationForNewNote 权限被拒时触发 onLocationPermissionDenied 回调',
        () async {
      var permissionDeniedCalled = false;
      final locService = _ConfigurableLocationService(hasPermission: false);
      final controller = AddNoteController(
        context: FakeBuildContext(),
        onLocationPermissionDenied: () => permissionDeniedCalled = true,
      )..updateServices(locService: locService);

      await controller.fetchLocationForNewNote();

      expect(permissionDeniedCalled, isTrue);
      expect(controller.includeLocation, isFalse);
      expect(controller.isFetchingLocation, isFalse);
    });

    test('fetchLocationForNewNote 抓取为空时触发 onLocationFetchEmpty 回调', () async {
      var emptyCalled = false;
      final locService = _ConfigurableLocationService(
        hasPermission: true,
        overridePositionResult: true,
        positionResult: null,
      );
      final controller = AddNoteController(
        context: FakeBuildContext(),
        onLocationFetchEmpty: () => emptyCalled = true,
      )..updateServices(locService: locService);

      await controller.fetchLocationForNewNote();

      expect(emptyCalled, isTrue);
      expect(controller.includeLocation, isFalse);
      expect(controller.isFetchingLocation, isFalse);
    });

    test('fetchLocationForNewNote 抛出异常时触发 onLocationError 回调', () async {
      String? errorMessage;
      final locService = _ConfigurableLocationService(
        hasPermission: true,
        shouldThrow: Exception('GPS timeout'),
      );
      final controller = AddNoteController(
        context: FakeBuildContext(),
        onLocationError: (msg) => errorMessage = msg,
      )..updateServices(locService: locService);

      await controller.fetchLocationForNewNote();

      expect(errorMessage, contains('GPS timeout'));
      expect(controller.includeLocation, isFalse);
      expect(controller.isFetchingLocation, isFalse);
    });

    test(
        'in-flight fetchLocationForNewNote handles non-exception Error correctly',
        () async {
      String? errorMessage;
      final locService = _ConfigurableLocationService(
        hasPermission: true,
        shouldThrow: StateError('State error in location service'),
      );
      final controller = AddNoteController(
        context: FakeBuildContext(),
        onLocationError: (msg) => errorMessage = msg,
      )..updateServices(locService: locService);

      await controller.fetchLocationForNewNote();

      expect(errorMessage, contains('State error in location service'));
      expect(controller.includeLocation, isFalse);
    });

    test('fetchWeatherForNewNote 缺乏坐标时触发 onWeatherMissingCoordinates 回调',
        () async {
      var missingCoordsCalled = false;
      final controller = AddNoteController(
        context: FakeBuildContext(),
        onWeatherMissingCoordinates: () => missingCoordsCalled = true,
      )..updateServices(weaService: _ConfigurableWeatherService());

      await controller.fetchWeatherForNewNote();

      expect(missingCoordsCalled, isTrue);
      expect(controller.includeWeather, isFalse);
      expect(controller.isFetchingWeather, isFalse);
    });

    test(
        'fetchWeatherForNewNote 缺乏 newLocation 时回退到 locationService.currentPosition',
        () async {
      final locService = _ConfigurableLocationService(
        hasPermission: true,
        currentPos: Position(
          latitude: 22.5,
          longitude: 114.0,
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        ),
      );
      final weaService = _ConfigurableWeatherService(hasData: true);

      final controller = AddNoteController(context: FakeBuildContext())
        ..updateServices(locService: locService, weaService: weaService);

      await controller.fetchWeatherForNewNote();

      expect(weaService.lastLat, 22.5);
      expect(weaService.lastLon, 114.0);
      expect(controller.isFetchingWeather, isFalse);
    });

    test('fetchWeatherForNewNote 抓取异常时触发 onWeatherFetchError 回调', () async {
      var errorCalled = false;
      final weaService = _ConfigurableWeatherService(
        shouldThrow: Exception('Network error'),
      );

      final controller = AddNoteController(
        context: FakeBuildContext(),
        onWeatherFetchError: () => errorCalled = true,
      )
        ..updateServices(weaService: weaService)
        ..setNewLocationData(null, 30.0, 120.0);

      await controller.fetchWeatherForNewNote();

      expect(errorCalled, isTrue);
      expect(controller.includeWeather, isFalse);
      expect(controller.isFetchingWeather, isFalse);
    });

    test('fetchWeatherForNewNote 捕获 Error 类型错误时降级并调用 onWeatherFetchError',
        () async {
      var errorCalled = false;
      final weaService = _ConfigurableWeatherService(
        shouldThrow: TypeError(),
      );

      final controller = AddNoteController(
        context: FakeBuildContext(),
        onWeatherFetchError: () => errorCalled = true,
      )
        ..updateServices(weaService: weaService)
        ..setNewLocationData(null, 30.0, 120.0);

      await controller.fetchWeatherForNewNote();

      expect(errorCalled, isTrue);
      expect(controller.includeWeather, isFalse);
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

  group('Hitokoto Helpers', () {
    test('getHitokotoTypeFromApiResponse returns type string if present', () {
      final controllerWithData = AddNoteController(
        context: FakeBuildContext(),
        hitokotoData: {'type': 'a', 'provider': 'hitokoto'},
      );
      expect(controllerWithData.getHitokotoTypeFromApiResponse(), equals('a'));

      final controllerEmpty = AddNoteController(context: FakeBuildContext());
      expect(controllerEmpty.getHitokotoTypeFromApiResponse(), isNull);
    });

    test('shouldApplyHitokotoSubtypeTag checks provider value correctly', () {
      final controllerNullProvider = AddNoteController(
        context: FakeBuildContext(),
        hitokotoData: {},
      );
      expect(controllerNullProvider.shouldApplyHitokotoSubtypeTag(), isTrue);

      final controllerHitokoto = AddNoteController(
        context: FakeBuildContext(),
        hitokotoData: {'provider': 'hitokoto'},
      );
      expect(controllerHitokoto.shouldApplyHitokotoSubtypeTag(), isTrue);

      final controllerOther = AddNoteController(
        context: FakeBuildContext(),
        hitokotoData: {'provider': 'other_provider'},
      );
      expect(controllerOther.shouldApplyHitokotoSubtypeTag(), isFalse);
    });

    test(
        'convertHitokotoTypeToTagName and getIconForHitokotoType return expected mappings',
        () {
      final controller = AddNoteController(context: FakeBuildContext());

      expect(controller.convertHitokotoTypeToTagName('a'), equals('动画'));
      expect(
          controller.convertHitokotoTypeToTagName('unknown'), equals('其他一言'));

      expect(controller.getIconForHitokotoType('c'), equals('🎮'));
      expect(
          controller.getIconForHitokotoType('unknown'), equals('format_quote'));
    });
  });

  group('AddNoteController Tag Matching and Fallback', () {
    test('ensureTagExists performs case-insensitive name matching', () async {
      final db = _CountingDatabaseService();
      final controller = AddNoteController(context: FakeBuildContext())
        ..updateServices(dbService: db);

      // '动画' tag exists in db with id 'default_anime'
      final tagId = await controller.ensureTagExists(db, '动画', '🎬');
      expect(tagId, equals('default_anime'));
    });

    test(
        'ensureTagExists falls back to db.addTag if addTagWithId throws exception',
        () async {
      final db = _FailingAddTagWithIdDatabaseService();
      final controller = AddNoteController(context: FakeBuildContext())
        ..updateServices(dbService: db);

      final tagId = await controller.ensureTagExists(
        db,
        '自定义分类',
        '⭐',
        fixedId: 'fixed_custom',
      );

      expect(tagId, equals('自定义分类'));
      expect(db.addTagCalled, isTrue);
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

    test('ensureTagExists 新建固定 ID 标签后缓存条目与数据库读回的一致', () async {
      final db = _CountingDatabaseService();
      final controller = AddNoteController(context: FakeBuildContext())
        ..updateServices(dbService: db);

      // 抖机灵不预建，只在保存对应一言时按固定 ID 建出，走的正是缓存更新分支
      final tagId = await controller.ensureTagExists(
        db,
        '抖机灵',
        '😆',
        fixedId: DatabaseService.defaultTagIdJoke,
      );

      expect(tagId, DatabaseService.defaultTagIdJoke);
      expect(db.getTagsCallCount, equals(1), reason: '新建成功后就地更新缓存，不应再全量拉一次标签');

      final persisted = (await db.getTags())
          .firstWhere((tag) => tag.id == DatabaseService.defaultTagIdJoke);
      final cached = controller.allCategoriesCache!
          .where((tag) => tag.id == DatabaseService.defaultTagIdJoke)
          .toList();
      expect(cached, hasLength(1), reason: '同一个固定 ID 不能在缓存里出现两次');
      expect(cached.single.name, equals(persisted.name));
      expect(cached.single.isDefault, equals(persisted.isDefault),
          reason: '内置系统标签必须保留 is_default，否则会退化成可删可改的普通标签');
      expect(cached.single.iconName, equals(persisted.iconName));
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
    _tags[id] = NoteTag(
      id: id,
      name: name,
      // 镜像 database_tag_mixin.dart：内置系统标签写回 is_default，
      // iconName 为空时落成 '' 而不是 null
      isDefault: DatabaseService.systemTagIds.contains(id),
      iconName: iconName ?? '',
    );
  }

  @override
  Future<void> addTag(String name, {String? iconName}) async {
    final id = name;
    _tags[id] = NoteTag(id: id, name: name, iconName: iconName ?? '');
  }

  @override
  bool get isInitialized => true;
}

class _FailingAddTagWithIdDatabaseService extends DatabaseService {
  _FailingAddTagWithIdDatabaseService() : super.forTesting();

  bool addTagCalled = false;
  final Map<String, NoteTag> _tags = {};

  @override
  Future<List<NoteTag>> getTags() async {
    return _tags.values.toList();
  }

  @override
  Future<void> addTagWithId(String id, String name, {String? iconName}) async {
    throw Exception('Failed to add tag with fixed ID');
  }

  @override
  Future<void> addTag(String name, {String? iconName}) async {
    addTagCalled = true;
    _tags[name] = NoteTag(id: name, name: name, iconName: iconName ?? '');
  }

  @override
  bool get isInitialized => true;
}

class _ConfigurableLocationService extends ChangeNotifier
    implements LocationService {
  _ConfigurableLocationService({
    this.hasPermission = true,
    bool overridePositionResult = false,
    Position? positionResult,
    this.currentPos,
    this.shouldThrow,
  }) : positionResult =
            overridePositionResult ? positionResult : _FakePosition();

  final bool hasPermission;
  final Position? positionResult;
  final Position? currentPos;
  final Object? shouldThrow;

  @override
  bool get hasLocationPermission => hasPermission;

  @override
  Future<bool> requestLocationPermission() async => hasPermission;

  @override
  bool get isLocationServiceEnabled => true;

  @override
  Position? get currentPosition => currentPos;

  @override
  String? get currentPoiName => null;

  @override
  String getFormattedLocation() => '北京市';

  @override
  Future<Position?> getCurrentLocation({
    bool highAccuracy = false,
    bool skipPermissionRequest = false,
  }) async {
    if (shouldThrow != null) {
      throw shouldThrow!;
    }
    return positionResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePosition extends Fake implements Position {
  _FakePosition();
  @override
  double get latitude => 39.9;
  @override
  double get longitude => 116.4;
}

class _ConfigurableWeatherService extends ChangeNotifier
    implements WeatherService {
  _ConfigurableWeatherService({
    this.hasData = false,
    this.shouldThrow,
  });

  @override
  final bool hasData;
  final Object? shouldThrow;

  double? lastLat;
  double? lastLon;

  @override
  Future<void> getWeatherData(
    double latitude,
    double longitude, {
    bool forceRefresh = false,
    Duration? timeout,
  }) async {
    if (shouldThrow != null) {
      throw shouldThrow!;
    }
    lastLat = latitude;
    lastLon = longitude;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
