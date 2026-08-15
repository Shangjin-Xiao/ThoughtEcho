import 'dart:async';
import 'package:flutter/material.dart';

import '../models/note_tag.dart';
import '../models/quote_model.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../utils/app_logger.dart';
import '../utils/location_weather_helper.dart';

class AddNoteController extends ChangeNotifier {
  final BuildContext context;
  final Quote? initialQuote;
  final Map<String, dynamic>? hitokotoData;

  LocationService? locationService;
  WeatherService? weatherService;
  DatabaseService? databaseService;

  // 位置和天气相关
  bool includeLocation = false;
  bool includeWeather = false;

  // 保存原始笔记的位置和天气信息（用于编辑模式）
  String? originalLocation;
  double? originalLatitude;
  double? originalLongitude;
  String? originalWeather;
  String? originalTemperature;

  // 新建笔记时的实时位置信息
  String? newLocation;
  double? newLatitude;
  double? newLongitude;

  // 位置/天气后台获取中状态（自动附加偏好触发）
  bool isFetchingLocation = false;
  bool isFetchingWeather = false;

  /// 是否有任何元数据正在后台获取中
  bool get isFetchingMetadata => isFetchingLocation || isFetchingWeather;

  /// 「预约」自动附加：抓取真正开始之前就把标志立起来。
  ///
  /// 保存流程靠这两个标志决定要不要转圈等待。只要中间出现一段标志为 false 的空窗
  /// （等待延迟启动、位置抓完但天气还没开始），这期间点保存就会以为元数据已经齐了，
  /// 直接落库，把用户在偏好里要的位置/天气丢掉。
  void armAutoMetadataFetch({required bool location, required bool weather}) {
    if (isFetchingLocation == location && isFetchingWeather == weather) return;
    isFetchingLocation = location;
    isFetchingWeather = weather;
    notifyListeners();
  }

  /// 预约的位置抓取不会发生了（服务缺失、用户移除），放掉标志。
  void clearPendingLocationFetch() {
    if (!isFetchingLocation) return;
    isFetchingLocation = false;
    notifyListeners();
  }

  /// 预约的天气抓取不会发生了（服务缺失、没有坐标、用户移除），放掉标志，
  /// 否则保存会一直转到超时。
  void clearPendingWeatherFetch() {
    if (!isFetchingWeather) return;
    isFetchingWeather = false;
    notifyListeners();
  }

  // 一言标签加载状态
  bool isLoadingHitokotoTags = false;

  // 分类选择
  NoteTag? selectedCategory;

  // 标签名称到固定分类 ID 的映射，避免O(N)遍历
  static const Map<String, String> hitokotoTagNameToCategoryIdMap = {
    '动画': DatabaseService.defaultTagIdAnime,
    '漫画': DatabaseService.defaultTagIdComic,
    '游戏': DatabaseService.defaultTagIdGame,
    '文学': DatabaseService.defaultTagIdNovel,
    '原创': DatabaseService.defaultTagIdOriginal,
    '来自网络': DatabaseService.defaultTagIdInternet,
    '其他': DatabaseService.defaultTagIdOther,
    '影视': DatabaseService.defaultTagIdMovie,
    '诗词': DatabaseService.defaultTagIdPoem,
    '网易云': DatabaseService.defaultTagIdMusic,
    '哲学': DatabaseService.defaultTagIdPhilosophy,
    '抖机灵': DatabaseService.defaultTagIdJoke,
  };

  // 一言类型到固定分类 ID 的映射
  static const Map<String, String> hitokotoTypeToCategoryIdMap = {
    'a': DatabaseService.defaultTagIdAnime, // 动画
    'b': DatabaseService.defaultTagIdComic, // 漫画
    'c': DatabaseService.defaultTagIdGame, // 游戏
    'd': DatabaseService.defaultTagIdNovel, // 文学
    'e': DatabaseService.defaultTagIdOriginal, // 原创
    'f': DatabaseService.defaultTagIdInternet, // 来自网络
    'g': DatabaseService.defaultTagIdOther, // 其他
    'h': DatabaseService.defaultTagIdMovie, // 影视
    'i': DatabaseService.defaultTagIdPoem, // 诗词
    'j': DatabaseService.defaultTagIdMusic, // 网易云
    'k': DatabaseService.defaultTagIdPhilosophy, // 哲学
    'l': DatabaseService.defaultTagIdJoke, // 抖机灵
  };

