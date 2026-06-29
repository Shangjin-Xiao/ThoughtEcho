import 'dart:async';
import 'package:flutter/material.dart';

import '../models/note_category.dart';
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

  // 一言标签加载状态
  bool isLoadingHitokotoTags = false;

  // 分类选择
  NoteCategory? selectedCategory;

  // 一言类型到固定分类 ID 的映射
  static final Map<String, String> hitokotoTypeToCategoryIdMap = {
    'a': DatabaseService.defaultCategoryIdAnime, // 动画
    'b': DatabaseService.defaultCategoryIdComic, // 漫画
    'c': DatabaseService.defaultCategoryIdGame, // 游戏
    'd': DatabaseService.defaultCategoryIdNovel, // 文学
    'e': DatabaseService.defaultCategoryIdOriginal, // 原创
    'f': DatabaseService.defaultCategoryIdInternet, // 来自网络
    'g': DatabaseService.defaultCategoryIdOther, // 其他
    'h': DatabaseService.defaultCategoryIdMovie, // 影视
    'i': DatabaseService.defaultCategoryIdPoem, // 诗词
    'j': DatabaseService.defaultCategoryIdMusic, // 网易云
    'k': DatabaseService.defaultCategoryIdPhilosophy, // 哲学
    'l': DatabaseService.defaultCategoryIdJoke, // 抖机灵
  };

  // 缓存所有标签，避免重复查询
  List<NoteCategory>? allCategoriesCache;

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
      originalLocation = initialQuote!.location;
      originalLatitude = initialQuote!.latitude;
      originalLongitude = initialQuote!.longitude;
      originalWeather = initialQuote!.weather;
      originalTemperature = initialQuote!.temperature;

      includeLocation = initialQuote!.location != null ||
          (initialQuote!.latitude != null && initialQuote!.longitude != null);
      includeWeather = initialQuote!.weather != null;
    }
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

  void setIncludeLocation(bool value) {
    includeLocation = value;
    if (!value) {
      newLocation = null;
      newLatitude = null;
      newLongitude = null;
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
    if (locService == null) return;

    // 检查并请求权限
    if (!await LocationWeatherHelper.ensureLocationPermission(locService)) {
      includeLocation = false;
      onLocationPermissionDenied?.call();
      notifyListeners();
      return;
    }

    try {
      final snapshot = await LocationWeatherHelper.fetchLocation(locService);
      if (snapshot != null) {
        newLatitude = snapshot.position.latitude;
        newLongitude = snapshot.position.longitude;
        newLocation = snapshot.location.isNotEmpty ? snapshot.location : null;
        onLocationFetched?.call();
        notifyListeners();
      } else {
        includeLocation = false;
        onLocationFetchEmpty?.call();
        notifyListeners();
      }
    } catch (e) {
      logDebug('获取位置失败: $e');
      includeLocation = false;
      onLocationError?.call(e.toString());
      notifyListeners();
    }
  }

  /// 获取新建笔记的天气信息
  Future<void> fetchWeatherForNewNote() async {
    final weaService = weatherService;
    final locService = locationService;
    if (weaService == null) return;

    try {
      double? lat = newLatitude;
      double? lon = newLongitude;

      if (lat == null || lon == null) {
        lat = locService?.currentPosition?.latitude;
        lon = locService?.currentPosition?.longitude;
      }

      if (lat == null || lon == null) {
        includeWeather = false;
        onWeatherMissingCoordinates?.call();
        notifyListeners();
        return;
      }

      await weaService.getWeatherData(lat, lon);

      if (!weaService.hasData) {
        includeWeather = false;
        onWeatherFetchEmpty?.call();
        notifyListeners();
      }
    } catch (e) {
      logDebug('获取天气失败: $e');
      includeWeather = false;
      onWeatherFetchError?.call();
      notifyListeners();
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
    const Map<String, String> typeMap = {
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
    return typeMap[typeCode] ?? '其他一言';
  }

  // 为不同类型的一言选择对应的图标
  String getIconForHitokotoType(String typeCode) {
    const Map<String, String> iconMap = {
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
    return iconMap[typeCode] ?? 'format_quote';
  }

  // 添加默认的一言相关标签
  Future<void> addDefaultHitokotoTagsAsync(void Function(NoteCategory?) onCategoryUpdated) async {
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
        'fixedId': DatabaseService.defaultCategoryIdHitokoto,
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
      for (final tagInfo in tagsToEnsure) {
        final tagId = await ensureTagExists(
          db,
          tagInfo['name']!,
          tagInfo['icon']!,
          fixedId: tagInfo['fixedId'],
        );
        if (tagId != null) {
          tagIds.add(tagId);
        }
      }

      for (final tagId in tagIds) {
        if (!_selectedTagIds.contains(tagId)) {
          _selectedTagIds.add(tagId);
        }
      }

      if (hitokotoType != null && hitokotoTypeToCategoryIdMap.containsKey(hitokotoType)) {
        final categoryId = hitokotoTypeToCategoryIdMap[hitokotoType];
        final category = await db.getCategoryById(categoryId!);
        selectedCategory = category;
        onCategoryUpdated(category);
      }
    } catch (e) {
      logDebug('添加默认标签失败: $e');
    } finally {
      isLoadingHitokotoTags = false;
      notifyListeners();
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
        for (var entry in hitokotoTypeToCategoryIdMap.entries) {
          if (convertHitokotoTypeToTagName(entry.key) == name) {
            fixedId = entry.value;
            break;
          }
        }
        if (name == '每日一言') {
          fixedId = DatabaseService.defaultCategoryIdHitokoto;
        }
      }

      if (fixedId != null) {
        final category = await db.getCategoryById(fixedId);
        if (category != null) {
          return category.id;
        }
      }

      allCategoriesCache ??= await db.getCategories();
      final categories = allCategoriesCache!;

      final existingTag = categories.firstWhere(
        (tag) => tag.name.toLowerCase() == name.toLowerCase(),
        orElse: () => NoteCategory(id: '', name: ''),
      );

      if (existingTag.id.isNotEmpty) {
        return existingTag.id;
      }

      if (fixedId != null) {
        try {
          await db.addCategoryWithId(fixedId, name, iconName: iconName);
          allCategoriesCache = null;
          return fixedId;
        } catch (e) {
          logDebug('使用固定ID创建标签失败: $e');
          await db.addCategory(name, iconName: iconName);
        }
      } else {
        await db.addCategory(name, iconName: iconName);
      }

      allCategoriesCache = null;
      final updatedCategories = await db.getCategories();
      final newTag = updatedCategories.firstWhere(
        (tag) => tag.name.toLowerCase() == name.toLowerCase(),
        orElse: () => NoteCategory(id: '', name: ''),
      );

      return newTag.id.isNotEmpty ? newTag.id : null;
    } catch (e) {
      logDebug('确保标签"$name"存在时出错: $e');
      return null;
    }
  }
}
