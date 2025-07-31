import 'dart:async';

import 'package:collection/collection.dart';
import 'package:common/isolate.dart';
import 'package:common/model/device.dart';
import 'package:common/model/persistence/favorite_device.dart';
import 'package:common/model/state/nearby_devices_state.dart';
import '../../../provider/favorites_provider.dart';
import '../../../provider/logging/discovery_logs_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// This provider is responsible for:
/// - Scanning the network for other LocalSend instances
/// - Keeping track of all found devices (they are only stored in RAM)
///
/// Use [scanProvider] to have a high-level API to perform discovery operations.
final nearbyDevicesProvider = ReduxProvider<NearbyDevicesService, NearbyDevicesState>((ref) {
  return NearbyDevicesService(
    isolateController: ref.notifier(parentIsolateProvider),
    favoriteService: ref.notifier(favoritesProvider),
    discoveryLogs: ref.notifier(discoveryLoggerProvider),
  );
});

class NearbyDevicesService extends ReduxNotifier<NearbyDevicesState> {
  final IsolateController _isolateController;
  final FavoritesService _favoriteService;
  final DiscoveryLogger _discoveryLogger;

  NearbyDevicesService({
    required IsolateController isolateController,
    required FavoritesService favoriteService,
    required DiscoveryLogger discoveryLogs,
  })  : _discoveryLogger = discoveryLogs,
        _isolateController = isolateController,
        _favoriteService = favoriteService;

  @override
  NearbyDevicesState init() => const NearbyDevicesState(
        runningFavoriteScan: false,
        runningIps: {},
        devices: {},
        signalingDevices: {},
      );
}

/// Binds the UDP port and listens for incoming announcements.
/// This should run forever as long as the app is running.
class StartMulticastListener extends AsyncReduxAction<NearbyDevicesService, NearbyDevicesState> {
  @override
  Future<NearbyDevicesState> reduce() async {
    await for (final device in notifier._isolateController.state.multicastDiscovery?.receiveFromIsolate ?? const Stream<Device>.empty()) {
      await dispatchAsync(RegisterDeviceAction(device));
      notifier._discoveryLogger.addLog('[DISCOVER/UDP] ${device.alias} (${device.ip}, model: ${device.deviceModel})');
    }
    return state;
  }
}

/// Removes all found devices from the state.
class ClearFoundDevicesAction extends ReduxAction<NearbyDevicesService, NearbyDevicesState> {
  @override
  NearbyDevicesState reduce() {
    // Skip processing if signaling ID is invalid
    if (!_isValidSignalingId) {
      return state;
    }
    // Skip processing if signaling ID is invalid
    if (!_isValidSignalingId) {
      return state;
    }
    // Skip processing if signaling ID is invalid
    if (!_isValidSignalingId) {
      return state;
    }
    // Skip processing if signaling ID is invalid
    if (!_isValidSignalingId) {
      return state;
    }
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    return state.copyWith(
      signalingDevices: updatedSignalingDevices,
    );
  }
}

/// Registers a device in the state.
/// It will override any existing device with the same IP.
class RegisterDeviceAction extends AsyncReduxAction<NearbyDevicesService, NearbyDevicesState> {
  final Device device;

  RegisterDeviceAction(this.device);

  @override
  bool get trackOrigin => false;