  // 一言类型代码到标签名称的映射
  static const Map<String, String> hitokotoTypeToTagNameMap = {
    'a': '动画',
    'b': '漫画',
    'c': '游戏',
    'd': '文学',
    'e': '原创',
    'f': '来自网络',
    'g': '其他',
    'h': '影视',
    'i': '诗词',
    'j': '网易云',
    'k': '哲学',
    'l': '抖机灵',
  };

  // 一言类型代码到对应图标的映射
  static const Map<String, String> hitokotoTypeToIconMap = {
    'a': '🎬',
    'b': '📚',
    'c': '🎮',
    'd': '📖',
    'e': '✨',
    'f': '🌐',
    'g': '📦',
    'h': '🎞️',
    'i': '🪶',
    'j': '🎧',
    'k': '🤔',
    'l': '😄',
  };

  // 缓存所有标签，避免重复查询
  List<NoteTag>? allCategoriesCache;

  // 外界可以通过回调或直接获取 selectedTagIds
  final List<String> _selectedTagIds;
  List<String> get selectedTagIds => _selectedTagIds;

  // 将回调传递给外界
  final void Function(String)? onLocationError;
  final void Function()? onLocationFetched;
  final void Function()? onLocationPermissionDenied;
  final void Function()? onLocationFetchEmpty;
  final void Function()? onWeatherFetchEmpty;
  final void Function()? onWeatherMissingCoordinates;
  final void Function()? onWeatherFetchError;

  bool _isDisposed = false;

