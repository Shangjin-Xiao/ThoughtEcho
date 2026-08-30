import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../gen_l10n/app_localizations.dart';
import '../services/location_service.dart';
import '../services/place_search_service.dart';
import '../theme/theme_style.dart';
import '../utils/app_logger.dart';
import '../widgets/app_loading_view.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/map/osm_map_layers.dart';

part 'map_picker/map_picker_panel.dart';

/// 地图选点页的返回值。
class MapPickerResult {
  const MapPickerResult({
    required this.latitude,
    required this.longitude,
    this.location,
    this.poiName,
  });

  final double latitude;
  final double longitude;

  /// 入库格式的行政区串 `国家,省份,城市,区县`；反查失败时为 null。
  ///
  /// 不是 `formatted_address`——见 [LocationService.buildStorageLocation]。
  final String? location;

  /// 用户选中的地点名（"芝公园"）。
  ///
  /// 选了「当前位置」、或这个坐标上没有可命名的地点时为 null，此时这条笔记
  /// 只记到行政区一级，和没用过选点的笔记一样。
  final String? poiName;
}

/// 地图选点页：给一条笔记标一个精确地点。
///
/// 从全屏编辑器长按位置按钮进入。用户拖地图定点、或搜索一个地点，确认后回传
/// [MapPickerResult]。
class MapLocationPickerPage extends StatefulWidget {
  const MapLocationPickerPage({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
  });

  /// 笔记已有坐标时以它为初始中心；为空则先取一次设备定位。
  final double? initialLatitude;
  final double? initialLongitude;

  @override
  State<MapLocationPickerPage> createState() => _MapLocationPickerPageState();
}

class _MapLocationPickerPageState extends State<MapLocationPickerPage> {
  /// 既没有传入坐标、定位又失败时的兜底中心（北京天安门）。
  ///
  /// 与其给一张全球视野的空地图，不如落在一个具体城市，用户至少知道要往哪拖。
  static const LatLng _fallbackCenter = LatLng(39.9042, 116.4074);

  /// 选中一个点之后的缩放级别：能看清街区，但还留得住周边参照。
  static const double _pointZoom = 16;
  static const double _fallbackZoom = 12;

  /// 拖动停下多久才反查一次。
  ///
  /// Nominatim 的公共服务限 1 请求/秒，拖动过程中每一帧都反查必被限流；
  /// 900ms 也刚好是「手指离开、看一眼地名」的节奏。
  static const Duration _reverseDebounce = Duration(milliseconds: 900);
  static const Duration _searchDebounce = Duration(milliseconds: 500);

  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final PlaceSearchService _placeSearch = NominatimPlaceSearchService();

  Timer? _reverseTimer;
  Timer? _searchTimer;

  /// 地图当前的中心，也就是「待确认的那个点」。
  late LatLng _center;

  /// [_resolvedAddress] 对应的坐标。
  ///
  /// 和 [_center] 分开存：反查是异步的，结果回来时用户可能已经拖到别处，
  /// 靠这个判断手上的地址还算不算数。
  LatLng? _resolvedPoint;
  Map<String, String?>? _resolvedAddress;
  bool _resolving = false;
  bool _locating = false;
  bool _confirming = false;

  /// 用户从搜索结果里选中的地点，它的名字覆盖反查给出的名字。
  ///
  /// 用户自己拖动地图后作废——那说明他要的不是搜出来的那个点了。
  PlaceInfo? _pickedPlace;

  /// 选了「当前位置」：只记行政区，不记具体地点。
  bool _cityLevelOnly = false;

  bool _searchVisible = false;
  bool _searching = false;
  List<PlaceInfo> _results = const [];

