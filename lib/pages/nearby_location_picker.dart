import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen_l10n/app_localizations.dart';
import '../services/location_service.dart';
import '../services/place_search_service.dart';
import '../theme/theme_style.dart';
import '../utils/app_logger.dart';
import '../widgets/app_loading_view.dart';

/// 位置选择结果。
class LocationPickerResult {
  const LocationPickerResult({
    required this.latitude,
    required this.longitude,
    this.location,
    this.poiName,
  });

  final double latitude;
  final double longitude;

  /// 入库格式的行政区串 `国家,省份,城市,区县`；反查失败时为 null。
  final String? location;

  /// 用户选中的地点名（如"灵隐寺"、"科苑南路"）。
  /// 选了纯系统定位且无 POI 时为 null。
  final String? poiName;
}

/// 兼容别名：供旧引用平滑过渡
typedef MapPickerResult = LocationPickerResult;

/// 附近地点选择器（朋友圈模式，去除地图瓦片）。
///
/// 遵循真实发生地原则，不允许用户手工键入任意地名；
/// 第一项常驻设备当前定位，下方异步加载 5 公里范围内的周边候选 POI，
/// 支持滑动到底部分页加载。
class NearbyLocationPicker extends StatefulWidget {
  const NearbyLocationPicker({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.initialLocation,
    this.initialPoiName,
    this.placeSearchService,
    this.locationService,
  });

  final double? initialLatitude;
  final double? initialLongitude;
  final String? initialLocation;
  final String? initialPoiName;
  final PlaceSearchService? placeSearchService;
  final LocationService? locationService;

  @override
  State<NearbyLocationPicker> createState() => _NearbyLocationPickerState();
}

/// 兼容别名
typedef MapLocationPickerPage = NearbyLocationPicker;

class _NearbyLocationPickerState extends State<NearbyLocationPicker> {
  LocationService? _locationService;
  late final PlaceSearchService _placeSearch;
  final ScrollController _scrollController = ScrollController();

  double? _deviceLatitude;
  double? _deviceLongitude;
  String? _deviceLocationString;
  String? _devicePoiName;

  bool _isLocating = true;
  bool _locatingFailed = false;

  bool _isConfirming = false;
  int _confirmEpoch = 0;

  final List<PlaceInfo> _places = [];
  bool _isLoadingPlaces = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _placesError = false;

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounceTimer;
  final List<PlaceInfo> _searchResults = [];
  bool _isSearching = false;
  bool _searchError = false;

  int _currentOffset = 0;
  static const int _pageSize = 20;

  late bool _systemSelected;
  PlaceInfo? _selectedPlace;
  String? _customSelectedPoiName;
  double? _customSelectedLatitude;
  double? _customSelectedLongitude;
  Animation<double>? _routeAnimation;

  static bool _coordsMatch(
    double? aLat,
    double? aLng,
    double? bLat,
    double? bLng,
  ) {
    if (aLat == null || aLng == null || bLat == null || bLng == null) {
      return false;
    }
    return (aLat - bLat).abs() < 0.0001 && (aLng - bLng).abs() < 0.0001;
  }

  @override
  void initState() {
    super.initState();
    _placeSearch = widget.placeSearchService ?? NominatimPlaceSearchService();
    _scrollController.addListener(_onScroll);

    final hasInitialPoi = widget.initialPoiName != null &&
        widget.initialPoiName!.trim().isNotEmpty;
    _systemSelected = !hasInitialPoi;
    _customSelectedPoiName =
        hasInitialPoi ? widget.initialPoiName!.trim() : null;
    _customSelectedLatitude = widget.initialLatitude;
    _customSelectedLongitude = widget.initialLongitude;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initServicesAndLoad();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (_routeAnimation != animation) {
      _routeAnimation?.removeStatusListener(_onRouteAnimationStatusChanged);
      _routeAnimation = animation;
      _routeAnimation?.addStatusListener(_onRouteAnimationStatusChanged);
    }
  }

