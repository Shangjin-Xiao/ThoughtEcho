import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../gen_l10n/app_localizations.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../services/settings_service.dart';
import '../controllers/weather_search_controller.dart';
import '../utils/lottie_animation_manager.dart';

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
  final Duration _debounceDuration = const Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    if (widget.initialCity != null) {
      _searchController.text = widget.initialCity!;
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

    // 同步语言设置到 LocationService
    locationService.currentLocaleCode = settingsService.localeCode;

    // 取消之前的计时器
    _debounce?.cancel();
    // 更新搜索状态
    setState(() {
      _isSearchActive = value.isNotEmpty;
    });

    // 如果输入为空，立即清空结果
    if (!_isSearchActive) {
      locationService.clearSearchResults();
    } else {
      // 启动新的计时器
      _debounce = Timer(_debounceDuration, () {
        if (mounted) {
          final currentQuery = _searchController.text;
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
    widget.weatherController.clearMessages();
    final success = await widget.weatherController.useCurrentLocation();

    if (success && mounted) {
      // 延迟关闭对话框，让用户看到成功消息
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        Navigator.of(context).pop();
        widget.onSuccess?.call();
      }
    }
  }

  Future<void> _selectCity(CityInfo cityInfo) async {
    widget.weatherController.clearMessages();
    final success = await widget.weatherController.selectCityAndUpdateWeather(
      cityInfo,
    );

    if (success && mounted) {
      // 延迟关闭对话框，让用户看到成功消息
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        Navigator.of(context).pop();
        widget.onSuccess?.call();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final locationService = Provider.of<LocationService>(context);
    final weatherService = Provider.of<WeatherService>(context);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Consumer<WeatherSearchController>(
      builder: (context, controller, child) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            AppBar(
              title: Text(l10n.selectCity),
              elevation: 0,
              backgroundColor: Colors.transparent,
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),

            // 当前天气简要信息与刷新
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                child: ListTile(
                  leading: Icon(weatherService.getWeatherIconData()),
                  title: Text(l10n.currentWeather),
                  subtitle: Text(
                    (weatherService.currentWeather == null &&
                            weatherService.temperature == null)
                        ? (locationService.currentAddress != null
                              ? l10n.clickRefreshHint(
                                  locationService.currentAddress!,
                                )
                              : l10n.cityNotSetHint)
                        : (weatherService.currentWeather == '天气数据获取失败'
                              ? l10n.weatherFetchFailed
                              : '${WeatherService.getLocalizedWeatherDescription(AppLocalizations.of(context), weatherService.currentWeather ?? 'unknown')} ${weatherService.temperature ?? ""}'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: controller.isLoading || weatherService.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    tooltip: l10n.refreshWeather,
                    onPressed:
                        (controller.isLoading || weatherService.isLoading)
                        ? null
                        : () async {
                            final position = locationService.currentPosition;
                            final messenger = ScaffoldMessenger.maybeOf(
                              context,
                            );
                            if (position != null) {
                              await weatherService.getWeatherData(
                                position.latitude,
                                position.longitude,
                              );
                              if (!mounted) return;
                              if (weatherService.currentWeather != '天气数据获取失败') {
                                messenger?.showSnackBar(
                                  SnackBar(
                                    content: Text(l10n.weatherUpdated),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              } else {
                                messenger?.showSnackBar(
                                  SnackBar(
                                    content: Text(l10n.weatherUpdateFailed),
                                    duration: const Duration(seconds: 3),
                                  ),
                                );
                              }
                            } else {
                              if (!mounted) return;
                              messenger?.showSnackBar(
                                SnackBar(
                                  content: Text(l10n.pleaseSelectCityFirst),
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            }
                          },
                  ),
                ),
              ),
            ),

            // 搜索框
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context).searchCity,
                  prefixIcon: Icon(
                    Icons.search,
                    color: theme.colorScheme.primary,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.clear,
                            color: theme.colorScheme.primary,
                          ),
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                              _isSearchActive = false;
                            });
                            locationService.clearSearchResults();
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16.0),
                    borderSide: BorderSide(color: theme.colorScheme.primary),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16.0),
                    borderSide: BorderSide(color: theme.colorScheme.outline),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16.0),
                    borderSide: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 2.0,
                    ),
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surface,
                ),
                enabled: !controller.isLoading,
                onChanged: _onSearchChanged,
              ),
            ),

            // 错误或成功消息
            if (controller.errorMessage != null ||
                controller.successMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: controller.errorMessage != null
                        ? theme.colorScheme.errorContainer
                        : theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        controller.errorMessage != null
                            ? Icons.error
                            : Icons.check_circle,
                        color: controller.errorMessage != null
                            ? theme.colorScheme.onErrorContainer
                            : theme.colorScheme.onPrimaryContainer,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          controller.errorMessage ?? controller.successMessage!,
                          style: TextStyle(
                            color: controller.errorMessage != null
                                ? theme.colorScheme.onErrorContainer
                                : theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 8),

            // 搜索结果或加载状态
            Expanded(child: _buildContent(locationService, controller, l10n)),

            // 当前位置按钮
            if (locationService.isLocationServiceEnabled)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: ElevatedButton.icon(
                  icon: controller.isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: EnhancedLottieAnimation(
                            type: LottieAnimationType.loading,
                            width: 16,
                            height: 16,
                          ),
                        )
                      : const Icon(Icons.my_location),
                  label: Text(l10n.useCurrentLocation),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  onPressed: controller.isLoading ? null : _useCurrentLocation,
                ),
              ),

            // API提供商信息
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.cloud_outlined,
                    size: 14,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    l10n.weatherProvidedBy,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildContent(
    LocationService locationService,
    WeatherSearchController controller,
    AppLocalizations l10n,
  ) {
    // 如果控制器正在加载，显示加载指示器
    if (controller.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = (constraints.maxHeight * 0.7).clamp(
                    120.0,
                    300.0,
                  );
                  return EnhancedLottieAnimation(
                    type: LottieAnimationType.weatherSearchLoading,
                    width: size,
                    height: size,
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Text(l10n.processing),
          ],
        ),
      );
    }
    // 如果位置服务正在搜索，显示搜索加载状态
    if (locationService.isSearching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = (constraints.maxHeight * 0.7).clamp(
                    120.0,
                    300.0,
                  );
                  return EnhancedLottieAnimation(
                    type: LottieAnimationType.weatherSearchLoading,
                    width: size,
                    height: size,
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Text(l10n.searchingCity),
          ],
        ),
      );
    }

    // 如果搜索激活但没有结果
    if (_isSearchActive && locationService.searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(l10n.noCityFound),
            const SizedBox(height: 8),
            Text(
              l10n.tryDifferentKeywords,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      );
    }

    // 如果没有激活搜索，显示提示
    if (!_isSearchActive) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(l10n.enterCityToSearch),
          ],
        ),
      );
    }

    // 显示搜索结果
    return ListView.builder(
      itemCount: locationService.searchResults.length,
      itemBuilder: (context, index) {
        final city = locationService.searchResults[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            title: Text(
              city.name,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Text(city.fullName),
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(
                Icons.location_city,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            trailing: controller.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: EnhancedLottieAnimation(
                      type: LottieAnimationType.loading,
                      width: 16,
                      height: 16,
                    ),
                  )
                : Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
            onTap: controller.isLoading ? null : () => _selectCity(city),
          ),
        );
      },
    );
  }
}
