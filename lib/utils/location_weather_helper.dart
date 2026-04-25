import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../gen_l10n/app_localizations.dart';
import '../utils/app_logger.dart';

/// Result object for location and weather fetch operations.
class LocationWeatherResult {
  final double? latitude;
  final double? longitude;
  final String? address;
  final String? weather;
  final String? temperature;
  final bool permissionDenied;

  LocationWeatherResult({
    this.latitude,
    this.longitude,
    this.address,
    this.weather,
    this.temperature,
    this.permissionDenied = false,
  });

  bool get hasLocation => latitude != null && longitude != null;
  bool get hasWeather => weather != null;
}

/// Helper class to extract repetitive location and weather retrieval logic.
class LocationWeatherHelper {
  /// Fetches current location and optionally weather data.
  ///
  /// Handles permission requests and shows error dialogs if requested.
  static Future<LocationWeatherResult> fetch({
    required BuildContext context,
    bool includeWeather = true,
    bool showPermissionDialog = true,
    bool showLocationErrorDialog = true,
    bool showWeatherErrorDialog = true,
    String? locationErrorTitle,
    String? locationErrorContent,
  }) async {
    final locationService = Provider.of<LocationService>(
      context,
      listen: false,
    );
    final l10n = AppLocalizations.of(context);

    // 1. Check and Request Permissions
    if (!locationService.hasLocationPermission) {
      bool permissionGranted = await locationService
          .requestLocationPermission();
      if (!permissionGranted) {
        if (showPermissionDialog && context.mounted) {
          _showErrorDialog(
            context,
            l10n.cannotGetLocationTitle,
            l10n.cannotGetLocationPermissionShort,
          );
        }
        return LocationWeatherResult(permissionDenied: true);
      }
    }

    // 2. Get Current Location
    Position? position;
    try {
      position = await locationService.getCurrentLocation();
    } catch (e) {
      logError('LocationWeatherHelper: Failed to get location', error: e);
      if (showLocationErrorDialog && context.mounted) {
        _showErrorDialog(
          context,
          l10n.getLocationFailedTitle,
          l10n.getLocationFailedDesc(e.toString()),
        );
      }
      return LocationWeatherResult();
    }

    if (position == null) {
      if (showLocationErrorDialog && context.mounted) {
        _showErrorDialog(
          context,
          locationErrorTitle ?? l10n.cannotGetLocationTitle,
          locationErrorContent ?? l10n.cannotGetLocationDesc,
        );
      }
      return LocationWeatherResult();
    }

    final address = locationService.getFormattedLocation();
    String? weather;
    String? temperature;

    // 3. Get Weather Data (Optional)
    if (includeWeather) {
      final weatherResult = await fetchWeather(
        context: context,
        latitude: position.latitude,
        longitude: position.longitude,
        showWeatherErrorDialog: showWeatherErrorDialog,
      );
      weather = weatherResult.weather;
      temperature = weatherResult.temperature;
    }

    return LocationWeatherResult(
      latitude: position.latitude,
      longitude: position.longitude,
      address: address.isNotEmpty ? address : null,
      weather: weather,
      temperature: temperature,
    );
  }

  /// Fetches weather data for given coordinates.
  static Future<({String? weather, String? temperature})> fetchWeather({
    required BuildContext context,
    required double latitude,
    required double longitude,
    bool showWeatherErrorDialog = true,
  }) async {
    final weatherService = Provider.of<WeatherService>(context, listen: false);
    final l10n = AppLocalizations.of(context);

    try {
      await weatherService.getWeatherData(latitude, longitude);
      final weather = weatherService.currentWeather;
      final temperature = weatherService.temperature;

      if (weather == null && showWeatherErrorDialog && context.mounted) {
        _showErrorDialog(
          context,
          l10n.weatherFetchFailedTitle,
          l10n.weatherFetchFailedDesc,
        );
      }
      return (weather: weather, temperature: temperature);
    } catch (e) {
      logError('LocationWeatherHelper: Failed to get weather data', error: e);
      if (showWeatherErrorDialog && context.mounted) {
        _showErrorDialog(
          context,
          l10n.weatherFetchFailedTitle,
          l10n.weatherFetchFailedDesc,
        );
      }
      return (weather: null, temperature: null);
    }
  }

  /// Helper to show a simple error dialog with an "I Know" button.
  static void _showErrorDialog(
    BuildContext context,
    String title,
    String content,
  ) {
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context).iKnow),
          ),
        ],
      ),
    );
  }
}
