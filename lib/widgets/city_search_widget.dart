import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_constants.dart';
import '../constants/popular_cities.dart';
import '../controllers/weather_search_controller.dart';
import '../gen_l10n/app_localizations.dart';
import '../services/location_service.dart';
import '../services/settings_service.dart';
import '../services/weather_service.dart';
import '../theme/theme_style.dart';
import '../widgets/app_empty_view.dart';
import '../widgets/app_loading_view.dart';
import '../widgets/app_snackbar.dart';

/// 城市搜索与选择组件
///
/// 支持即时热门城市选择、GPS 定位一键获取、拼音/中英文即时本地匹配与在线地理编码搜索。
class CitySearchWidget extends StatefulWidget {
  final WeatherSearchController weatherController;
  final VoidCallback? onSuccess;
  final String? initialCity;

  const CitySearchWidget({
    super.key,
    required this.weatherController,
    this.onSuccess,
    this.initialCity,
  });

  @override
  State<CitySearchWidget> createState() => _CitySearchWidgetState();
}

class _CitySearchWidgetState extends State<CitySearchWidget> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearchActive = false;
  Timer? _debounce;
  CityInfo? _selectingCity;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialCity != null && widget.initialCity!.isNotEmpty) {
      _searchController.text = widget.initialCity!;
      _isSearchActive = true;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    final locationService = Provider.of<LocationService>(
      context,
      listen: false,
    );
    final settingsService = Provider.of<SettingsService>(
      context,
      listen: false,
    );

    locationService.currentLocaleCode = settingsService.localeCode;

    _debounce?.cancel();
    final hasText = value.trim().isNotEmpty;
    setState(() {
      _isSearchActive = hasText;
    });

    if (!hasText) {
      locationService.clearSearchResults();
    } else {
      _debounce = Timer(AppConstants.searchDebounceDelay, () {
        if (mounted) {
          final currentQuery = _searchController.text.trim();
          if (currentQuery.isNotEmpty) {
            locationService.searchCity(currentQuery);
          } else {
            locationService.clearSearchResults();
          }
        }
      });
    }
  }

  Future<void> _useCurrentLocation() async {
    if (_isLocating || widget.weatherController.isLoading) return;

    setState(() {
      _isLocating = true;
    });

    final l10n = AppLocalizations.of(context);
    widget.weatherController.clearMessages();

    try {
      final success = await widget.weatherController.useCurrentLocation();

      if (!mounted) return;

      if (success) {
        final locationService = Provider.of<LocationService>(
          context,
          listen: false,
        );
        final cityName = locationService.city ?? locationService.currentAddress;
        AppSnackBar.success(
          context,
          l10n.currentLocationWeatherUpdated(
            (cityName != null && cityName.isNotEmpty)
                ? cityName
                : l10n.currentLocationLabel,
          ),
        );
        Navigator.of(context).pop();
        widget.onSuccess?.call();
      } else {
        final errorMsg =
            widget.weatherController.lastResult?.getLocalizedMessage(l10n) ??
                l10n.cannotGetCurrentLocation;
        AppSnackBar.error(context, errorMsg);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLocating = false;
        });
      }
    }
  }

  Future<void> _selectCity(CityInfo cityInfo) async {
    if (_selectingCity != null || widget.weatherController.isLoading) return;

    setState(() {
      _selectingCity = cityInfo;
    });

    final l10n = AppLocalizations.of(context);
    widget.weatherController.clearMessages();

    try {
      final success = await widget.weatherController.selectCityAndUpdateWeather(
        cityInfo,
      );

      if (!mounted) return;

      if (success) {
        AppSnackBar.success(context, l10n.citySelected(cityInfo.name));
        Navigator.of(context).pop();
        widget.onSuccess?.call();
      } else {
        final errorMsg =
            widget.weatherController.lastResult?.getLocalizedMessage(l10n) ??
                l10n.weatherFetchFailed;
        AppSnackBar.error(context, errorMsg);
      }
    } finally {
      if (mounted) {
        setState(() {
          _selectingCity = null;
        });
      }
    }
  }

  /// 合并本地即时匹配与远程搜索结果（去重）
  List<CityInfo> _getMergedSearchResults(LocationService locationService) {
    final query = _searchController.text.trim();
    if (query.isEmpty) return const [];

    final localMatches =
        PopularCitiesData.search(query).map((c) => c.toCityInfo()).toList();
    final remoteResults = locationService.searchResults;

    final combined = <CityInfo>[...localMatches];
    for (final remote in remoteResults) {
      if (!combined.contains(remote)) {
        combined.add(remote);
      }
    }
    return combined;
  }

  @override
  Widget build(BuildContext context) {
    final locationService = Provider.of<LocationService>(context);
    final weatherService = Provider.of<WeatherService>(context);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Consumer<WeatherSearchController>(
      builder: (context, controller, child) {
        final isBusy =
            controller.isLoading || _isLocating || _selectingCity != null;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部标题栏
            _buildHeader(context, theme, l10n),

            // 当前天气与定位状态英雄卡
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: _buildCurrentWeatherCard(
                context,
                theme,
                l10n,
                locationService,
                weatherService,
                isBusy,
              ),
            ),

            const SizedBox(height: 12),

            // 搜索输入栏
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: _buildSearchBar(
                context,
                theme,
                l10n,
                locationService,
                isBusy,
              ),
            ),

            // 搜索进度指示器
            if (locationService.isSearching || isBusy)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: LinearProgressIndicator(minHeight: 2),
              )
            else
              const SizedBox(height: 2),

            const SizedBox(height: 8),

            // 核心内容区（热门城市 / 搜索结果）
            Expanded(
              child: _buildBodyContent(
                context,
                theme,
                l10n,
                locationService,
                controller,
              ),
            ),

            // 底部数据来源说明
            _buildFooter(theme, l10n),
          ],
        );
      },
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    final shapeTokens = AppShapeTokens.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(shapeTokens.cardRadius),
            ),
            child: Icon(
              Icons.location_city_rounded,
              color: theme.colorScheme.onPrimaryContainer,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.selectCity,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  l10n.citySearchSubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentWeatherCard(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
    LocationService locationService,
    WeatherService weatherService,
    bool isBusy,
  ) {
    final shapeTokens = AppShapeTokens.of(context);
    final hasLocation = locationService.currentAddress != null &&
        locationService.currentAddress!.isNotEmpty;
    final hasWeather = weatherService.hasValidWeatherData;

    final weatherDesc = hasWeather
        ? WeatherService.getLocalizedWeatherDescription(
            l10n,
            weatherService.currentWeather ?? 'unknown',
          )
        : '';
    final tempText = weatherService.temperature ?? '';

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shapeTokens.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            // 天气图标容器
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color:
                    theme.colorScheme.primaryContainer.withValues(alpha: 0.7),
                shape: BoxShape.circle,
              ),
              child: Icon(
                weatherService.getWeatherIconData(),
                color: theme.colorScheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),

            // 天气与位置文本
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        hasWeather
                            ? '$weatherDesc $tempText'
                            : (weatherService.state == WeatherServiceState.error
                                ? l10n.weatherFetchFailed
                                : l10n.currentWeather),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (weatherService.isLoading) ...[
                        const SizedBox(width: 8),
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        Icons.place_outlined,
                        size: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          hasLocation
                              ? locationService.currentAddress!
                              : l10n.cityNotSetHint,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 快捷操作按钮：GPS 定位 & 刷新
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: l10n.refreshWeather,
                  onPressed: isBusy || weatherService.isLoading
                      ? null
                      : () async {
                          final position = locationService.currentPosition;
                          if (position != null) {
                            await weatherService.getWeatherData(
                              position.latitude,
                              position.longitude,
                              forceRefresh: true,
                            );
                            if (!context.mounted) return;
                            if (weatherService.hasValidWeatherData) {
                              AppSnackBar.success(context, l10n.weatherUpdated);
                            } else {
                              AppSnackBar.error(
                                  context, l10n.weatherUpdateFailed);
                            }
                          } else {
                            AppSnackBar.warning(
                              context,
                              l10n.pleaseSelectCityFirst,
                            );
                          }
                        },
                ),
                IconButton.filledTonal(
                  icon: _isLocating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location_rounded),
                  tooltip: l10n.locateCurrentPosition,
                  onPressed: isBusy ? null : _useCurrentLocation,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
    LocationService locationService,
    bool isBusy,
  ) {
    final shapeTokens = AppShapeTokens.of(context);

    return TextField(
      controller: _searchController,
      enabled: !isBusy,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: l10n.searchCityHint,
        hintStyle: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          color: theme.colorScheme.primary,
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
          vertical: 12,
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
    );
  }

  Widget _buildBodyContent(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
    LocationService locationService,
    WeatherSearchController controller,
  ) {
    if (!_isSearchActive) {
      return _buildPresetPopularCities(context, theme, l10n, locationService);
    }

    final mergedResults = _getMergedSearchResults(locationService);

    if (mergedResults.isEmpty) {
      if (locationService.isSearching) {
        return AppLoadingView(
          message: l10n.searchingCity,
          size: 60,
        );
      }
      return AppEmptyView(
        text: l10n.noCityFound,
        message: l10n.tryDifferentKeywords,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: mergedResults.length,
      itemBuilder: (context, index) {
        final city = mergedResults[index];
        final isSelected = _selectingCity == city;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3.0),
          child: _buildCityResultTile(
            context,
            theme,
            city,
            isSelected,
          ),
        );
      },
    );
  }

  Widget _buildPresetPopularCities(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
    LocationService locationService,
  ) {
    final currentCityName = locationService.city;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      children: [
        // 快捷 GPS 定位选项
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: OutlinedButton.icon(
            icon: _isLocating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location_rounded, size: 18),
            label: Text(
              _isLocating ? l10n.locating : l10n.locateCurrentPosition,
              style: theme.textTheme.labelLarge,
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  AppShapeTokens.of(context).buttonRadius,
                ),
              ),
            ),
            onPressed: _isLocating ? null : _useCurrentLocation,
          ),
        ),

        // 国内主要城市
        Row(
          children: [
            Icon(
              Icons.trending_up_rounded,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              l10n.domesticCities,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: PopularCitiesData.domestic.map((city) {
            final isCurrent = currentCityName == city.name;
            return _buildPopularCityChip(
              context,
              theme,
              city,
              isCurrent,
            );
          }).toList(),
        ),

        const SizedBox(height: 16),

        // 国际主要城市
        Row(
          children: [
            Icon(
              Icons.public_rounded,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              l10n.internationalCities,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: PopularCitiesData.international.map((city) {
            final isCurrent = currentCityName == city.name;
            return _buildPopularCityChip(
              context,
              theme,
              city,
              isCurrent,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildPopularCityChip(
    BuildContext context,
    ThemeData theme,
    PopularCity city,
    bool isCurrent,
  ) {
    final shapeTokens = AppShapeTokens.of(context);
    final isThisSelecting = _selectingCity?.name == city.name;

    return ActionChip(
      avatar: isThisSelecting
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : (isCurrent
              ? Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: theme.colorScheme.primary,
                )
              : null),
      label: Text(
        city.name,
        style: theme.textTheme.labelMedium?.copyWith(
          color: isCurrent
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurface,
          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      backgroundColor: isCurrent
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.6)
          : theme.colorScheme.surfaceContainerLow,
      side: BorderSide(
        color: isCurrent
            ? theme.colorScheme.primary
            : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shapeTokens.buttonRadius),
      ),
      onPressed: isThisSelecting ? null : () => _selectCity(city.toCityInfo()),
    );
  }

  Widget _buildCityResultTile(
    BuildContext context,
    ThemeData theme,
    CityInfo city,
    bool isSelected,
  ) {
    final shapeTokens = AppShapeTokens.of(context);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: isSelected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
          : theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shapeTokens.cardRadius),
        side: BorderSide(
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shapeTokens.cardRadius),
        ),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.location_on_rounded,
            size: 18,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          city.name,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          city.fullName,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: isSelected
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
        onTap: isSelected ? null : () => _selectCity(city),
      ),
    );
  }

  Widget _buildFooter(ThemeData theme, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_outlined,
            size: 13,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            l10n.weatherProvidedBy,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