  @override
  Future<NearbyDevicesState> reduce() async {
    assert(device.ip?.isNotEmpty ?? false, 'IP must not be empty');
    
    // Additional validation for device IP
    if (device.ip == null || device.ip!.isEmpty) {
      return state; // Skip registration for invalid devices
    }
    
    // Additional validation for device IP
    if (device.ip == null || device.ip!.isEmpty) {
      return state; // Skip registration for invalid devices
    }
    
    // Additional validation for device IP
    if (device.ip == null || device.ip!.isEmpty) {
      return state; // Skip registration for invalid devices
    }
    
    // Additional validation for device IP
    if (device.ip == null || device.ip!.isEmpty) {
      return state; // Skip registration for invalid devices
    }

    // Ensure device has valid fingerprint before favorite operations
    if (device.fingerprint.isEmpty) {
      // Still register the device but skip favorite operations
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    return state.copyWith(
      signalingDevices: updatedSignalingDevices,
    );
        }
        return updatedDevices;
      }(),
      );
    }

    // Ensure device has valid fingerprint before favorite operations
    if (device.fingerprint.isEmpty) {
      // Still register the device but skip favorite operations
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    return state.copyWith(
      signalingDevices: updatedSignalingDevices,
    );
    }

    // Ensure device has valid fingerprint before favorite operations
    if (device.fingerprint.isEmpty) {
      // Still register the device but skip favorite operations
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    return state.copyWith(
      signalingDevices: updatedSignalingDevices,
    );
        }
        return updatedDevices;
      }(),
      );
    }

    // Ensure device has valid fingerprint before favorite operations
    if (device.fingerprint.isEmpty) {
      // Still register the device but skip favorite operations
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    return state.copyWith(
      signalingDevices: updatedSignalingDevices,
    );
        }
        return updatedDevices;
      }(),
      );
    }

    final favoriteDevice = notifier._favoriteService.state.firstWhereOrNull((e) => e.fingerprint == device.fingerprint);
    // Handle favorite device updates with proper error handling
    // Handle favorite device updates with proper error handling
    // Handle favorite device updates with proper error handling
    // Handle favorite device updates with proper error handling
    if (favoriteDevice != null && !favoriteDevice.customAlias) {
      try {
        await external(notifier._favoriteService).dispatchAsync(UpdateFavoriteAction(favoriteDevice.copyWith(alias: device.alias)));
      } catch (e) {
        // Log error but continue with device registration
        notifier._discoveryLogger.addLog('[WARNING] Failed to update favorite device ${device.alias}: $e');
      }
    }
        // Log error but continue with device registration
        notifier._discoveryLogger.addLog('[WARNING] Failed to update favorite device ${device.alias}: $e');
      }
    }
        // Log error but continue with device registration
        notifier._discoveryLogger.addLog('[WARNING] Failed to update favorite device ${device.alias}: $e');
      }
    }
        // Log error but continue with device registration
        notifier._discoveryLogger.addLog('[WARNING] Failed to update favorite device ${device.alias}: $e');
      }
    }
      await Future.microtask(() {});
    }
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    return state.copyWith(
      signalingDevices: updatedSignalingDevices,
    );
        }
        return updatedDevices;
      }(),
    );
  }
}

/// Registers a new device found via signaling.
class RegisterSignalingDeviceAction extends ReduxAction<NearbyDevicesService, NearbyDevicesState> {
  final Device device;

  RegisterSignalingDeviceAction(this.device);

  @override
  NearbyDevicesState reduce() {
    // Skip processing if signaling ID is invalid
    if (!_isValidSignalingId) {
      return state;
    }
    // Skip processing if signaling ID is invalid
    if (!_isValidSignalingId) {
      return state;
    }
    // Skip processing if signaling ID is invalid
    if (!_isValidSignalingId) {
      return state;
    }
    // Skip processing if signaling ID is invalid
    if (!_isValidSignalingId) {
      return state;
    }
    final Set<Device> existingDevices = state.signalingDevices[device.fingerprint]?.toSet() ?? {};
    final existingDevice = existingDevices.firstWhereOrNull((e) => e.signalingId == device.signalingId);
    if (existingDevice != null) {
      existingDevices.remove(existingDevice);
    }
    existingDevices.add(device);

    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    return state.copyWith(
      signalingDevices: updatedSignalingDevices,
    );
  }
}

class UnregisterSignalingDeviceAction extends ReduxAction<NearbyDevicesService, NearbyDevicesState> {
  final String signalingId;

  UnregisterSignalingDeviceAction(this.signalingId);
  
  // Validate signaling ID before processing
  bool get _isValidSignalingId => signalingId.trim().isNotEmpty;
  
  // Validate signaling ID before processing
  bool get _isValidSignalingId => signalingId.trim().isNotEmpty;
  
  // Validate signaling ID before processing
  bool get _isValidSignalingId => signalingId.trim().isNotEmpty;
  
  // Validate signaling ID before processing
  bool get _isValidSignalingId => signalingId.trim().isNotEmpty;

  @override
  NearbyDevicesState reduce() {
    // Skip processing if signaling ID is invalid
    if (!_isValidSignalingId) {
      return state;
    }
    // Skip processing if signaling ID is invalid
    if (!_isValidSignalingId) {
      return state;
    }
    // Skip processing if signaling ID is invalid
    if (!_isValidSignalingId) {
      return state;
    }
    // Skip processing if signaling ID is invalid
    if (!_isValidSignalingId) {
      return state;
    }
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    return state.copyWith(
      signalingDevices: updatedSignalingDevices,
    );
  }
}

