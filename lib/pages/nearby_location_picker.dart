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

  final List<PlaceInfo> _places = [];
  bool _isLoadingPlaces = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _placesError = false;

  int _currentOffset = 0;
  static const int _pageSize = 20;

  late bool _systemSelected;
  PlaceInfo? _selectedPlace;
  String? _customSelectedPoiName;
  double? _customSelectedLatitude;
  double? _customSelectedLongitude;

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
  void dispose() {
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

      final pos = await locService.getCurrentLocation();
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
    // 若用户传入的 initialPoiName 与设备当前 POI 相同，则视同选中系统当前位置
    if (_customSelectedPoiName != null &&
        _devicePoiName != null &&
        _customSelectedPoiName == _devicePoiName) {
      _systemSelected = true;
      _customSelectedPoiName = null;
    }

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

    _fetchNearbyPlaces(isLoadMore: false);
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
      final keyword = _locationService?.district ??
          _locationService?.city ??
          _devicePoiName ??
          '';
      final localeCode = Localizations.localeOf(context).languageCode;

      final results = await _placeSearch.getNearbyPlaces(
        _deviceLatitude!,
        _deviceLongitude!,
        categoryOrKeyword: keyword.isNotEmpty ? keyword : null,
        localeCode: localeCode,
        limit: _pageSize,
        offset: _currentOffset,
      );

      if (!mounted) return;

      // 严格保证在 5 公里半径之内
      final validPlaces =
          results.where((p) => (p.distanceMeters ?? 0) <= 5000).toList();

      final existingNames = _places.map((p) => p.name).toSet();
      final List<PlaceInfo> newUnique = [];
      for (final p in validPlaces) {
        if (!existingNames.contains(p.name)) {
          existingNames.add(p.name);
          newUnique.add(p);
        }
      }

      // 如果当前选中的是之前传入的 POI，在候选列表中定位对应条目
      if (_customSelectedPoiName != null && _selectedPlace == null) {
        for (final p in _places.followedBy(newUnique)) {
          if (p.name == _customSelectedPoiName) {
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
        if (results.length < _pageSize) {
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

  void _confirmSelection({PlaceInfo? place}) {
    if (_customSelectedPoiName != null &&
        _customSelectedPoiName == widget.initialPoiName &&
        (place == null || place.name == widget.initialPoiName)) {
      // 意图保留初始 POI（无论是否在附近列表中定位到对应条目，均统一走保留初始位置逻辑）
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
      // 用户从列表中点选的 POI：优先使用 place.address，避免跨区县时误用 _deviceLocationString
      final placeLoc =
          (place.address != null && place.address!.trim().isNotEmpty)
              ? place.address!.trim()
              : null;
      Navigator.of(context).pop(
        LocationPickerResult(
          latitude: place.latitude,
          longitude: place.longitude,
          location: placeLoc,
          poiName: place.name,
        ),
      );
    } else if (_systemSelected) {
      // 选中当前设备位置（离线反查失败时保留精确经纬度）
      Navigator.of(context).pop(
        LocationPickerResult(
          latitude: _deviceLatitude!,
          longitude: _deviceLongitude!,
          location: _deviceLocationString,
          poiName: _devicePoiName,
        ),
      );
    } else if (_customSelectedPoiName != null &&
        _customSelectedLatitude != null &&
        _customSelectedLongitude != null) {
      // 保留原本选中的候选 POI
      Navigator.of(context).pop(
        LocationPickerResult(
          latitude: _customSelectedLatitude!,
          longitude: _customSelectedLongitude!,
          location: widget.initialLocation,
          poiName: _customSelectedPoiName,
        ),
      );
    } else {
      Navigator.of(context).pop(
        LocationPickerResult(
          latitude: _deviceLatitude!,
          longitude: _deviceLongitude!,
          location: _deviceLocationString,
          poiName: _devicePoiName,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.nearbyLocationTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: l10n.mapPickerConfirm,
            onPressed: (_deviceLatitude == null || _deviceLongitude == null)
                ? null
                : () => _confirmSelection(
                      place: _systemSelected ? null : _selectedPlace,
                    ),
          ),
        ],
      ),
      body: _buildBody(theme, l10n),
    );
  }

  Widget _buildBody(ThemeData theme, AppLocalizations l10n) {
    if (_isLocating) {
      return Center(
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
    }

    if (_locatingFailed &&
        (_deviceLatitude == null || _deviceLongitude == null)) {
      return Center(
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
    }

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
    if (_devicePoiName != null && _devicePoiName!.isNotEmpty) {
      title = LocationService.formatPoiForDisplay(
        _devicePoiName,
        _deviceLocationString,
      );
    } else if (_deviceLocationString != null &&
        _deviceLocationString!.isNotEmpty) {
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
      onTap: () {
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
            onPressed: () => _fetchNearbyPlaces(isLoadMore: false),
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
    final selected = !_systemSelected &&
        (_selectedPlace == place ||
            (_selectedPlace == null && place.name == _customSelectedPoiName));
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
      onTap: () {
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