  /// 搜索请求的序号，用来丢弃过期响应。
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    final lat = widget.initialLatitude;
    final lon = widget.initialLongitude;
    final hasInitialPoint = lat != null && lon != null;
    _center = hasInitialPoint ? LatLng(lat, lon) : _fallbackCenter;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (hasInitialPoint) {
        _resolveCenter();
      } else {
        // 没有已有坐标就以设备位置开局，但不当成用户「选了当前位置」——
        // 他还没做选择，拖一下就该是普通选点。
        _moveToDeviceLocation(asCurrentLocation: false);
      }
    });
  }

  @override
  void dispose() {
    _reverseTimer?.cancel();
    _searchTimer?.cancel();
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- 定位与反查

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    _center = camera.center;

    // 只有用户自己拖动才作废之前的选择：程序化 move（搜索结果、回到当前位置）
    // 同样会走到这里，那是我们自己设的选择，不能被它清掉。
    if (hasGesture && (_pickedPlace != null || _cityLevelOnly)) {
      setState(() {
        _pickedPlace = null;
        _cityLevelOnly = false;
      });
    }

    _reverseTimer?.cancel();
    _reverseTimer = Timer(_reverseDebounce, _resolveCenter);
  }

  Future<void> _resolveCenter() async {
    final point = _center;
    if (_resolvedPoint == point) return;

    final locationService = context.read<LocationService>();
    setState(() => _resolving = true);

    Map<String, String?>? address;
    try {
      address = await locationService.reverseGeocodePoint(
        point.latitude,
        point.longitude,
      );
    } catch (e, stack) {
      logError(
        '反查选点地址失败',
        error: e,
        stackTrace: stack,
        source: 'MapLocationPickerPage',
      );
    }

    if (!mounted) return;
    // 反查期间用户又拖走了，这个结果已经不是当前这个点的
    if (_center != point) {
      setState(() => _resolving = false);
      return;
    }
    setState(() {
      _resolvedPoint = point;
      _resolvedAddress = address;
      _resolving = false;
    });
  }

  Future<void> _moveToDeviceLocation({required bool asCurrentLocation}) async {
    if (_locating) return;

    final locationService = context.read<LocationService>();
    final l10n = AppLocalizations.of(context);
    setState(() => _locating = true);

    try {
      final position = locationService.currentPosition ??
          await locationService.getCurrentLocation(highAccuracy: false);
      if (!mounted) return;

      if (position == null) {
        AppSnackBar.error(context, l10n.cannotGetLocationDesc);
        return;
      }

      final point = LatLng(position.latitude, position.longitude);
      setState(() {
        _center = point;
        _pickedPlace = null;
        _cityLevelOnly = asCurrentLocation;
      });
      _mapController.move(point, _pointZoom);
    } catch (e, stack) {
      logError(
        '获取设备位置失败',
        error: e,
        stackTrace: stack,
        source: 'MapLocationPickerPage',
      );
      if (mounted) AppSnackBar.error(context, l10n.cannotGetLocationDesc);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  // -------------------------------------------------------------------- 搜索

  void _toggleSearch() {
    setState(() {
      _searchVisible = !_searchVisible;
      if (!_searchVisible) {
        _searchTimer?.cancel();
        _searchToken++;
        _searchController.clear();
        _results = const [];
        _searching = false;
      }
    });
    if (!_searchVisible) FocusScope.of(context).unfocus();
  }

  void _onSearchChanged(String value) {
    _searchTimer?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      _searchToken++;
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    _searchTimer = Timer(_searchDebounce, () => _runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    final token = ++_searchToken;
    final localeCode = context.read<LocationService>().currentLocaleCode;
    setState(() => _searching = true);

    final results = await _placeSearch.searchNearby(
      _center.latitude,
      _center.longitude,
      query: query,
      localeCode: localeCode,
    );

    // 用户已经改了关键词，这批结果是上一次的
    if (!mounted || token != _searchToken) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  /// 把选择切回「地图上的选点」。
  ///
  /// 面板在 extension 里，`setState` 只能在 State 的实例成员里调用，所以这一
  /// 步放在这边。
  void _selectMapPoint() {
    if (!_cityLevelOnly) return;
    setState(() => _cityLevelOnly = false);
  }

  void _selectPlace(PlaceInfo place) {
    final point = LatLng(place.latitude, place.longitude);
    setState(() {
      _center = point;
      _pickedPlace = place;
      _cityLevelOnly = false;
      // 行政区要按新坐标重新反查，否则副行还写着上一个点的城市
      _resolvedPoint = null;
    });
    _mapController.move(point, _pointZoom);
    FocusScope.of(context).unfocus();
  }

  // -------------------------------------------------------------------- 确认

  Future<void> _confirm() async {
    if (_confirming) return;
    setState(() => _confirming = true);

    try {
      // 拖完立刻按确认时反查还没跑；补一次，别让用户拿到一条只有坐标没有
      // 地址的记录——卡片上那就只能显示一串经纬度。
      if (_resolvedPoint != _center) {
        _reverseTimer?.cancel();
        await _resolveCenter();
      }
      if (!mounted) return;

      final address = _resolvedAddress;
      final poiName =
          _cityLevelOnly ? null : (_pickedPlace?.name ?? address?['poi_name']);

      Navigator.of(context).pop(
        MapPickerResult(
          latitude: _center.latitude,
          longitude: _center.longitude,
          location: LocationService.buildStorageLocation(address),
          poiName: poiName?.trim().isEmpty ?? true ? null : poiName!.trim(),
        ),
      );
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  // -------------------------------------------------------------------- 构建

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: _searchVisible
            ? TextField(
                controller: _searchController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: l10n.mapPickerSearchHint,
                ),
                onChanged: _onSearchChanged,
                onSubmitted: (value) {
                  _searchTimer?.cancel();
                  final query = value.trim();
                  if (query.isEmpty) {
                    _searchToken++;
                    setState(() {
                      _results = const [];
                      _searching = false;
                    });
                    return;
                  }
                  _runSearch(query);
                },
              )
            : Text(l10n.mapPickerTitle),
        actions: [
          IconButton(
            icon: Icon(_searchVisible ? Icons.close : Icons.search),
            tooltip: _searchVisible ? l10n.cancel : l10n.mapPickerSearchHint,
            onPressed: _toggleSearch,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMap(theme, l10n)),
          _buildPanel(theme, l10n),
        ],
      ),
    );
  }

  Widget _buildMap(ThemeData theme, AppLocalizations l10n) {
    return Stack(
      children: [
        RepaintBoundary(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom:
                  widget.initialLatitude != null ? _pointZoom : _fallbackZoom,
              onPositionChanged: _onPositionChanged,
              backgroundColor: theme.colorScheme.surfaceContainerLow,
            ),
            children: [OsmMapLayers.tiles(), OsmMapLayers.attribution()],
          ),
        ),
        // 定位针钉在屏幕中心，跟着地图一起动的是底图——这样"选的是哪个点"
        // 永远只有一个答案，不用先点一下再拖。
        IgnorePointer(
          child: Center(
            child: Transform.translate(
              offset: const Offset(0, -16),
              child: Icon(
                Icons.place,
                size: 40,
                color: theme.colorScheme.primary,
                shadows: [
                  Shadow(
                    color: theme.colorScheme.shadow.withValues(alpha: 0.4),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.small(
            heroTag: 'map_picker_locate',
            tooltip: l10n.mapPickerLocateMe,
            onPressed: _locating
                ? null
                : () => _moveToDeviceLocation(asCurrentLocation: false),
            child: _locating
                ? const AppInlineLoadingIndicator()
                : const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }
}
