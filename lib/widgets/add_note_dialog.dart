import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import '../gen_l10n/app_localizations.dart';
import '../models/note_category.dart';
import '../models/quote_model.dart';
import '../services/database_service.dart';
import '../services/location_service.dart';
import '../services/local_geocoding_service.dart';
import '../services/weather_service.dart';
import '../utils/time_utils.dart'; // 导入时间工具类
import '../theme/app_theme.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter_markdown/flutter_markdown.dart'; // 导入 markdown 库
import '../utils/color_utils.dart'; // Import color_utils
import 'accessible_color_grid.dart'; // Import the new accessible color grid
import 'add_note_ai_menu.dart'; // 导入 AI 菜单组件
import '../pages/note_full_editor_page.dart'; // 导入全屏富文本编辑器
import 'package:thoughtecho/utils/app_logger.dart';
import '../constants/app_constants.dart';
import 'add_note_dialog_parts.dart'; // 导入拆分的组件
import '../utils/feature_guide_helper.dart';
import '../services/settings_service.dart';
import '../utils/icon_utils.dart';
import '../main.dart'; // 导入 main.dart 以访问全局 navigatorKey

class AddNoteDialog extends StatefulWidget {
  final Quote? initialQuote; // 如果是编辑笔记，则传入初始值
  final String? prefilledContent; // 预填充的内容
  final String? prefilledAuthor; // 预填充的作者
  final String? prefilledWork; // 预填充的作品
  final Map<String, dynamic>? hitokotoData; // 添加一言API返回的完整数据
  final List<NoteCategory> tags;
  final Function(Quote)? onSave; // 保存后的回调

  const AddNoteDialog({
    super.key,
    this.initialQuote,
    this.prefilledContent,
    this.prefilledAuthor,
    this.prefilledWork,
    this.hitokotoData,
    required this.tags,
    this.onSave,
  });

  @override
  State<AddNoteDialog> createState() => _AddNoteDialogState();
}

class _AddNoteDialogState extends State<AddNoteDialog> {
  late TextEditingController _contentController;
  late TextEditingController _authorController;
  late TextEditingController _workController;
  final GlobalKey _fullscreenButtonKey = GlobalKey();
  final GlobalKey _tagGuideKey = GlobalKey(); // 标签功能引导 Key
  final List<String> _selectedTagIds = [];
  String? _aiSummary;
  Quote? _fullInitialQuote;
  bool _isLoadingFullQuote = false;
  final ValueNotifier<bool> _isSaving = ValueNotifier(false);

  // 优化：内部维护标签列表，支持动态更新
  List<NoteCategory> _availableTags = [];
  DatabaseService? _databaseService;

  // 分类选择
  NoteCategory? _selectedCategory;

  // 位置和天气相关
  bool _includeLocation = false;
  bool _includeWeather = false;

  // 保存原始笔记的位置和天气信息（用于编辑模式）
  String? _originalLocation;
  double? _originalLatitude;
  double? _originalLongitude;
  String? _originalWeather;
  String? _originalTemperature;

  // 新建笔记时的实时位置信息
  String? _newLocation;
  double? _newLatitude;
  double? _newLongitude;
  // 颜色选择
  String? _selectedColorHex;

  // 标签搜索控制器
  final TextEditingController _tagSearchController = TextEditingController();

  // 性能优化：延迟请求焦点，避免与 BottomSheet 动画竞争
  final FocusNode _contentFocusNode = FocusNode();

  // 性能优化：缓存Provider引用，避免重复查找
  LocationService? _cachedLocationService;
  WeatherService? _cachedWeatherService;

  // 搜索防抖和过滤缓存
  Timer? _searchDebounceTimer;
  List<NoteCategory> _filteredTags = [];
  String _lastSearchQuery = '';

  // 数据库监听防抖
  Timer? _dbChangeDebounceTimer;

  // 一言标签加载状态
  bool _isLoadingHitokotoTags = false;

  // AI推荐标签相关状态
  // 预留：后续接入本地 embedding/标签推荐时使用

  // 优化：缓存过滤结果，避免重复计算
  final Map<String, List<NoteCategory>> _filterCache = {};

  T? _readServiceOrNull<T>(BuildContext context) {
    try {
      return Provider.of<T>(context, listen: false);
    } catch (_) {
      return null;
    }
  }

  // 一言类型到固定分类 ID 的映射
  static final Map<String, String> _hitokotoTypeToCategoryIdMap = {
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

  @override
  void initState() {
    super.initState();

    // 初始化控制器
    _contentController = TextEditingController(
      text: widget.initialQuote?.content ?? widget.prefilledContent ?? '',
    );

    _authorController = TextEditingController(
      text: widget.initialQuote?.sourceAuthor ?? widget.prefilledAuthor ?? '',
    );

    _workController = TextEditingController(
      text: widget.initialQuote?.sourceWork ?? widget.prefilledWork ?? '',
    );

    // 优化：初始化内部标签列表
    _availableTags = List.from(widget.tags);
    _filteredTags = _availableTags;
    _lastSearchQuery = '';

    // 优化：完全延迟所有服务初始化和数据库监听器，避免阻塞首次绘制
    // 使用 postFrameCallback + delay 确保首帧渲染完成后再执行重量级操作
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // 延迟 300ms 执行服务初始化和位置/天气获取，避免与动画竞争
      Future.delayed(const Duration(milliseconds: 300), () async {
        if (!mounted) return;

        _cachedLocationService = _readServiceOrNull<LocationService>(context);
        _cachedWeatherService = _readServiceOrNull<WeatherService>(context);
        _databaseService = _readServiceOrNull<DatabaseService>(context);

        // 新建笔记时，读取用户偏好并自动勾选位置/天气
        if (widget.initialQuote == null) {
          final settingsService = _readServiceOrNull<SettingsService>(context);
          if (settingsService != null) {
            final autoLocation = settingsService.autoAttachLocation;
            final autoWeather = settingsService.autoAttachWeather;

            if (autoLocation || autoWeather) {
              if (mounted) {
                setState(() {
                  if (autoLocation) {
                    _includeLocation = true;
                  }
                  if (autoWeather) {
                    _includeWeather = true;
                  }
                });
              }

              // 如果自动勾选了位置，获取位置；天气需要位置坐标，所以在位置获取后处理
              if (autoLocation) {
                await _fetchLocationForNewNote();
                // 位置获取后再获取天气
                if (autoWeather &&
                    _includeLocation &&
                    (_newLatitude != null ||
                        _cachedLocationService?.currentPosition != null)) {
                  _fetchWeatherForNewNote();
                } else if (autoWeather && !_includeLocation) {
                  // 位置获取失败，天气也无法获取，取消天气选中并提示
                  if (mounted) {
                    setState(() {
                      _includeWeather = false;
                    });
                    if (context.mounted) {
                      final l10n = AppLocalizations.of(context);
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(l10n.weatherFetchFailedTitle),
                          content: Text(l10n.locationAndWeatherUnavailable),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(l10n.iKnow),
                            ),
                          ],
                        ),
                      );
                    }
                  }
                }
              } else if (autoWeather) {
                // 没有勾选位置但勾选了天气，尝试用缓存的位置获取天气
                _fetchWeatherForNewNote();
              }
            }
          }
        }

