import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/add_note_controller.dart';
import '../gen_l10n/app_localizations.dart';
import '../models/quote_model.dart';
import '../services/location_service.dart';

/// 快捷记事弹窗中的位置 Chip 局部状态组件。
///
/// 直接监听 [AddNoteController] 及 [isUpdatingLocation] 的变更，
/// 仅在位置状态变化时局部重绘，避免触发父级 Dialog 整体 Rebuild。
class LocationChipWidget extends StatelessWidget {
  final AddNoteController controller;
  final Quote? initialQuote;
  final ValueListenable<bool>? isUpdatingLocation;
  final LocationService? locationService;
  final LocationService? Function()? getLocationService;
  final Future<void> Function()? onShowLocationDialog;
  final Future<void> Function()? onShowNewNoteLocationDialog;
  final Future<void> Function()? onOpenNearbyPicker;
  final VoidCallback? onEnsureMetadataServices;
  final VoidCallback? onCancelAutoAttachPlan;

  const LocationChipWidget({
    super.key,
    required this.controller,
    this.initialQuote,
    this.isUpdatingLocation,
    this.locationService,
    this.getLocationService,
    this.onShowLocationDialog,
    this.onShowNewNoteLocationDialog,
    this.onOpenNearbyPicker,
    this.onEnsureMetadataServices,
    this.onCancelAutoAttachPlan,
  });

  /// 获取位置提示文本（支持 POI、行政区及经纬度显示）
  static String buildLocationTooltipText({
    required BuildContext context,
    required AddNoteController controller,
    required Quote? initialQuote,
  }) {
    final l10n = AppLocalizations.of(context);

    // 编辑模式：显示原始位置
    if (initialQuote != null) {
      if (controller.originalPoiName != null &&
          controller.originalPoiName!.isNotEmpty) {
        return LocationService.formatPoiForDisplay(
          controller.originalPoiName,
          controller.originalLocation,
        );
      }
      if (controller.originalLocation != null &&
          controller.originalLocation!.isNotEmpty) {
        return LocationService.formatLocationForDisplay(
          controller.originalLocation,
        );
      }
      if (controller.originalLatitude != null &&
          controller.originalLongitude != null) {
        return LocationService.formatCoordinates(
          controller.originalLatitude,
          controller.originalLongitude,
        );
      }
      return l10n.noLocationInfo;
    }

    // 新建模式：优先 POI > 行政区 > 坐标
    if (controller.newPoiName != null && controller.newPoiName!.isNotEmpty) {
      return LocationService.formatPoiForDisplay(
        controller.newPoiName,
        controller.newLocation,
      );
    }
    if (controller.newLocation != null &&
        controller.newLocation!.isNotEmpty) {
      return LocationService.formatLocationForDisplay(controller.newLocation);
    }
    if (controller.newLatitude != null && controller.newLongitude != null) {
      return LocationService.formatCoordinates(
        controller.newLatitude,
        controller.newLongitude,
      );
    }
    // 未获取位置时显示"当前位置"提示
    return l10n.currentLocationLabel;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    final listenable = isUpdatingLocation != null
        ? Listenable.merge([controller, isUpdatingLocation!])
        : controller;

    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final locService = getLocationService?.call() ??
            locationService ??
            _readServiceOrNull<LocationService>(context);

        final isUpdating = isUpdatingLocation?.value ?? false;
        final isFetching = isUpdating || controller.isFetchingLocation;

        final tooltipText = buildLocationTooltipText(
          context: context,
          controller: controller,
          initialQuote: initialQuote,
        );

        final message = initialQuote != null
            ? (locService != null
                ? '${l10n.addLocationPrefix}: $tooltipText'
                : l10n.locationServiceUnavailable)
            : (locService != null
                ? '${l10n.addLocationPrefix}: $tooltipText (${l10n.longPressForNearbyPicker})'
                : l10n.longPressForNearbyPicker);

        return Tooltip(
          message: message,
          child: Stack(
            children: [
              GestureDetector(
                onLongPress: isUpdating
                    ? null
                    : () async {
                        // 编辑模式下长按表现与单击一致（只读/删除，不能选新地点）
                        if (initialQuote != null) {
                          await onShowLocationDialog?.call();
                          return;
                        }
                        // 新建模式下长按：打开附近地点选择器
                        await onOpenNearbyPicker?.call();
                      },
                child: FilterChip(
                  key: const ValueKey('add_note_location_chip'),
                  showCheckmark: false,
                  avatar: isFetching
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(
                          Icons.location_on,
                          color: controller.includeLocation
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                          size: 18,
                        ),
                  label: Text(l10n.location),
                  selected: controller.includeLocation,
                  onSelected: isUpdating
                      ? null
                      : (value) async {
                          if (!value) {
                            onCancelAutoAttachPlan?.call();
                          }
                          // 编辑模式下统一弹对话框
                          if (initialQuote != null) {
                            await onShowLocationDialog?.call();
                            return;
                          }
                          // 新建模式：已有坐标/地址时弹对话框（查看/转换/移除）
                          if (controller.includeLocation &&
                              (controller.newLatitude != null ||
                                  controller.newLocation != null)) {
                            await onShowNewNoteLocationDialog?.call();
                            return;
                          }
                          // 新建模式：首次勾选，获取位置
                          if (value) {
                            if (controller.newLocation == null &&
                                controller.newLatitude == null) {
                              onEnsureMetadataServices?.call();
                              controller.fetchLocationForNewNote();
                            }
                            controller.includeLocation = true;
                            return;
                          }
                          // 取消勾选：走 removeNewLocation 一并放掉在途标志。
                          controller.removeNewLocation();
                        },
                  selectedColor: theme.colorScheme.primaryContainer,
                ),
              ),
              // 小红点：有坐标但没地址时提示可更新
              if (initialQuote == null &&
                  controller.includeLocation &&
                  controller.newLocation == null &&
                  controller.newLatitude != null &&
                  controller.newLongitude != null)
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
              if (initialQuote != null &&
                  controller.originalLocation == null &&
                  controller.originalLatitude != null &&
                  controller.originalLongitude != null)
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
    );
  }

  static T? _readServiceOrNull<T>(BuildContext context) {
    try {
      return Provider.of<T?>(context, listen: false);
    } catch (_) {
      return null;
    }
  }
}