  void _onRouteAnimationStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.reverse ||
        status == AnimationStatus.dismissed) {
      _confirmEpoch++;
    }
  }

  bool get _isCurrentRouteActive {
    if (!mounted) return false;
    final route = ModalRoute.of(context);
    return route != null && route.isActive && route.isCurrent;
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    _confirmEpoch++;
    _routeAnimation?.removeStatusListener(_onRouteAnimationStatusChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _initServicesAndLoad() {
    if (!mounted) return;
    try {
      _locationService = widget.locationService ??
          Provider.of<LocationService>(context, listen: false);
    } catch (_) {
      _locationService = widget.locationService ?? LocationService();
    }

    _locateDeviceAndFetchPlaces();
  }

  Future<void> _locateDeviceAndFetchPlaces() async {
    setState(() {
      _isLocating = true;
      _locatingFailed = false;
    });

    try {
      final locService = _locationService;
      if (locService == null) {
        _handleLocatingFallback();
        return;
      }

      final pos = await locService.getCurrentLocation(highAccuracy: true);
      if (!mounted) return;

      if (pos != null) {
        _deviceLatitude = pos.latitude;
        _deviceLongitude = pos.longitude;
        _devicePoiName = locService.currentPoiName;
        final fmt = locService.getFormattedLocation();
        _deviceLocationString = fmt.isNotEmpty ? fmt : null;
        _onDeviceLocationAcquired();
      } else if (locService.currentPosition != null) {
        final cached = locService.currentPosition!;
        _deviceLatitude = cached.latitude;
        _deviceLongitude = cached.longitude;
        _devicePoiName = locService.currentPoiName;
        final fmt = locService.getFormattedLocation();
        _deviceLocationString = fmt.isNotEmpty ? fmt : null;
        _onDeviceLocationAcquired();
      } else {
        _handleLocatingFallback();
      }
    } catch (e) {
      logDebug('获取当前设备位置失败: $e', source: 'NearbyLocationPicker');
      if (mounted) {
        _handleLocatingFallback();
      }
    }
  }

  void _handleLocatingFallback() {
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _deviceLatitude = widget.initialLatitude;
      _deviceLongitude = widget.initialLongitude;
      _deviceLocationString = widget.initialLocation;
      if (_systemSelected) {
        _devicePoiName = widget.initialPoiName;
      }
      _onDeviceLocationAcquired();
    } else {
      _isLocating = false;
      _locatingFailed = true;
      setState(() {});
    }
  }

  void _onDeviceLocationAcquired() {
    _isLocating = false;
    setState(() {});
    _resolveAddressAndFetchPlaces();
  }

  Future<void> _resolveAddressAndFetchPlaces() async {
    if (_deviceLatitude == null || _deviceLongitude == null) return;

    // 若地址尚未就绪，尝试反查
    if (_deviceLocationString == null || _deviceLocationString!.isEmpty) {
      try {
        final rev = await _locationService?.reverseGeocodePoint(
          _deviceLatitude!,
          _deviceLongitude!,
        );
        if (mounted && rev != null) {
          setState(() {
            _deviceLocationString = LocationService.buildStorageLocation(rev);
            _devicePoiName ??= rev['poi_name'];
          });
        }
      } catch (e) {
        logDebug('反查地址失败（离线保存精确物理坐标）: $e', source: 'NearbyLocationPicker');
      }
    }

    if (!mounted) return;
    _fetchNearbyPlaces(isLoadMore: false);
  }

  void _onSearchChanged(String query) {
    _searchDebounceTimer?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults.clear();
        _searchError = false;
      });
      return;
    }

    _searchDebounceTimer = Timer(const Duration(milliseconds: 400), () {
      _executeSearch(trimmed);
    });
  }

  Future<void> _executeSearch(String query) async {
    if (!mounted) return;
    if (_deviceLatitude == null || _deviceLongitude == null) return;
    setState(() {
      _isSearching = true;
      _searchError = false;
    });

    try {
      final localeCode = Localizations.localeOf(context).languageCode;
      final results = await _placeSearch.searchNearby(
        _deviceLatitude!,
        _deviceLongitude!,
        query: query,
        localeCode: localeCode,
      );
      if (!mounted) return;
      setState(() {
        _searchResults.clear();
        _searchResults.addAll(results);
        _isSearching = false;
      });
    } catch (e, stack) {
      logError(
        '搜索地点失败',
        error: e,
        stackTrace: stack,
        source: 'NearbyLocationPicker',
      );
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _searchError = true;
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (maxScroll - currentScroll <= 150) {
      if (!_isLoadingPlaces && !_isLoadingMore && _hasMore && !_placesError) {
        _fetchNearbyPlaces(isLoadMore: true);
      }
    }
  }

  Future<void> _fetchNearbyPlaces({required bool isLoadMore}) async {
    if (!mounted) return;
    if (_deviceLatitude == null || _deviceLongitude == null) return;
    if (isLoadMore) {
      if (_isLoadingMore || !_hasMore) return;
      setState(() {
        _isLoadingMore = true;
      });
    } else {
      setState(() {
        _isLoadingPlaces = true;
        _placesError = false;
        _currentOffset = 0;
        _hasMore = true;
      });
    }

    try {
      final localeCode = Localizations.localeOf(context).languageCode;

      final results = await _placeSearch.getNearbyPlaces(
        _deviceLatitude!,
        _deviceLongitude!,
        localeCode: localeCode,
        limit: _pageSize,
        offset: _currentOffset,
      );

      if (!mounted) return;

      // 严格保证在 5 公里半径之内
      final validPlaces =
          results.where((p) => (p.distanceMeters ?? 0) <= 5000).toList();

      String placeKey(PlaceInfo p) =>
          '${p.name}|${p.latitude.toStringAsFixed(4)}|${p.longitude.toStringAsFixed(4)}';
      final existingKeys = _places.map(placeKey).toSet();
      final List<PlaceInfo> newUnique = [];
      for (final p in validPlaces) {
        if (existingKeys.add(placeKey(p))) {
          newUnique.add(p);
        }
      }

      // 如果当前选中的是之前传入的 POI，在候选列表中定位对应条目（同时匹配名称与坐标容差，防止同名不同分店误选）
      if (_customSelectedPoiName != null && _selectedPlace == null) {
        for (final p in _places.followedBy(newUnique)) {
          final matchesCoords = _coordsMatch(p.latitude, p.longitude,
              _customSelectedLatitude, _customSelectedLongitude);
          if (p.name == _customSelectedPoiName && matchesCoords) {
            _selectedPlace = p;
            break;
          }
        }
      }

      setState(() {
        if (!isLoadMore) {
          _places.clear();
        }
        _places.addAll(newUnique);
        _currentOffset += results.length;
        if (results.isEmpty) {
          _hasMore = false;
        }
        _isLoadingPlaces = false;
        _isLoadingMore = false;
      });
    } catch (e, stack) {
      logError(
        '加载周边地点失败',
        error: e,
        stackTrace: stack,
        source: 'NearbyLocationPicker',
      );
      if (!mounted) return;
      setState(() {
        if (!isLoadMore) {
          _placesError = true;
        }
        _isLoadingPlaces = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _confirmSelection({PlaceInfo? place}) async {
    if (_isConfirming) return;
    final epoch = ++_confirmEpoch;
    setState(() {
      _isConfirming = true;
    });

    try {
      final bool matchesInitial;
      if (place == null) {
        // 未点选候选列表项（例如直接点击右上角确认）：
        // 只要未改变选中的 POI 名称，即可保留传入的初始值（包含无坐标场景）
        matchesInitial = _customSelectedPoiName != null &&
            _customSelectedPoiName == widget.initialPoiName;
      } else {
        // 用户点选了候选列表项（或已选中的候选地点）：
        // 仅在名称一致且坐标在容差范围内一致时，才视为确认初始 POI；
        // 若初始经纬度为空或坐标不匹配，候选点必须作为新选地点处理，重新解析行政区。
        matchesInitial = _customSelectedPoiName != null &&
            _customSelectedPoiName == widget.initialPoiName &&
            place.name == widget.initialPoiName &&
            _coordsMatch(place.latitude, place.longitude,
                widget.initialLatitude, widget.initialLongitude);
      }

      if (matchesInitial) {
        // 意图保留初始 POI（经纬度在容差内与名称均一致，或无明确点选列表项时点击确认）
        if (!mounted || epoch != _confirmEpoch || !_isCurrentRouteActive) {
          return;
        }
        Navigator.of(context).pop(
          LocationPickerResult(
            latitude: widget.initialLatitude ??
                _customSelectedLatitude ??
                _deviceLatitude!,
            longitude: widget.initialLongitude ??
                _customSelectedLongitude ??
                _deviceLongitude!,
            location: widget.initialLocation,
            poiName: widget.initialPoiName,
          ),
        );
      } else if (place != null) {
        // 用户从列表中点选了候选 POI：
        // 行政区必须为合规的四级结构串（国家,省份,城市,区县），不能直接保存街道门牌展示串。
        // 若与设备定位同坐标，复用设备行政区串；否则若提供反查服务则尝试反查行政区，
        // 无法反查时设为 null（保存退回坐标/地名），杜绝写入非标准格式。
        String? adminLocation;
        if (_coordsMatch(place.latitude, place.longitude, _deviceLatitude,
            _deviceLongitude)) {
          adminLocation = _deviceLocationString;
        } else if (_locationService != null) {
          try {
            final rev = await _locationService!
                .reverseGeocodePoint(place.latitude, place.longitude);
            adminLocation = LocationService.buildStorageLocation(rev);
          } catch (_) {
            adminLocation = null;
          }
        }
        if (!mounted || epoch != _confirmEpoch || !_isCurrentRouteActive) {
          return;
        }
        Navigator.of(context).pop(
          LocationPickerResult(
            latitude: place.latitude,
            longitude: place.longitude,
            location: adminLocation,
            poiName: place.name,
          ),
        );
      } else if (_systemSelected) {
        // 选中当前设备位置（所见即所得：仅保存行政区，不偷偷注入周边 POI）
        if (!mounted || epoch != _confirmEpoch || !_isCurrentRouteActive) {
          return;
        }
        Navigator.of(context).pop(
          LocationPickerResult(
            latitude: _deviceLatitude!,
            longitude: _deviceLongitude!,
            location: _deviceLocationString,
            poiName: null,
          ),
        );
      } else if (_customSelectedPoiName != null &&
          _customSelectedLatitude != null &&
          _customSelectedLongitude != null) {
        // 保留原本选中的候选 POI
        if (!mounted || epoch != _confirmEpoch || !_isCurrentRouteActive) {
          return;
        }
        Navigator.of(context).pop(
          LocationPickerResult(
            latitude: _customSelectedLatitude!,
            longitude: _customSelectedLongitude!,
            location: widget.initialLocation,
            poiName: _customSelectedPoiName,
          ),
        );
      } else {
        if (!mounted || epoch != _confirmEpoch || !_isCurrentRouteActive) {
          return;
        }
        Navigator.of(context).pop(
          LocationPickerResult(
            latitude: _deviceLatitude!,
            longitude: _deviceLongitude!,
            location: _deviceLocationString,
            poiName: null,
          ),
        );
      }
    } finally {
      if (mounted && epoch == _confirmEpoch) {
        setState(() {
          _isConfirming = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _confirmEpoch++;
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(
            onPressed: () {
              _confirmEpoch++;
              Navigator.maybePop(context);
            },
          ),
          title: Text(l10n.nearbyLocationTitle),
          actions: [
            IconButton(
              key: const ValueKey('nearby_picker_confirm_button'),
              icon: _isConfirming
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: AppInlineLoadingIndicator(size: 16),
                    )
                  : const Icon(Icons.check),
              tooltip: l10n.mapPickerConfirm,
              onPressed: (_isConfirming ||
                      _deviceLatitude == null ||
                      _deviceLongitude == null)
                  ? null
                  : () => _confirmSelection(
                        place: _systemSelected ? null : _selectedPlace,
                      ),
            ),
          ],
        ),
        body: _buildBody(theme, l10n),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, AppLocalizations l10n) {
    final Widget content;
    if (_isLocating) {
      content = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const AppInlineLoadingIndicator(),
            const SizedBox(height: 16),
            Text(
              l10n.gettingLocationHint,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    } else if (_locatingFailed &&
        (_deviceLatitude == null || _deviceLongitude == null)) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.location_off_outlined,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.locationServiceUnavailable,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _locateDeviceAndFetchPlaces,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.retry),
              ),
            ],
          ),
        ),
      );
    } else {
      final isSearchingMode = _searchController.text.trim().isNotEmpty;
      content = Column(
        children: [
          _buildSearchBar(theme, l10n),
          Expanded(
            child: isSearchingMode
                ? _buildSearchResultsList(theme, l10n)
                : _buildNearbyPlacesList(theme, l10n),
          ),
        ],
      );
    }

    return AbsorbPointer(
      key: const ValueKey('nearby_picker_body_absorb_pointer'),
      absorbing: _isConfirming,
      child: content,
    );
  }

  Widget _buildSearchBar(ThemeData theme, AppLocalizations l10n) {
    final shapeTokens = AppShapeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        controller: _searchController,
        style: theme.textTheme.bodyMedium,
        decoration: InputDecoration(
          hintText: l10n.mapPickerSearchHint,
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded),
                  tooltip: l10n.clear,
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                )
              : null,
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHigh,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(shapeTokens.inputRadius),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(shapeTokens.inputRadius),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(shapeTokens.inputRadius),
            borderSide: BorderSide(
              color: theme.colorScheme.primary,
              width: 1.5,
            ),
          ),
        ),
        onChanged: _onSearchChanged,
      ),
    );
  }

  Widget _buildSearchResultsList(ThemeData theme, AppLocalizations l10n) {
    if (_isSearching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const AppInlineLoadingIndicator(),
            const SizedBox(height: 16),
            Text(
              l10n.mapPickerSearching,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (_searchError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.onlinePlaceSearchUnavailable,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => _executeSearch(_searchController.text.trim()),
                child: Text(l10n.retry),
              ),
            ],
          ),
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 48,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.noCityFound,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final place = _searchResults[index];
        return _buildPlaceTile(theme, l10n, place);
      },
    );
  }

  Widget _buildNearbyPlacesList(ThemeData theme, AppLocalizations l10n) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: 1 +
          (_placesError ? 1 : 0) +
          _places.length +
          (_isLoadingPlaces || _isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        // 第 0 项：设备当前系统定位，永远可用
        if (index == 0) {
          return _buildSystemLocationTile(theme, l10n);
        }

        var offsetIndex = index - 1;

        // 在线服务错误提示条目（附轻量重试按钮）
        if (_placesError) {
          if (offsetIndex == 0) {
            return _buildErrorBanner(theme, l10n);
          }
          offsetIndex--;
        }

        // 候选 POI 列表
        if (offsetIndex < _places.length) {
          final place = _places[offsetIndex];
          return _buildPlaceTile(theme, l10n, place);
        }

        // 底部加载更多指示器
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: AppInlineLoadingIndicator(),
          ),
        );
      },
    );
  }

  /// 第一项：设备当前系统定位
  Widget _buildSystemLocationTile(ThemeData theme, AppLocalizations l10n) {
    final String title;
    if (_deviceLocationString != null && _deviceLocationString!.isNotEmpty) {
      title = LocationService.formatLocationForDisplay(_deviceLocationString);
    } else {
      title = LocationService.formatCoordinates(
        _deviceLatitude!,
        _deviceLongitude!,
        precision: 4,
      );
    }

    final String subtitle;
    if (_deviceLocationString != null && _deviceLocationString!.isNotEmpty) {
      subtitle = l10n.mapPickerCurrentLocationSubtitle;
    } else {
      subtitle = l10n.offlineCoordinates;
    }

    return ListTile(
      key: const ValueKey('nearby_picker_system_location_tile'),
      leading: Icon(
        Icons.my_location,
        color: _systemSelected
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: _systemSelected
          ? Icon(Icons.check, color: theme.colorScheme.primary)
          : null,
      selected: _systemSelected,
      onTap: _isConfirming
          ? null
          : () {
              setState(() {
                _systemSelected = true;
                _selectedPlace = null;
                _customSelectedPoiName = null;
              });
              _confirmSelection(place: null);
            },
    );
  }

  /// 在线地点服务故障提示（轻量重试按钮）
  Widget _buildErrorBanner(ThemeData theme, AppLocalizations l10n) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius:
            BorderRadius.circular(AppShapeTokens.of(context).cardRadius),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.onlinePlaceSearchUnavailable,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            onPressed: _isConfirming
                ? null
                : () => _fetchNearbyPlaces(isLoadMore: false),
            child: Text(l10n.retry),
          ),
        ],
      ),
    );
  }

  /// 候选 POI 条目
  Widget _buildPlaceTile(
    ThemeData theme,
    AppLocalizations l10n,
    PlaceInfo place,
  ) {
    final selected = !_systemSelected && _selectedPlace == place;
    final distance = _formatDistance(l10n, place.distanceMeters);

    return ListTile(
      leading: Icon(
        Icons.place_outlined,
        color: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(
        place.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: place.address != null
          ? Text(
              place.address!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (distance != null)
            Text(
              distance,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (selected) ...[
            const SizedBox(width: 8),
            Icon(Icons.check, color: theme.colorScheme.primary),
          ],
        ],
      ),
      selected: selected,
      onTap: _isConfirming
          ? null
          : () {
              setState(() {
                _systemSelected = false;
                _selectedPlace = place;
                _customSelectedPoiName = place.name;
                _customSelectedLatitude = place.latitude;
                _customSelectedLongitude = place.longitude;
              });
              _confirmSelection(place: place);
            },
    );
  }

  String? _formatDistance(AppLocalizations l10n, double? meters) {
    if (meters == null) return null;
    if (meters < 1000) {
      return l10n.mapPickerDistanceMeters(meters.round().toString());
    }
    return l10n.mapPickerDistanceKilometers(
      (meters / 1000).toStringAsFixed(1),
    );
  }
}
