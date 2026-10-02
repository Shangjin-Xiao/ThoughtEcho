import 'package:flutter/material.dart';

import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/services/local_geocoding_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/weather_service.dart';

/// 用户在位置元数据对话框中的操作类型
enum NoteLocationDialogAction {
  /// 移除笔记的位置信息
  remove,

  /// 清除地点名称（保留行政区与坐标）
  clearPoi,

  /// 根据当前坐标反查并更新行政区地址
  updateLocation,
}

/// 用户在天气元数据对话框中的操作类型
enum NoteWeatherDialogAction {
  /// 移除笔记的天气信息
  remove,
}

/// 统一管理笔记编辑器中位置与天气元数据弹窗的纯 UI/交互决策类。
///
/// 将全屏编辑器与轻量弹窗编辑器中原本冗余重复的弹窗交互抽象为单一事实来源。
class NoteMetadataDialogs {
  const NoteMetadataDialogs._();

  /// 显示笔记的位置信息对话框。
  ///
  /// - 若无位置数据：弹出提示告知编辑模式下无法添加位置；
  /// - 若有位置数据：展示当前 POI、行政区或坐标，并提供“移除”、“清除地点名称”、“更新位置”或“取消”选项。
  static Future<NoteLocationDialogAction?> showLocationInfoDialog({
    required BuildContext context,
    required String? location,
    required double? latitude,
    required double? longitude,
    String? poiName,
    required bool isSelected,
  }) async {
    final l10n = AppLocalizations.of(context);
    final hasCoordinates = latitude != null && longitude != null;
    final hasLocationData =
        (location != null && location.isNotEmpty) || hasCoordinates;
    final hasOnlyCoordinates =
        (location == null || location.isEmpty) && hasCoordinates;
    final hasPoiName = poiName != null && poiName.trim().isNotEmpty;

    final String title;
    final String content;
    final List<Widget> actions;

    if (!hasLocationData) {
      title = l10n.cannotAddLocation;
      content = l10n.cannotAddLocationDesc;
      actions = [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.iKnow),
        ),
      ];
    } else {
      title = l10n.locationInfo;
      final locationInfoText = hasOnlyCoordinates
          ? l10n.locationUpdateHint(
              LocationService.formatCoordinates(latitude, longitude),
            )
          : l10n.locationRemoveHint(
              LocationService.formatPoiForDisplay(
                poiName,
                location,
              ).isNotEmpty
                  ? LocationService.formatPoiForDisplay(poiName, location)
                  : LocationService.formatLocationForDisplay(location),
            );

      content = hasPoiName
          ? '${l10n.poiNameLabel}: ${poiName.trim()}\n\n$locationInfoText'
          : locationInfoText;

      actions = [
        if (isSelected)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, NoteLocationDialogAction.remove),
            child: Text(l10n.remove),
          ),
        if (hasPoiName)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, NoteLocationDialogAction.clearPoi),
            child: Text('${l10n.clear} ${l10n.poiNameLabel}'),
          ),
        if (hasOnlyCoordinates)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, NoteLocationDialogAction.updateLocation),
            child: Text(l10n.updateLocation),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
      ];
    }

    return showDialog<NoteLocationDialogAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: actions,
      ),
    );
  }

  /// 显示笔记的天气信息对话框。
  ///
  /// - 若无天气数据：弹出提示告知编辑模式下无法添加天气；
  /// - 若有天气数据：展示天气状况及温度，并提供“移除”或“取消”选项。
  static Future<NoteWeatherDialogAction?> showWeatherInfoDialog({
    required BuildContext context,
    required String? weather,
    String? temperature,
    required bool isSelected,
  }) async {
    final l10n = AppLocalizations.of(context);
    final hasWeatherData = weather != null && weather.isNotEmpty;

    final String title;
    final String content;
    final List<Widget> actions;

    if (!hasWeatherData) {
      title = l10n.cannotAddWeather;
      content = l10n.cannotAddWeatherDesc;
      actions = [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.iKnow),
        ),
      ];
    } else {
      title = l10n.weatherInfo2;
      final weatherDesc = WeatherService.getLocalizedWeatherDescription(
        l10n,
        weather,
      );
      final weatherDisplay =
          '$weatherDesc${temperature != null && temperature.isNotEmpty ? " $temperature" : ""}';
      content = l10n.weatherRemoveHint(weatherDisplay);
      actions = [
        if (isSelected)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, NoteWeatherDialogAction.remove),
            child: Text(l10n.remove),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
      ];
    }

    return showDialog<NoteWeatherDialogAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: actions,
      ),
    );
  }

  /// 使用经纬度坐标异步反查行政区地址，并在界面上给出标准反馈。
  ///
  /// - 成功：返回标准入库地址字符串，并在 [context] 中弹出“位置已更新为...”提示；
  /// - 失败：返回 null，并在 [context] 中弹出失败提示。
  static Future<String?> updateAddressFromCoordinates({
    required BuildContext context,
    required double latitude,
    required double longitude,
  }) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final localeCode = l10n.localeName;
      final addressInfo = await LocalGeocodingService.getAddressFromCoordinates(
        latitude,
        longitude,
        localeCode: localeCode,
      );

      if (addressInfo != null && context.mounted) {
        final standardAddress =
            LocationService.buildStorageLocation(addressInfo);
        if (standardAddress != null) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                l10n.locationUpdatedTo(
                  LocationService.formatLocationForDisplay(standardAddress),
                ),
              ),
            ),
          );
          return standardAddress;
        }
      }
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.cannotGetAddress)),
        );
      }
      return null;
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.updateFailed(e.toString()))),
        );
      }
      return null;
    }
  }
}