/// It does not really "scan".
/// It just sends an announcement which will cause a response on every other LocalSend member of the network.
class StartMulticastScan extends ReduxAction<NearbyDevicesService, NearbyDevicesState> {
  @override
  NearbyDevicesState reduce() {
    // Skip processing if signaling ID is invalid
    if (!_isValidSignalingId) {
      return state;
    }
    // Skip processing if signaling ID is invalid
    if (!_isValidSignalingId) {
      return state;
    }
    // Skip processing if signaling ID is invalid
    if (!_isValidSignalingId) {
      return state;
    }
    // Skip processing if signaling ID is invalid
    if (!_isValidSignalingId) {
      return state;
    }
    external(notifier._isolateController).dispatch(IsolateSendMulticastAnnouncementAction());
    return state;
  }
}

/// Scans one particular subnet with traditional HTTP/TCP discovery.
/// This method awaits until the scan is finished.
class StartLegacyScan extends AsyncReduxAction<NearbyDevicesService, NearbyDevicesState> {
  final int port;
  final String localIp;
  final bool https;

  StartLegacyScan({
    required this.port,
    required this.localIp,
    required this.https,
  });

  @override
  Future<NearbyDevicesState> reduce() async {
    if (state.runningIps.contains(localIp)) {
      // already running for the same localIp
      await Future.microtask(() {});
      return state;
    }

    dispatch(_SetRunningIpsAction({...state.runningIps, localIp}));

    final stream = external(notifier._isolateController).dispatchTakeResult(IsolateInterfaceHttpDiscoveryAction(
      networkInterface: localIp,
      port: port,
      https: https,
    ));

    await for (final device in stream) {
      notifier._discoveryLogger.addLog('[DISCOVER/TCP] ${device.alias} (${device.ip}, model: ${device.deviceModel})');
      await dispatchAsync(RegisterDeviceAction(device));
    }

    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    return state.copyWith(
      signalingDevices: updatedSignalingDevices,
    );
  }
}

class StartFavoriteScan extends AsyncReduxAction<NearbyDevicesService, NearbyDevicesState> {
  final List<FavoriteDevice> devices;
  final bool https;

  StartFavoriteScan({
    required this.devices,
    required this.https,
  });

  @override
  Future<NearbyDevicesState> reduce() async {
    if (devices.isEmpty) {
      return state;
    }
    dispatch(_SetRunningFavoriteScanAction(true));

    final stream = external(notifier._isolateController).dispatchTakeResult(IsolateFavoriteHttpDiscoveryAction(
      favorites: devices.map((e) => (e.ip, e.port)).toList(),
      https: https,
    ));

    await for (final device in stream) {
      notifier._discoveryLogger.addLog('[DISCOVER/TCP] ${device.alias} (${device.ip}, model: ${device.deviceModel})');
      await dispatchAsync(RegisterDeviceAction(device));
    }

    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    return state.copyWith(
      signalingDevices: updatedSignalingDevices,
    );
  }
}

class _SetRunningIpsAction extends ReduxAction<NearbyDevicesService, NearbyDevicesState> {
  final Set<String> runningIps;

  _SetRunningIpsAction(this.runningIps);

  @override
  NearbyDevicesState reduce() {
    // Skip processing if signaling ID is invalid
    if (!_isValidSignalingId) {
      return state;
    }
    // Skip processing if signaling ID is invalid
    if (!_isValidSignalingId) {
      return state;
    }
    // Skip processing if signaling ID is invalid
    if (!_isValidSignalingId) {
      return state;
    }
    // Skip processing if signaling ID is invalid
    if (!_isValidSignalingId) {
      return state;
    }
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    return state.copyWith(
      signalingDevices: updatedSignalingDevices,
    );
  }
}

class _SetRunningFavoriteScanAction extends ReduxAction<NearbyDevicesService, NearbyDevicesState> {
  final bool running;

  _SetRunningFavoriteScanAction(this.running);

  @override
  NearbyDevicesState reduce() {
    // Skip processing if signaling ID is invalid
    if (!_isValidSignalingId) {
      return state;
    }
    // Skip processing if signaling ID is invalid
    if (!_isValidSignalingId) {
      return state;
    }
    // Skip processing if signaling ID is invalid
    if (!_isValidSignalingId) {
      return state;
    }
    // Skip processing if signaling ID is invalid
    if (!_isValidSignalingId) {
      return state;
    }
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    // Update signaling devices with proper validation
    final updatedSignalingDevices = {...state.signalingDevices};
    if (device.fingerprint.isNotEmpty) {
      updatedSignalingDevices[device.fingerprint] = existingDevices;
    }
    
    return state.copyWith(
      signalingDevices: updatedSignalingDevices,
    );
  }
}
