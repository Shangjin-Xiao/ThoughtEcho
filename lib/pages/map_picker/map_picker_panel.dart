part of '../map_location_picker_page.dart';

/// 选点页地图下方的候选列表与确认区。
extension _MapPickerPanel on _MapLocationPickerPageState {
  /// 面板最多占屏幕这么高。
  ///
  /// 超过一半地图就看不清了；不到内容高度时面板会自己收缩，只有两条候选时
  /// 不会留一大片空白。
  static const double _maxHeightFactor = 0.42;

  Widget _buildPanel(ThemeData theme, AppLocalizations l10n) {
    final radius = AppShapeTokens.of(context).cardRadius;

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      elevation: 3,
      shadowColor: theme.colorScheme.shadow,
      borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * _maxHeightFactor,
              ),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _buildSelectedPointTile(theme, l10n),
                  _buildCurrentLocationTile(theme, l10n),
                  ..._buildSearchSection(theme, l10n),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _confirming ? null : _confirm,
                  icon: _confirming
                      ? AppInlineLoadingIndicator(
                          color: theme.colorScheme.onPrimary,
                        )
                      : const Icon(Icons.check),
                  label: Text(l10n.mapPickerConfirm),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 地图中心那个点。这是默认选中的一条。
  Widget _buildSelectedPointTile(ThemeData theme, AppLocalizations l10n) {
    final selected = !_cityLevelOnly;
    final address = _resolvedAddress;

    // 搜索选中的地点名不需要等反查，先显示出来
    final pendingName = _pickedPlace == null && _resolving;

    final String title;
    if (pendingName) {
      title = l10n.mapPickerResolvingPoint;
    } else {
      final name = _pickedPlace?.name ?? address?['poi_name']?.trim();
      title =
          (name == null || name.isEmpty) ? l10n.mapPickerUnnamedPoint : name;
    }

    final areaText = LocationService.buildStorageLocation(address);
    final detail = areaText == null
        ? LocationService.formatCoordinates(
            _center.latitude,
            _center.longitude,
            precision: 4,
          )
        : LocationService.formatLocationForDisplay(areaText);

    return ListTile(
      leading: pendingName
          ? const SizedBox(
              width: 24,
              height: 24,
              child: Center(child: AppInlineLoadingIndicator()),
            )
          : Icon(Icons.place_outlined, color: theme.colorScheme.primary),
      title: Text(title),
      subtitle: Text(
        detail.isEmpty
            ? l10n.mapPickerSelectedPoint
            : '${l10n.mapPickerSelectedPoint} · $detail',
      ),
      trailing: selected
          ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
          : null,
      selected: selected,
      onTap: _selectMapPoint,
    );
  }

  /// 「当前位置」：只记城市和区县，不给这条笔记落一个具体地点名。
  Widget _buildCurrentLocationTile(ThemeData theme, AppLocalizations l10n) {
    return ListTile(
      leading: Icon(
        Icons.my_location,
        color: _cityLevelOnly
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(l10n.mapPickerCurrentLocation),
      subtitle: Text(l10n.mapPickerCurrentLocationSubtitle),
      trailing: _cityLevelOnly
          ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
          : null,
      selected: _cityLevelOnly,
      onTap: () => _moveToDeviceLocation(asCurrentLocation: true),
    );
  }

  List<Widget> _buildSearchSection(ThemeData theme, AppLocalizations l10n) {
    if (!_searchVisible) return const [];

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Text(
            l10n.mapPickerSearchResults,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_searching) ...[
            const SizedBox(width: 8),
            const AppInlineLoadingIndicator(),
          ],
        ],
      ),
    );

    if (_results.isEmpty) {
      return [
        const Divider(height: 1),
        header,
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            _searching ? l10n.mapPickerSearching : l10n.mapPickerNoResults,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ];
    }

    return [
      const Divider(height: 1),
      header,
      ..._results.map((place) => _buildPlaceTile(theme, l10n, place)),
    ];
  }

  Widget _buildPlaceTile(
    ThemeData theme,
    AppLocalizations l10n,
    PlaceInfo place,
  ) {
    final selected = identical(_pickedPlace, place);
    final distance = _formatDistance(l10n, place.distanceMeters);

    return ListTile(
      leading: Icon(
        Icons.location_on_outlined,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(place.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: place.address == null
          ? null
          : Text(
              place.address!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: distance == null
          ? null
          : Text(
              distance,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      selected: selected,
      onTap: () => _selectPlace(place),
    );
  }

  /// 一公里以内按米给整数，再远按公里给一位小数。
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