        // 延迟注册监听器，避免初始化时触发不必要的查询
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted && _databaseService != null) {
            _databaseService!.addListener(_onDatabaseChanged);
          }
        });
      });
    });

    // 添加搜索防抖监听器
    _tagSearchController.addListener(_onSearchChanged);

    // 性能优化：延迟 Feature Guide 弹出，避免与键盘动画竞争
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 延迟 500ms 显示功能引导，确保 UI 稳定
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _showGuides();
        }
      });
    });

    // 如果是编辑已有笔记
    if (widget.initialQuote != null) {
      _aiSummary = widget.initialQuote!.aiAnalysis;
      _selectedColorHex = widget.initialQuote!.colorHex;

      // 保存原始的位置和天气信息
      _originalLocation = widget.initialQuote!.location;
      _originalLatitude = widget.initialQuote!.latitude;
      _originalLongitude = widget.initialQuote!.longitude;
      _originalWeather = widget.initialQuote!.weather;
      _originalTemperature = widget.initialQuote!.temperature;

      // 根据现有笔记的位置和天气信息设置复选框状态
      _includeLocation = widget.initialQuote!.location != null ||
          (widget.initialQuote!.latitude != null &&
              widget.initialQuote!.longitude != null);
      _includeWeather = widget.initialQuote!.weather != null;

      // 添加标签
      if (widget.initialQuote!.tagIds.isNotEmpty) {
        _selectedTagIds.addAll(widget.initialQuote!.tagIds);
      }

      // 如果源字段存在但分离的作者/作品字段为空，尝试解析
      if ((widget.initialQuote!.sourceAuthor == null ||
              widget.initialQuote!.sourceAuthor!.isEmpty) &&
          (widget.initialQuote!.sourceWork == null ||
              widget.initialQuote!.sourceWork!.isEmpty) &&
          widget.initialQuote!.source != null &&
          widget.initialQuote!.source!.isNotEmpty) {
        _parseSource(
          widget.initialQuote!.source!,
          _authorController,
          _workController,
        );
      }

      // 异步获取完整的 Quote 信息（防止列表页传递的是不完整的对象）
      _isLoadingFullQuote = true;
      _fetchFullQuote().whenComplete(() {
        if (mounted) {
          setState(() {
            _isLoadingFullQuote = false;
          });
        }
      });
    }

    // 优化：完全异步执行重量级操作，不阻塞 UI
    if (widget.hitokotoData != null) {
      // 使用 microtask 在下一个事件循环执行，比 Future.delayed 更快
      Future.microtask(() {
        if (mounted) {
          _addDefaultHitokotoTagsAsync();
        }
      });
    }
  }

  /// 异步获取完整的 Quote 对象
  Future<void> _fetchFullQuote() async {
    if (widget.initialQuote == null || widget.initialQuote!.id == null) return;

    // 延迟一点执行，确保 Provider 可用
    await Future.delayed(Duration.zero);
    if (!mounted) return;

    try {
      final db = Provider.of<DatabaseService>(context, listen: false);
      final fullQuote = await db.getQuoteById(widget.initialQuote!.id!);
      if (fullQuote != null && mounted) {
        setState(() {
          _fullInitialQuote = fullQuote;
          // 如果列表页传递的对象缺少 AI 分析等大字段，这里补全
          if (_aiSummary == null && fullQuote.aiAnalysis != null) {
            _aiSummary = fullQuote.aiAnalysis;
          }
        });
      }
    } catch (e) {
      logDebug('获取完整笔记详情失败: $e');
    }
  }

  // 优化：数据库变化监听回调 - 自动更新标签列表（带防抖）
  void _onDatabaseChanged() {
    if (!mounted || _databaseService == null) return;

    // 防抖：300ms 内的多次变化只触发一次更新
    _dbChangeDebounceTimer?.cancel();
    _dbChangeDebounceTimer = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted || _databaseService == null) return;

      try {
        // 重新获取最新的标签列表
        final updatedTags = await _databaseService!.getCategories();

        if (!mounted) return;

        // 脏检查：只有标签数量或内容变化时才更新
        bool needsUpdate = _availableTags.length != updatedTags.length;
        if (!needsUpdate && _availableTags.isNotEmpty) {
          // 简单检查第一个和最后一个标签是否相同
          needsUpdate = _availableTags.first.id != updatedTags.first.id ||
              _availableTags.last.id != updatedTags.last.id;
        }

        if (needsUpdate) {
          setState(() {
            _availableTags = updatedTags;
            // 重新应用当前的搜索过滤
            _updateFilteredTags(_lastSearchQuery);
          });
          logDebug('标签列表已更新，当前共 ${updatedTags.length} 个标签');
        }
      } catch (e) {
        logDebug('更新标签列表失败: $e');
      }
    });
  }

  /// 显示功能引导序列
  void _showGuides() {
    FeatureGuideHelper.showSequence(
      context: context,
      guides: [
        ('add_note_fullscreen_button', _fullscreenButtonKey),
        ('add_note_tag_hidden', _tagGuideKey),
      ],
    );
  }

  // 搜索变化处理 - 使用防抖优化
  void _onSearchChanged() {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      final query = _tagSearchController.text.toLowerCase();
      if (query != _lastSearchQuery) {
        _lastSearchQuery = query;
        _updateFilteredTags(query);
      }
    });
  }

  // 更新过滤标签 - 使用缓存优化
  void _updateFilteredTags(String query) {
    if (!mounted) return;

    setState(() {
      if (query.isEmpty) {
        _filteredTags = _availableTags;
      } else {
        // 优化：使用缓存避免重复计算
        if (_filterCache.containsKey(query)) {
          _filteredTags = _filterCache[query]!;
        } else {
          _filteredTags = _availableTags.where((tag) {
            return tag.name.toLowerCase().contains(query);
          }).toList();

          // 缓存结果，限制缓存大小防止内存泄漏
          if (_filterCache.length < 50) {
            _filterCache[query] = _filteredTags;
          }
        }
      }
    });
  }

  /// 获取新建笔记的实时位置（与全屏编辑器逻辑一致）
  Future<void> _fetchLocationForNewNote() async {
    final locationService = _cachedLocationService;
    if (locationService == null) return;

    // 检查并请求权限（与全屏编辑器一致）
    if (!locationService.hasLocationPermission) {
      bool permissionGranted =
          await locationService.requestLocationPermission();
      if (!permissionGranted) {
        if (mounted && context.mounted) {
          final l10n = AppLocalizations.of(context);
          setState(() {
            _includeLocation = false;
          });
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(l10n.cannotGetLocationTitle),
              content: Text(l10n.cannotGetLocationPermissionShort),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.iKnow),
                ),
              ],
            ),
          );
        }
        return;
      }
    }

    try {
      final position = await locationService.getCurrentLocation();
      if (position != null && mounted) {
        final location = locationService.getFormattedLocation();
        setState(() {
          _newLatitude = position.latitude;
          _newLongitude = position.longitude;
          _newLocation = location.isNotEmpty ? location : null;
        });
      } else if (mounted) {
        // 获取位置失败，提示并还原开关状态
        setState(() {
          _includeLocation = false;
        });
        if (context.mounted) {
          final l10n = AppLocalizations.of(context);
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(l10n.cannotGetLocationTitle),
              content: Text(l10n.cannotGetLocationDesc),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.iKnow),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      logDebug('对话框获取位置失败: $e');
      if (mounted && context.mounted) {
        final l10n = AppLocalizations.of(context);
        setState(() {
          _includeLocation = false;
        });
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.getLocationFailedTitle),
            content: Text(l10n.getLocationFailedDesc(e.toString())),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.iKnow),
              ),
            ],
          ),
        );
      }
    }
  }

  /// 获取新建笔记的天气信息
  Future<void> _fetchWeatherForNewNote() async {
    final weatherService = _cachedWeatherService;
    final locationService = _cachedLocationService;
    if (weatherService == null) return;

    try {
      // 天气需要位置坐标
      double? lat = _newLatitude;
      double? lon = _newLongitude;

      // 如果还没有坐标，尝试从 locationService 获取
      if (lat == null || lon == null) {
        lat = locationService?.currentPosition?.latitude;
        lon = locationService?.currentPosition?.longitude;
      }

      if (lat == null || lon == null) {
        // 没有坐标，无法获取天气
        if (mounted) {
          setState(() {
            _includeWeather = false;
          });
          if (context.mounted) {
            final l10n = AppLocalizations.of(context);
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(l10n.weatherFetchFailedTitle),
                content: Text(l10n.locationAndWeatherUnavailable),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(l10n.iKnow),
                  ),
                ],
              ),
            );
          }
        }
        return;
      }

      // 获取天气
      await weatherService.getWeatherData(lat, lon);

      if (!weatherService.hasData && mounted) {
        // 天气获取失败
        setState(() {
          _includeWeather = false;
        });
        if (context.mounted) {
          final l10n = AppLocalizations.of(context);
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(l10n.weatherFetchFailedTitle),
              content: Text(l10n.weatherFetchFailedDesc),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.iKnow),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      logDebug('对话框获取天气失败: $e');
      if (mounted) {
        setState(() {
          _includeWeather = false;
        });
        if (context.mounted) {
          final l10n = AppLocalizations.of(context);
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(l10n.weatherFetchFailedTitle),
              content: Text(l10n.weatherFetchFailedDesc),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.iKnow),
                ),
              ],
            ),
          );
        }
      }
    }
  }

  /// 获取位置提示文本（支持坐标显示）
  /// 修复：新建模式只显示实时获取的位置，而不是从 LocationService 获取的缓存位置
  String _getLocationTooltipText(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // 编辑模式：显示原始位置
    if (widget.initialQuote != null) {
      if (_originalLocation != null && _originalLocation!.isNotEmpty) {
        return LocationService.formatLocationForDisplay(_originalLocation);
      }
      if (_originalLatitude != null && _originalLongitude != null) {
        return LocationService.formatCoordinates(
          _originalLatitude,
          _originalLongitude,
        );
      }
      return l10n.noLocationInfo;
    }

    // 新建模式：只显示实时获取的位置
    if (_newLocation != null && _newLocation!.isNotEmpty) {
      return LocationService.formatLocationForDisplay(_newLocation);
    }
    if (_newLatitude != null && _newLongitude != null) {
      return LocationService.formatCoordinates(_newLatitude, _newLongitude);
    }
    // 未获取位置时显示"当前位置"提示
    return l10n.currentLocationLabel;
  }

  /// 编辑模式下的位置对话框
  Future<void> _showLocationDialog(
    BuildContext context,
    ThemeData theme,
  ) async {
    final l10n = AppLocalizations.of(context);
    final hasLocationData = _originalLocation != null ||
        (_originalLatitude != null && _originalLongitude != null);
    final hasCoordinates =
        _originalLatitude != null && _originalLongitude != null;
    final hasOnlyCoordinates = _originalLocation == null && hasCoordinates;

    String title;
    String content;
    List<Widget> actions = [];

    if (!hasLocationData) {
      // 没有位置数据
      title = l10n.cannotAddLocation;
      content = l10n.cannotAddLocationDesc;
      actions = [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.iKnow),
        ),
      ];
    } else {
      // 有位置数据
      title = l10n.locationInfo;
      content = hasOnlyCoordinates
          ? l10n.locationUpdateHint(LocationService.formatCoordinates(
              _originalLatitude, _originalLongitude))
          : l10n.locationRemoveHint(
              LocationService.formatLocationForDisplay(_originalLocation),
            );
      actions = [
        if (_includeLocation)
          TextButton(
            onPressed: () => Navigator.pop(context, 'remove'),
            child: Text(l10n.remove),
          ),
        if (hasOnlyCoordinates)
          TextButton(
            onPressed: () => Navigator.pop(context, 'update'),
            child: Text(l10n.updateLocation),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'cancel'),
          child: Text(l10n.cancel),
        ),
      ];
    }

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: actions,
      ),
    );

    if (result == 'update' && hasCoordinates) {
      // 尝试用坐标更新地址
      try {
        // 获取当前语言设置
        final localeCode = _cachedLocationService?.currentLocaleCode;
        final addressInfo =
            await LocalGeocodingService.getAddressFromCoordinates(
          _originalLatitude!,
          _originalLongitude!,
          localeCode: localeCode,
        );
        if (addressInfo != null && mounted) {
          final formattedAddress = addressInfo['formatted_address'];
          if (formattedAddress != null && formattedAddress.isNotEmpty) {
            setState(() {
              _originalLocation = formattedAddress;
              _includeLocation = true;
            });
            if (context.mounted) {
              final l10n = AppLocalizations.of(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(l10n.locationUpdatedTo(formattedAddress))),
              );
            }
          } else if (context.mounted) {
            final l10n = AppLocalizations.of(context);
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(l10n.cannotGetAddress)));
          }
        } else if (mounted && context.mounted) {
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.cannotGetAddress)));
        }
      } catch (e) {
        if (mounted && context.mounted) {
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(
              SnackBar(content: Text(l10n.updateFailed(e.toString()))));
        }
      }
    } else if (result == 'remove') {
      setState(() {
        _includeLocation = false;
      });
    }
  }

  /// 编辑模式下的天气对话框
  Future<void> _showWeatherDialog(BuildContext context, ThemeData theme) async {
    final l10n = AppLocalizations.of(context);
    final hasWeatherData = _originalWeather != null;

    String title;
    String content;
    List<Widget> actions = [];

    if (!hasWeatherData) {
      // 没有天气数据
      title = l10n.cannotAddWeather;
      content = l10n.cannotAddWeatherDesc;
      actions = [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.iKnow),
        ),
      ];
    } else {
      // 有天气数据
      title = l10n.weatherInfo2;
      final weatherDisplay =
          '$_originalWeather${_originalTemperature != null ? " $_originalTemperature" : ""}';
      content = l10n.weatherRemoveHint(weatherDisplay);
      actions = [
        if (_includeWeather)
          TextButton(
            onPressed: () => Navigator.pop(context, 'remove'),
            child: Text(l10n.remove),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'cancel'),
          child: Text(l10n.cancel),
        ),
      ];
    }

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: actions,
      ),
    );

    if (result == 'remove') {
      setState(() {
        _includeWeather = false;
      });
    }
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _dbChangeDebounceTimer?.cancel();
    _contentController.dispose();
    _authorController.dispose();
    _workController.dispose();
    _tagSearchController.dispose();
    _contentFocusNode.dispose();
    _isSaving.dispose();

    // 优化：移除数据库监听器，防止内存泄漏
    _databaseService?.removeListener(_onDatabaseChanged);

    // 优化：清理所有缓存，释放内存
    _filterCache.clear();
    _allCategoriesCache = null;
    _availableTags.clear();
    _filteredTags.clear();

    super.dispose();
  }

  // 添加默认的一言相关标签（完全异步执行，不阻塞UI）
  Future<void> _addDefaultHitokotoTagsAsync() async {
    if (!mounted) return;

    setState(() {
      _isLoadingHitokotoTags = true;
    });

    try {
      final db =
          _databaseService ?? _readServiceOrNull<DatabaseService>(context);

      if (db == null) {
        logDebug('未找到DatabaseService，跳过默认标签添加');
        return;
      }

      // 批量准备标签信息，减少异步等待次数
      final List<Map<String, String>> tagsToEnsure = [];

      // 添加"每日一言"标签
      tagsToEnsure.add({
        'name': '每日一言',
        'icon': '💭',
        'fixedId': DatabaseService.defaultCategoryIdHitokoto,
      });

      // 添加一言类型对应的标签
      String? hitokotoType;
      if (widget.hitokotoData != null) {
        hitokotoType = _getHitokotoTypeFromApiResponse();
        if (hitokotoType != null && hitokotoType.isNotEmpty) {
          String tagName = _convertHitokotoTypeToTagName(hitokotoType);
          String iconName = _getIconForHitokotoType(hitokotoType);
          String? fixedId;

          if (_hitokotoTypeToCategoryIdMap.containsKey(hitokotoType)) {
            fixedId = _hitokotoTypeToCategoryIdMap[hitokotoType];
          }

          tagsToEnsure.add({
            'name': tagName,
            'icon': iconName,
            if (fixedId != null) 'fixedId': fixedId,
          });
        }
      }

      // 批量确保标签存在
      final List<String> tagIds = [];
      for (final tagInfo in tagsToEnsure) {
        final tagId = await _ensureTagExists(
          db,
          tagInfo['name']!,
          tagInfo['icon']!,
          fixedId: tagInfo['fixedId'],
        );
        if (tagId != null) {
          tagIds.add(tagId);
        }
      }

      if (!mounted) return;

      // 一次性更新所有选中的标签
      setState(() {
        for (final tagId in tagIds) {
          if (!_selectedTagIds.contains(tagId)) {
            _selectedTagIds.add(tagId);
          }
        }
      });

      // 设置分类（如果需要）
      if (hitokotoType != null &&
          _hitokotoTypeToCategoryIdMap.containsKey(hitokotoType)) {
        final categoryId = _hitokotoTypeToCategoryIdMap[hitokotoType];
        final category = await db.getCategoryById(categoryId!);
        if (mounted) {
          setState(() {
            _selectedCategory = category;
          });
        }
      }
    } catch (e) {
      logDebug('添加默认标签失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingHitokotoTags = false;
        });
      }
    }
  }

  // 从hitokotoData中获取一言类型
  String? _getHitokotoTypeFromApiResponse() {
    // 一言API的类型字段是'type'
    if (widget.hitokotoData != null &&
        widget.hitokotoData!.containsKey('type')) {
      return widget.hitokotoData!['type'].toString();
    }
    return null;
  }

  // 将一言API的类型代码转换为可读标签名称
  String _convertHitokotoTypeToTagName(String typeCode) {
    // 一言API的类型映射
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
  String _getIconForHitokotoType(String typeCode) {
    const Map<String, String> iconMap = {
      'a': '🎬', // 动画
      'b': '📚', // 漫画
      'c': '🎮', // 游戏
      'd': '📖', // 文学
      'e': '✨', // 原创
      'f': '🌐', // 来自网络
      'g': '📦', // 其他 -> 新 emoji
      'h': '🎞️', // 影视 -> 随机 emoji
      'i': '🪶', // 诗词 -> 随机 emoji
      'j': '', // 网易云 -> 🎧
      'k': '🤔', // 哲学
      'l': '😄', // 抖机灵
    };

    // 默认使用 Material 的 format_quote 图标名
    return iconMap[typeCode] ?? 'format_quote';
  }

  // 缓存所有标签，避免重复查询
  List<NoteCategory>? _allCategoriesCache;

  // 确保标签存在，如果不存在则创建（优化版：减少数据库查询）
  Future<String?> _ensureTagExists(
    DatabaseService db,
    String name,
    String iconName, {
    String? fixedId,
  }) async {
    try {
      // 使用传入的 fixedId 或检查是否有固定ID映射
      if (fixedId == null) {
        for (var entry in _hitokotoTypeToCategoryIdMap.entries) {
          if (_convertHitokotoTypeToTagName(entry.key) == name) {
            fixedId = entry.value;
            break;
          }
        }

        // 如果是"每日一言"标签的特殊情况
        if (name == '每日一言') {
          fixedId = DatabaseService.defaultCategoryIdHitokoto;
        }
      }

      // 无论标签是否被重命名，优先通过固定ID查找
      if (fixedId != null) {
        final category = await db.getCategoryById(fixedId);
        if (category != null) {
          logDebug('通过固定ID找到标签: ${category.name}(ID=${category.id})');
          return category.id;
        }
      }

      // 优化：使用缓存的标签列表，避免每次都查询数据库
      _allCategoriesCache ??= await db.getCategories();
      final categories = _allCategoriesCache!;

      final existingTag = categories.firstWhere(
        (tag) => tag.name.toLowerCase() == name.toLowerCase(),
        orElse: () => NoteCategory(id: '', name: ''),
      );

      // 如果标签已存在，返回其ID
      if (existingTag.id.isNotEmpty) {
        return existingTag.id;
      }

      // 创建新标签
      if (fixedId != null) {
        try {
          await db.addCategoryWithId(fixedId, name, iconName: iconName);
          // 清除缓存，下次会重新加载
          _allCategoriesCache = null;
          return fixedId;
        } catch (e) {
          logDebug('使用固定ID创建标签失败: $e');
          await db.addCategory(name, iconName: iconName);
        }
      } else {
        await db.addCategory(name, iconName: iconName);
      }

      // 清除缓存并重新获取
      _allCategoriesCache = null;
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

  // 解析格式如"——作者《作品》"的字符串
  void _parseSource(
    String source,
    TextEditingController authorController,
    TextEditingController workController,
  ) {
    String author = '';
    String work = '';

    // 提取作者（在"——"之后，"《"之前）
    final authorMatch = RegExp(r'——([^《]+)').firstMatch(source);
    if (authorMatch != null && authorMatch.groupCount >= 1) {
      author = authorMatch.group(1)?.trim() ?? '';
    }

    // 提取作品（在《》之间）
    final workMatch = RegExp(r'《(.+?)》').firstMatch(source);
    if (workMatch != null && workMatch.groupCount >= 1) {
      work = workMatch.group(1) ?? '';
    }

    authorController.text = author;
    workController.text = work;
  }

  // 格式化来源
  String _formatSource(String author, String work) {
    if (author.isEmpty && work.isEmpty) {
      return '';
    }

    String result = '';
    if (author.isNotEmpty) {
      result += '——$author';
    }

    if (work.isNotEmpty) {
      if (result.isNotEmpty) {
        result += ' ';
      } else {
        result += '——';
      }
      result += '《$work》';
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            // 内容输入区，带全屏编辑按钮
            const SizedBox(height: 16),
            Stack(
              children: [
                TextField(
                  controller: _contentController,
                  focusNode: _contentFocusNode,
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(context).writeYourThoughts,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.edit),
                    contentPadding: const EdgeInsets.fromLTRB(16, 16, 48, 16),
                  ),
                  maxLines: 3,
                  autofocus: true, // 立即弹出键盘，其他重操作已延迟
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: Builder(
                    builder: (context) {
                      final isLongContent =
                          _contentController.text.length > 100;
                      return Stack(
                        children: [
                          // 如果是长文本，添加一个提示小红点
                          if (isLongContent)
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: theme.colorScheme.surface,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          IconButton(
                            key: _fullscreenButtonKey,
                            tooltip: isLongContent
                                ? l10n.fullscreenEditLongTextTip
                                : l10n.fullscreenEditTooltip,
                            icon: Icon(
                              Icons.fullscreen,
                              color: theme.colorScheme.primary,
                            ),
                            onPressed: () async {
                              if (!context.mounted) return;
                              try {
                                // 获取所有标签数据
                                final databaseService =
                                    Provider.of<DatabaseService>(
                                  context,
                                  listen: false,
                                );
                                final allTags =
                                    await databaseService.getCategories();

                                // 修复内存泄露：在异步操作后检查mounted状态
                                if (!mounted) return;
                                if (!context.mounted) return;

                                // 创建包含当前元数据的临时Quote对象，确保全屏编辑器能继承所有元数据
                                final locationService =
                                    Provider.of<LocationService>(
                                  context,
                                  listen: false,
                                );
                                final weatherService =
                                    Provider.of<WeatherService>(
                                  context,
                                  listen: false,
                                );

                                // 获取位置和天气信息
                                String? currentLocation;
                                String? currentWeather;
                                String? currentTemperature;

                                if (_includeLocation) {
                                  currentLocation = _originalLocation ??
                                      locationService.getFormattedLocation();
                                }

                                if (_includeWeather) {
                                  currentWeather = _originalWeather ??
                                      weatherService.currentWeather;
                                  currentTemperature = _originalTemperature ??
                                      weatherService.temperature;
                                }

                                // 创建包含当前所有元数据的临时Quote对象
                                // 获取经纬度（编辑时用原始值，新建时用实时获取的值）
                                final currentLat = widget.initialQuote != null
                                    ? _originalLatitude
                                    : _newLatitude ??
                                        locationService
                                            .currentPosition?.latitude;
                                final currentLon = widget.initialQuote != null
                                    ? _originalLongitude
                                    : _newLongitude ??
                                        locationService
                                            .currentPosition?.longitude;

                                final tempQuote = Quote(
                                  id: widget
                                      .initialQuote?.id, // 保持原有ID（如果是编辑模式）
                                  content: _contentController.text,
                                  date: widget.initialQuote?.date ??
                                      DateTime.now().toIso8601String(),
                                  sourceAuthor:
                                      _authorController.text.trim().isEmpty
                                          ? null
                                          : _authorController.text.trim(),
                                  sourceWork:
                                      _workController.text.trim().isEmpty
                                          ? null
                                          : _workController.text.trim(),
                                  tagIds: _selectedTagIds,
                                  colorHex: _selectedColorHex,
                                  location: currentLocation,
                                  latitude:
                                      _includeLocation ? currentLat : null,
                                  longitude:
                                      _includeLocation ? currentLon : null,
                                  weather: currentWeather,
                                  temperature: currentTemperature,
                                  aiAnalysis: widget.initialQuote?.aiAnalysis,
                                  sentiment: widget.initialQuote?.sentiment,
                                  keywords: widget.initialQuote?.keywords,
                                  summary: widget.initialQuote?.summary,
                                  categoryId: widget.initialQuote?.categoryId,
                                  editSource: widget.initialQuote?.editSource,
                                  deltaContent:
                                      widget.initialQuote?.deltaContent,
                                  dayPeriod: widget.initialQuote?.dayPeriod,
                                );

                                if (!context.mounted) return;
                                final navigator = Navigator.of(context);
                                final result = await navigator.push(
                                  MaterialPageRoute(
                                    builder: (context) => NoteFullEditorPage(
                                      initialContent: _contentController.text,
                                      initialQuote:
                                          tempQuote, // 传递包含当前元数据的临时Quote对象
                                      allTags: allTags,
                                    ),
                                  ),
                                );

                                if (!mounted) return;

                                if (result != null && result == true) {
                                  // 如果笔记已在全屏编辑器中保存，关闭本对话框
                                  if (mounted && context.mounted) {
                                    Navigator.pop(context);
                                  }
                                }
                              } catch (e) {
                                if (mounted && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          '${l10n.openFullEditorFailedSimple}: $e'),
                                      backgroundColor: Colors.red,
                                      duration: const Duration(seconds: 3),
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 拆分来源输入为作者和作品
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _authorController,
                    decoration: InputDecoration(
                      hintText: AppLocalizations.of(context).authorPerson,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.person),
                    ),
                    maxLines: 1,
                    onChanged: (value) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _workController,
                    decoration: InputDecoration(
                      hintText: AppLocalizations.of(context).workName,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.book),
                    ),
                    maxLines: 1,
                    onChanged: (value) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            // 显示格式化后的来源预览
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.sourcePreviewFormat(_formatSource(
                    _authorController.text, _workController.text)),
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurface.applyOpacity(
                    0.6,
                  ), // MODIFIED
                ),
              ),
            ),

            // 位置和天气选项
            const SizedBox(height: 16),
            RepaintBoundary(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    l10n.addInfo,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 位置信息按钮
                  Builder(
                    builder: (context) {
                      // 仅在需要显示 tooltip 时读取服务，避免每次 build 都触发
                      final locationService = _cachedLocationService;
                      return Tooltip(
                        message: locationService != null
                            ? '${l10n.addLocationPrefix}: ${_getLocationTooltipText(context)}'
                            : l10n.locationServiceUnavailable,
                        child: Stack(
                          children: [
                            FilterChip(
                              key: const ValueKey('add_note_location_chip'),
                              avatar: Icon(
                                Icons.location_on,
                                color: _includeLocation
                                    ? theme.colorScheme.primary
                                    : Colors.grey,
                                size: 18,
                              ),
                              label: Text(l10n.location),
                              selected: _includeLocation,
                              onSelected: (value) async {
                                // 编辑模式下统一弹对话框
                                if (widget.initialQuote != null) {
                                  await _showLocationDialog(context, theme);
                                  return;
                                }
                                // 新建模式
                                if (value &&
                                    _newLocation == null &&
                                    _newLatitude == null) {
                                  _fetchLocationForNewNote();
                                }
                                setState(() {
                                  _includeLocation = value;
                                });
                              },
                              selectedColor: theme.colorScheme.primaryContainer,
                            ),
                            // 小红点：有坐标但没地址时提示可更新
                            if (widget.initialQuote != null &&
                                _originalLocation == null &&
                                _originalLatitude != null &&
                                _originalLongitude != null)
                              Positioned(
                                right: 0,
                                top: 0,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.error,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  // 天气信息按钮
                  Builder(
                    builder: (context) {
                      // 仅在需要显示时读取服务，避免每次 build 都触发
                      final weatherService = _cachedWeatherService;
                      final weather = weatherService?.currentWeather;
                      final formattedWeather =
                          weatherService?.getFormattedWeather(l10n);
                      return Tooltip(
                        message: weather != null && weatherService != null
                            ? l10n.addWeatherWithValue(
                                formattedWeather ?? weather)
                            : l10n.addWeatherInfo,
                        child: FilterChip(
                          key: const ValueKey('add_note_weather_chip'),
                          avatar: Icon(
                            weather != null && weatherService != null
                                ? weatherService.getWeatherIconData()
                                : Icons.cloud,
                            color: _includeWeather
                                ? theme.colorScheme.primary
                                : Colors.grey,
                            size: 18,
                          ),
                          label: Text(l10n.weather),
                          selected: _includeWeather,
                          onSelected: (value) async {
                            // 编辑模式下统一弹对话框
                            if (widget.initialQuote != null) {
                              await _showWeatherDialog(context, theme);
                              return;
                            }
                            // 新建模式
                            if (value) {
                              setState(() {
                                _includeWeather = true;
                              });
                              // 勾选时获取天气
                              _fetchWeatherForNewNote();
                            } else {
                              setState(() {
                                _includeWeather = false;
                              });
                            }
                          },
                          selectedColor: theme.colorScheme.primaryContainer,
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  // 颜色选择按钮
                  Tooltip(
                    message: _selectedColorHex != null
                        ? l10n.cardColorSet
                        : l10n.setCardColor,
                    child: FilterChip(
                      key: const ValueKey('add_note_color_chip'),
                      avatar: _selectedColorHex != null
                          ? Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: Color(
                                  int.parse(
                                        _selectedColorHex!.substring(1),
                                        radix: 16,
                                      ) |
                                      0xFF000000,
                                ),
                                borderRadius: BorderRadius.circular(9),
                                border:
                                    Border.all(color: Colors.white, width: 1),
                              ),
                            )
                          : const Icon(
                              Icons.color_lens,
                              size: 18,
                              color: Colors.grey,
                            ),
                      label: Text(l10n.color),
                      selected: _selectedColorHex != null,
                      onSelected: (value) {
                        if (value) {
                          _showCustomColorPicker(context);
                        } else {
                          setState(() {
                            _selectedColorHex = null;
                          });
                        }
                      },
                      selectedColor: theme.colorScheme.primaryContainer,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ), // 标签选择区域
            const SizedBox(height: 16),
            // ✅ 使用独立组件，避免AddNoteDialog重建时重复构建标签列表
            Container(
              key: _tagGuideKey,
              child: TagSelectionSection(
                tags: _availableTags,
                selectedTagIds: _selectedTagIds,
                onSelectionChanged: (newSelection) {
                  setState(() {
                    _selectedTagIds
                      ..clear()
                      ..addAll(newSelection);
                  });
                },
                isLoading: _isLoadingHitokotoTags,
              ),
            ),

            // 显示已选标签
            SelectedTagsDisplay(
              selectedTagIds: _selectedTagIds,
              allTags: _availableTags,
              onRemoveTag: (tagId) {
                setState(() {
                  _selectedTagIds.remove(tagId);
                });
              },
            ),

            // AI分析结果
            if (_aiSummary != null)
              Container(
                margin: const EdgeInsets.only(top: 16),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'AI分析',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    MarkdownBody(
                      data: _aiSummary!,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet.fromTheme(
                        theme,
                      ).copyWith(p: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // AI助手按钮
                AddNoteAIMenu(
                  contentController: _contentController,
                  authorController: _authorController,
                  workController: _workController,
                  onAiAnalysisCompleted: (result) {
                    setState(() {
                      _aiSummary = result;
                    });
                  },
                ),
                const Spacer(),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppTheme.buttonRadius,
                      ),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.cancel),
                ),
                const SizedBox(width: 8),
                ValueListenableBuilder<bool>(
                  valueListenable: _isSaving,
                  builder: (context, isSaving, child) {
                    return ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _contentController,
                      builder: (context, value, child) {
                        final bool isContentEmpty = value.text.trim().isEmpty;
                        final bool canSave = !_isLoadingFullQuote &&
                            !isSaving &&
                            !isContentEmpty;

                        return FilledButton(
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppTheme.buttonRadius,
                              ),
                            ),
                          ),
                          onPressed: canSave
                              ? () async {
                                  _isSaving.value = true;

                                  try {
                                    // 获取当前时间段
                                    final String currentDayPeriodKey = TimeUtils
                                        .getCurrentDayPeriodKey(); // 使用 Key

                                    // 创建或更新笔记
                                    // 使用实时获取的位置（新建）或原始位置（编辑）
                                    final isEditing =
                                        widget.initialQuote != null;
                                    final baseQuote = _fullInitialQuote ??
                                        widget.initialQuote;

                                    final Quote quote = Quote(
                                      id: widget.initialQuote?.id ??
                                          const Uuid().v4(),
                                      content: _contentController.text,
                                      date: widget.initialQuote?.date ??
                                          DateTime.now().toIso8601String(),
                                      aiAnalysis: _aiSummary,
                                      source: _formatSource(
                                        _authorController.text,
                                        _workController.text,
                                      ),
                                      sourceAuthor: _authorController.text,
                                      sourceWork: _workController.text,
                                      tagIds: _selectedTagIds,
                                      sentiment: baseQuote?.sentiment,
                                      keywords: baseQuote?.keywords,
                                      summary: baseQuote?.summary,
                                      categoryId: _selectedCategory?.id ??
                                          widget.initialQuote?.categoryId,
                                      colorHex: _selectedColorHex,
                                      location: _includeLocation
                                          ? (isEditing
                                              ? _originalLocation
                                              : _newLocation ??
                                                  _cachedLocationService
                                                      ?.getFormattedLocation())
                                          : null,
                                      latitude:
                                          (_includeLocation || _includeWeather)
                                              ? (isEditing
                                                  ? _originalLatitude
                                                  : _newLatitude)
                                              : null,
                                      longitude:
                                          (_includeLocation || _includeWeather)
                                              ? (isEditing
                                                  ? _originalLongitude
                                                  : _newLongitude)
                                              : null,
                                      weather: _includeWeather
                                          ? (isEditing
                                              ? _originalWeather
                                              : _cachedWeatherService
                                                  ?.currentWeather)
                                          : null,
                                      temperature: _includeWeather
                                          ? (isEditing
                                              ? _originalTemperature
                                              : _cachedWeatherService
                                                  ?.temperature)
                                          : null,
                                      dayPeriod:
                                          widget.initialQuote?.dayPeriod ??
                                              currentDayPeriodKey, // 保存 Key
                                      editSource: widget
                                          .initialQuote?.editSource, // 保证兼容
                                      deltaContent: widget
                                          .initialQuote?.deltaContent, // 保证兼容
                                    );

                                    final db = Provider.of<DatabaseService>(
                                      context,
                                      listen: false,
                                    );

                                    if (widget.initialQuote != null) {
                                      // 更新已有笔记
                                      await db.updateQuote(quote);
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            AppLocalizations.of(context)
                                                .noteUpdated,
                                          ),
                                          duration: AppConstants
                                              .snackBarDurationImportant,
                                        ),
                                      );
                                    } else {
                                      // 添加新笔记
                                      await db.addQuote(quote);
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            AppLocalizations.of(context)
                                                .noteSaved,
                                          ),
                                          duration: AppConstants
                                              .snackBarDurationImportant,
                                        ),
                                      );
                                    }

                                    // 调用保存回调
                                    if (widget.onSave != null) {
                                      widget.onSave!(quote);
                                    }

                                    // 关闭对话框
                                    if (this.context.mounted) {
                                      Navigator.of(context).pop();
                                    }

                                    // 在保存后请求AI推荐标签（仅新建笔记时）
                                    if (!isEditing) {
                                      // 使用无阻塞方式调用推荐，无需await
                                      _showAIRecommendedTags(quote.content);
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            AppLocalizations.of(
                                              context,
                                            ).saveFailedWithError(e.toString()),
                                          ),
                                          duration: AppConstants
                                              .snackBarDurationError,
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (mounted) {
                                      _isSaving.value = false;
                                    }
                                  }
                                }
                              : null,
                          child: _isLoadingFullQuote || isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  widget.initialQuote != null
                                      ? AppLocalizations.of(context).edit
                                      : AppLocalizations.of(context).save,
                                ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // 自定义颜色选择器
  Future<void> _showCustomColorPicker(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final Color initialColor = _selectedColorHex != null
        ? Color(
            int.parse(_selectedColorHex!.substring(1), radix: 16) | 0xFF000000,
          )
        : Colors.transparent;

    final Color? result = await showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.selectCardColor),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 预设颜色网格 - 使用新的无障碍组件
              AccessibleColorGrid(
                selectedColorHex: _selectedColorHex,
                onColorSelected: (color) {
                  if (!mounted) return;
                  Navigator.of(context).pop(color);
                },
              ),

              const SizedBox(height: 16),

              // 高级颜色选择按钮
              OutlinedButton.icon(
                icon: const Icon(Icons.color_lens),
                label: Text(l10n.customColor),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  Navigator.pop(context); // 关闭当前对话框

                  // 打开高级颜色选择器
                  Color selectedColor = initialColor;
                  final Color? advancedColor = await showDialog<Color>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(l10n.customColor),
                      content: SingleChildScrollView(
                        child: ColorPicker(
                          color: initialColor != Colors.transparent
                              ? initialColor
                              : const Color(0xFFE1F5FE), // 默认蓝色
                          onColorChanged: (color) {
                            selectedColor = color;
                          },
                          width: 40,
                          height: 40,
                          spacing: 10,
                          runSpacing: 10,
                          borderRadius: 20,
                          wheelDiameter: 200,
                          enableShadesSelection: true,
                          pickersEnabled: const {
                            ColorPickerType.primary: true,
                            ColorPickerType.accent: false,
                            ColorPickerType.wheel: true,
                          },
                        ),
                      ),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(l10n.cancel),
                        ),
                        FilledButton(
                          onPressed: () =>
                              Navigator.of(context).pop(selectedColor),
                          child: Text(l10n.select),
                        ),
                      ],
                    ),
                  );

                  if (advancedColor != null && mounted) {
                    setState(() {
                      _selectedColorHex = advancedColor == Colors.transparent
                          ? null
                          : '#${advancedColor.toARGB32().toRadixString(16).substring(2)}'; // MODIFIED
                    });
                  }
                },
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
        ],
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
    if (result != null) {
      setState(() {
        _selectedColorHex = result == Colors.transparent
            ? null
            : '#${result.toARGB32().toRadixString(16).substring(2)}'; // MODIFIED
      });
    }
  }

  /// 显示AI推荐标签对话框
  Future<void> _showAIRecommendedTags(String content) async {
    // 捕获必要的数据
    if (!mounted) return;

    final settingsService = _readServiceOrNull<SettingsService>(context);
    if (settingsService == null) return;

    final localAI = settingsService.localAISettings;
    if (!localAI.enabled || !localAI.smartTagsEnabled) {
      return;
    }

    // 复制标签列表，因为后续 async gap 后 _availableTags 可能被清除
    final capturedTags = List<NoteCategory>.from(_availableTags);

    // TODO: 调用本地AI模型获取推荐标签 - 后端实现后添加
    // 目前返回mock数据
    // 注意：这里我们故意等待，而调用者 (onPressed) 不 await 这个方法，
    // 从而实现"保存后推荐"且不阻塞 UI 关闭。
    await Future.delayed(const Duration(milliseconds: 500));

    // Mock: 暂时不推荐任何标签
    final List<String> recommendedTagIds = [];

    if (recommendedTagIds.isEmpty) return;

    // 显示推荐标签对话框 - 使用全局 navigatorKey
    // 因为此时 AddNoteDialog 已经 pop 并 dispose
    final globalContext = navigatorKey.currentContext;
    if (globalContext != null && globalContext.mounted) {
      final l10n = AppLocalizations.of(globalContext);
      showDialog(
        context: globalContext,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.recommendedTags),
          content: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: recommendedTagIds.map((tagId) {
              final tag = capturedTags.firstWhere(
                (t) => t.id == tagId,
                orElse: () => NoteCategory(
                  id: tagId,
                  name: tagId,
                  iconName: 'label',
                ),
              );
              return FilterChip(
                label: Text(tag.name),
                avatar: IconUtils.isEmoji(tag.iconName)
                    ? IconUtils.getDisplayIcon(tag.iconName)
                    : Icon(IconUtils.getIconData(tag.iconName), size: 18),
                onSelected: (selected) {
                  // 这里无法直接更新 Note，因为 Note 已经保存。
                  // 实际逻辑应该是：
                  // 1. 更新数据库中的 Note
                  // 2. 触发全局刷新
                  // 由于这是 Mock，且涉及较多逻辑变更，暂时保留 UI 展示
                  // 后续需实现：DatabaseService.updateQuoteTags(noteId, newTags)
                },
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.cancel),
            ),
            // FilledButton(...) - 这里需要真实的保存逻辑
          ],
        ),
      );
    }
  }
}