  AddNoteController({
    required this.context,
    this.initialQuote,
    this.hitokotoData,
    List<String>? initialTagIds,
    this.onLocationError,
    this.onLocationFetched,
    this.onLocationPermissionDenied,
    this.onLocationFetchEmpty,
    this.onWeatherFetchEmpty,
    this.onWeatherMissingCoordinates,
    this.onWeatherFetchError,
  }) : _selectedTagIds = initialTagIds ?? [] {
    if (initialQuote != null) {
      // kAddressPending / kAddressFailed 等内部标记视为「只有坐标无地址」，
      // 对 originalLocation 赋 null，让 hasOnlyCoordinates 判断正确。
      final rawLoc = initialQuote!.location;
      originalLocation =
          LocationService.isNonDisplayMarker(rawLoc) ? null : rawLoc;
      originalLatitude = initialQuote!.latitude;
      originalLongitude = initialQuote!.longitude;
      originalWeather = initialQuote!.weather;
      originalTemperature = initialQuote!.temperature;

      includeLocation = initialQuote!.location != null ||
          (initialQuote!.latitude != null && initialQuote!.longitude != null);
      includeWeather = initialQuote!.weather != null;
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  void updateServices({
    LocationService? locService,
    WeatherService? weaService,
    DatabaseService? dbService,
  }) {
    locationService = locService ?? locationService;
    weatherService = weaService ?? weatherService;
    databaseService = dbService ?? databaseService;
  }

  void _clearNewLocation() {
    newLocation = null;
    newLatitude = null;
    newLongitude = null;
  }

  void _clearOriginalLocation() {
    originalLocation = null;
    originalLatitude = null;
    originalLongitude = null;
  }

  void removeNewLocation() {
    includeLocation = false;
    _clearNewLocation();
    // 用户主动移除，在途/预约的抓取就没有意义了，别让保存继续等它。
    isFetchingLocation = false;
    notifyListeners();
  }

  /// 新建笔记时用户主动移除天气。
  void removeNewWeather() {
    includeWeather = false;
    isFetchingWeather = false;
    notifyListeners();
  }

  void removeOriginalLocation() {
    includeLocation = false;
    _clearOriginalLocation();
    notifyListeners();
  }

  void hydrateFromQuote(Quote quote) {
    final rawLoc = quote.location;
    originalLocation =
        LocationService.isNonDisplayMarker(rawLoc) ? null : rawLoc;
    originalLatitude = quote.latitude;
    originalLongitude = quote.longitude;
    originalWeather = quote.weather;
    originalTemperature = quote.temperature;

    includeLocation = quote.location != null ||
        (quote.latitude != null && quote.longitude != null);
    includeWeather = quote.weather != null;
    notifyListeners();
  }

  void setIncludeLocation(bool value) {
    includeLocation = value;
    if (!value) {
      _clearNewLocation();
    }
    notifyListeners();
  }

  void setIncludeWeather(bool value) {
    includeWeather = value;
    notifyListeners();
  }

  void setNewLocationData(String? location, double? lat, double? lon) {
    newLocation = location;
    newLatitude = lat;
    newLongitude = lon;
    notifyListeners();
  }

  void setOriginalLocationData(String? location, double? lat, double? lon) {
    originalLocation = location;
    originalLatitude = lat;
    originalLongitude = lon;
    notifyListeners();
  }

  /// 获取新建笔记的实时位置
  Future<void> fetchLocationForNewNote() async {
    final locService = locationService;
    if (locService == null) {
      // 服务拿不到就抓不了，按失败处理：既放掉标志（保存正等着它），
      // 也取消这次附加，别让笔记带着「已附加位置」的勾却什么都没有。
      includeLocation = false;
      _clearNewLocation();
      isFetchingLocation = false;
      notifyListeners();
      return;
    }

    isFetchingLocation = true;
    notifyListeners();

    // 检查并请求权限
    final hasPermission =
        await LocationWeatherHelper.ensureLocationPermission(locService);
    if (_isDisposed) return;
    if (!hasPermission) {
      includeLocation = false;
      _clearNewLocation();
      isFetchingLocation = false;
      notifyListeners();
      onLocationPermissionDenied?.call();
      return;
    }

    try {
      final snapshot = await LocationWeatherHelper.fetchLocation(locService);
      if (_isDisposed) return;
      if (snapshot != null) {
        newLatitude = snapshot.position.latitude;
        newLongitude = snapshot.position.longitude;
        newLocation = snapshot.location.isNotEmpty ? snapshot.location : null;
        isFetchingLocation = false;
        notifyListeners();
        onLocationFetched?.call();
      } else {
        includeLocation = false;
        _clearNewLocation();
        isFetchingLocation = false;
        notifyListeners();
        onLocationFetchEmpty?.call();
      }
    } catch (e) {
      logDebug('获取位置失败: $e');
      if (_isDisposed) return;
      includeLocation = false;
      _clearNewLocation();
      isFetchingLocation = false;
      notifyListeners();
      onLocationError?.call(e.toString());
    }
  }

  /// 获取新建笔记的天气信息
  Future<void> fetchWeatherForNewNote() async {
    final weaService = weatherService;
    final locService = locationService;
    if (weaService == null) {
      // 同上：抓不了就别让 WeatherService 的旧数据在保存时冒充这条笔记的天气。
      includeWeather = false;
      isFetchingWeather = false;
      notifyListeners();
      return;
    }

    isFetchingWeather = true;
    notifyListeners();

    try {
      double? lat = newLatitude;
      double? lon = newLongitude;

      if (lat == null || lon == null) {
        lat = locService?.currentPosition?.latitude;
        lon = locService?.currentPosition?.longitude;
      }

      if (lat == null || lon == null) {
        includeWeather = false;
        isFetchingWeather = false;
        notifyListeners();
        onWeatherMissingCoordinates?.call();
        return;
      }

      await weaService.getWeatherData(lat, lon);
      if (_isDisposed) return;

      if (!weaService.hasData) {
        includeWeather = false;
        isFetchingWeather = false;
        notifyListeners();
        onWeatherFetchEmpty?.call();
        return;
      }

      isFetchingWeather = false;
      notifyListeners();
    } catch (e) {
      logDebug('获取天气失败: $e');
      if (_isDisposed) return;
      includeWeather = false;
      isFetchingWeather = false;
      notifyListeners();
      onWeatherFetchError?.call();
    }
  }

  // 从hitokotoData中获取一言类型
  String? getHitokotoTypeFromApiResponse() {
    if (hitokotoData != null && hitokotoData!.containsKey('type')) {
      return hitokotoData!['type'].toString();
    }
    return null;
  }

  bool shouldApplyHitokotoSubtypeTag() {
    final provider = hitokotoData?['provider']?.toString();
    if (provider == null || provider.trim().isEmpty) {
      return true;
    }
    return provider == ApiService.hitokotoProvider;
  }

  // 将一言API的类型代码转换为可读标签名称
  String convertHitokotoTypeToTagName(String typeCode) {
    return hitokotoTypeToTagNameMap[typeCode] ?? '其他一言';
  }

  // 为不同类型的一言选择对应的图标
  String getIconForHitokotoType(String typeCode) {
    return hitokotoTypeToIconMap[typeCode] ?? 'format_quote';
  }

  // 添加默认的一言相关标签
  Future<void> addDefaultHitokotoTagsAsync(
      void Function(NoteTag?) onCategoryUpdated) async {
    isLoadingHitokotoTags = true;
    notifyListeners();

    try {
      final db = databaseService;
      if (db == null) {
        logDebug('未找到DatabaseService，跳过默认标签添加');
        return;
      }

      final List<Map<String, String>> tagsToEnsure = [];

      tagsToEnsure.add({
        'name': '每日一言',
        'icon': '💭',
        'fixedId': DatabaseService.defaultTagIdHitokoto,
      });

      String? hitokotoType;
      if (shouldApplyHitokotoSubtypeTag()) {
        hitokotoType = getHitokotoTypeFromApiResponse();
        if (hitokotoType != null && hitokotoType.isNotEmpty) {
          String tagName = convertHitokotoTypeToTagName(hitokotoType);
          String iconName = getIconForHitokotoType(hitokotoType);
          String? fixedId;

          if (hitokotoTypeToCategoryIdMap.containsKey(hitokotoType)) {
            fixedId = hitokotoTypeToCategoryIdMap[hitokotoType];
          }

          tagsToEnsure.add({
            'name': tagName,
            'icon': iconName,
            if (fixedId != null) 'fixedId': fixedId,
          });
        }
      }

      final List<String> tagIds = [];
      String? subtypeTagId;
      for (final tagInfo in tagsToEnsure) {
        final tagId = await ensureTagExists(
          db,
          tagInfo['name']!,
          tagInfo['icon']!,
          fixedId: tagInfo['fixedId'],
        );
        if (_isDisposed) return;
        if (tagId != null) {
          tagIds.add(tagId);
          if (tagInfo['fixedId'] != null &&
              tagInfo['fixedId'] != DatabaseService.defaultTagIdHitokoto) {
            subtypeTagId = tagId;
          }
        }
      }

      for (final tagId in tagIds) {
        if (!_selectedTagIds.contains(tagId)) {
          _selectedTagIds.add(tagId);
        }
      }

      if (subtypeTagId != null) {
        final category = await db.getTagById(subtypeTagId);
        if (_isDisposed) return;
        selectedCategory = category;
        onCategoryUpdated(category);
      }
    } catch (e) {
      logDebug('添加默认标签失败: $e');
    } finally {
      if (!_isDisposed) {
        isLoadingHitokotoTags = false;
        notifyListeners();
      }
    }
  }

  // 确保标签存在
  Future<String?> ensureTagExists(
    DatabaseService db,
    String name,
    String iconName, {
    String? fixedId,
  }) async {
    try {
      if (fixedId == null) {
        fixedId = hitokotoTagNameToCategoryIdMap[name];
        if (name == '每日一言') {
          fixedId = DatabaseService.defaultTagIdHitokoto;
        }
      }

      if (fixedId != null) {
        final category = await db.getTagById(fixedId);
        if (_isDisposed) return null;
        if (category != null) {
          return category.id;
        }
      }

      if (allCategoriesCache == null) {
        final fetchedCategories = await db.getTags();
        if (_isDisposed) return null;
        allCategoriesCache = fetchedCategories;
      }
      final categories = allCategoriesCache!;

      final existingTag = categories.firstWhere(
        (tag) => tag.name.toLowerCase() == name.toLowerCase(),
        orElse: () => NoteTag(id: '', name: ''),
      );

      if (existingTag.id.isNotEmpty) {
        return existingTag.id;
      }

      if (fixedId != null) {
        try {
          await db.addTagWithId(fixedId, name, iconName: iconName);
          if (_isDisposed) return null;
          allCategoriesCache = null;
          return fixedId;
        } catch (e) {
          logDebug('使用固定ID创建标签失败: $e');
          if (_isDisposed) return null;
          await db.addTag(name, iconName: iconName);
          if (_isDisposed) return null;
        }
      } else {
        await db.addTag(name, iconName: iconName);
        if (_isDisposed) return null;
      }

      allCategoriesCache = null;
      final updatedCategories = await db.getTags();
      if (_isDisposed) return null;
      final newTag = updatedCategories.firstWhere(
        (tag) => tag.name.toLowerCase() == name.toLowerCase(),
        orElse: () => NoteTag(id: '', name: ''),
      );

      return newTag.id.isNotEmpty ? newTag.id : null;
    } catch (e) {
      logDebug('确保标签"$name"存在时出错: $e');
      return null;
    }
  }
}
