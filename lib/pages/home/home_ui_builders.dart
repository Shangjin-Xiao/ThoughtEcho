part of '../home_page.dart';

/// Extension for UI building methods
extension _HomeUIBuilders on _HomePageState {
  /// 构建首页位置天气显示（保持原有样式，只改文字）
  Widget _buildLocationWeatherDisplay(
    BuildContext context,
    LocationService locationService,
    WeatherService weatherService,
  ) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final connectivityService = Provider.of<ConnectivityService>(context);
    final isConnected = connectivityService.isConnected;
    final hasPermission = locationService.hasLocationPermission;
    final isServiceEnabled = locationService.isLocationServiceEnabled;
    final hasCoordinates = locationService.hasCoordinates;
    final hasCity =
        locationService.city != null && locationService.city!.isNotEmpty;
    final hasWeather = weatherService.currentWeather != null &&
        weatherService.currentWeather != 'error' &&
        weatherService.currentWeather != 'unknown';

    String locationText;
    String weatherText;
    IconData weatherIcon;

    // --- 构建天气文本的辅助函数 ---
    String buildWeatherText() {
      return '${WeatherService.getLocalizedWeatherDescription(l10n, weatherService.currentWeather!)}'
          '${weatherService.temperature != null && weatherService.temperature!.isNotEmpty ? ' ${weatherService.temperature}' : ''}';
    }

    // --- 优先级链：位置显示 ---
    if (hasCity) {
      // 有城市信息（可能来自 GPS 解析或手动搜索城市）
      locationText = locationService.getDisplayLocation();
    } else if (hasCoordinates) {
      // 有坐标但没有城市名（离线 GPS 或解析中）
      locationText = LocationService.formatCoordinates(
        locationService.currentPosition!.latitude,
        locationService.currentPosition!.longitude,
      );
    } else if (!isServiceEnabled) {
      // P3: 位置服务未启用（优先于权限文案）
      locationText = l10n.tileLocationServiceOff;
    } else if (!hasPermission) {
      // 有位置服务但没有权限
      locationText = l10n.tileNoLocationPermission;
    } else if (!isConnected) {
      locationText = l10n.tileNoNetwork;
    } else {
      locationText = l10n.tileLoading;
    }

    // --- 优先级链：天气显示 ---
    // P5: 不再把天气显示绑死在权限上；只要有天气数据就显示
    if (hasWeather) {
      weatherText = buildWeatherText();
      weatherIcon = weatherService.getWeatherIconData();
    } else if (!hasCoordinates && !hasCity) {
      // 完全没有位置坐标，天气无法获取
      if (!isConnected) {
        weatherText = l10n.tileOffline;
        weatherIcon = Icons.cloud_off;
      } else {
        weatherText = '--';
        weatherIcon = Icons.cloud_off;
      }
    } else if (isConnected) {
      weatherText = l10n.tileLoading;
      weatherIcon = Icons.cloud_queue;
    } else {
      weatherText = l10n.tileNoWeather;
      weatherIcon = Icons.cloud_off;
    }

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          boxShadow: AppTheme.defaultShadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_on,
              size: 14,
              color: theme.colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 4),
            Text(
              locationText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '|',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer.withAlpha(128),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              weatherIcon,
              size: 18,
              color: theme.colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 4),
            Text(
              weatherText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  SystemUiOverlayStyle _buildSystemUiOverlayStyle(
    ThemeData theme,
    Color navColor,
  ) {
    final navBrightness = ThemeData.estimateBrightnessForColor(navColor);
    final bool navIconsShouldBeDark = navBrightness == Brightness.light;
    final bool statusIconsShouldBeDark = theme.brightness == Brightness.light;

    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness:
          statusIconsShouldBeDark ? Brightness.dark : Brightness.light,
      statusBarBrightness:
          statusIconsShouldBeDark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: navColor,
      systemNavigationBarIconBrightness:
          navIconsShouldBeDark ? Brightness.dark : Brightness.light,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    );
  }
}
