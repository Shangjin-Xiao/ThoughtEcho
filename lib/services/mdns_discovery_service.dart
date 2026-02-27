import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:thoughtecho/services/localsend/constants.dart';
import 'package:thoughtecho/services/localsend/models/device.dart';
import 'package:thoughtecho/utils/app_logger.dart';

/// mDNS/Bonjour 备用设备发现服务
///
/// 当 UDP 组播发现失败时（尤其在 iOS 上），使用 mDNS 作为备选。
/// mDNS 不需要 multicast entitlement（它使用系统级别的 DNS-SD）。
///
/// 服务类型：_thoughtecho._tcp
class MDNSDiscoveryService extends ChangeNotifier {
  static const String _serviceType = '_thoughtecho._tcp';
  static const String _localSendServiceType = '_localsend._tcp';

  final List<Device> _devices = [];
  bool _isScanning = false;
  MDnsClient? _client;
  Timer? _scanTimer;

  List<Device> get devices => List.unmodifiable(_devices);
  bool get isScanning => _isScanning;

  /// 开始 mDNS 发现
  Future<void> startDiscovery({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (_isScanning) return;
    if (kIsWeb) {
      debugPrint('MDNSDiscoveryService: Web 平台不支持');
      return;
    }

    _isScanning = true;
    _devices.clear();
    notifyListeners();

    logInfo('mdns_discovery_start', source: 'mDNS');

    try {
      _client = MDnsClient();
      await _client!.start();

      // 同时扫描 ThoughtEcho 和 LocalSend 服务
      _scanForService(_serviceType);
      _scanForService(_localSendServiceType);

      // 设置超时
      _scanTimer = Timer(timeout, () {
        stopDiscovery();
      });
    } catch (e) {
      logError('mdns_discovery_start_fail error=$e', source: 'mDNS');
      _isScanning = false;
      notifyListeners();
    }
  }

  /// 扫描特定服务类型
  void _scanForService(String serviceType) async {
    if (_client == null) return;

    try {
      debugPrint('mDNS: 开始扫描 $serviceType');

      await for (final PtrResourceRecord ptr
          in _client!.lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(serviceType),
          )) {
        debugPrint('mDNS: 发现服务 ${ptr.domainName}');

        // 获取 SRV 记录以获取端口
        await for (final SrvResourceRecord srv
            in _client!.lookup<SrvResourceRecord>(
              ResourceRecordQuery.service(ptr.domainName),
            )) {
          debugPrint('mDNS: 服务详情 ${srv.target}:${srv.port}');

          // 获取 IP 地址
          await for (final IPAddressResourceRecord ip
              in _client!.lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv4(srv.target),
              )) {
            final device = _createDevice(
              ip: ip.address.address,
              port: srv.port,
              name: ptr.domainName.split('.').first,
              serviceType: serviceType,
            );

            _addDevice(device);
          }
        }
      }
    } catch (e) {
      debugPrint('mDNS: 扫描 $serviceType 失败 - $e');
    }
  }

  /// 创建设备对象
  Device _createDevice({
    required String ip,
    required int port,
    required String name,
    required String serviceType,
  }) {
    return Device(
      signalingId: null,
      ip: ip,
      version: protocolVersion,
      port: port,
      https: false,
      fingerprint: '$ip:$port', // 临时指纹
      alias: name.isNotEmpty ? name : 'mDNS Device ($ip)',
      deviceModel: serviceType == _localSendServiceType
          ? 'LocalSend'
          : 'ThoughtEcho',
      deviceType: DeviceType.desktop,
      download: true,
      discoveryMethods: {MulticastDiscovery()},
    );
  }

  /// 添加设备（去重）
  void _addDevice(Device device) {
    final exists = _devices.any(
      (d) => d.ip == device.ip && d.port == device.port,
    );

    if (!exists) {
      _devices.add(device);
      notifyListeners();
      logInfo(
        'mdns_device_found ip=${device.ip} port=${device.port} alias=${device.alias}',
        source: 'mDNS',
      );
      debugPrint('mDNS: 添加设备 ${device.alias} (${device.ip}:${device.port})');
    }
  }

  /// 停止发现
  Future<void> stopDiscovery() async {
    _scanTimer?.cancel();
    _client?.stop();
    _client = null;
    _isScanning = false;
    notifyListeners();
    logInfo('mdns_discovery_stop devices=${_devices.length}', source: 'mDNS');
  }

  /// 清空设备列表
  void clearDevices() {
    _devices.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    stopDiscovery();
    super.dispose();
  }
}

/// mDNS 服务注册（让其他设备发现我们）
class MDNSServiceRegistration {
  static final MDNSServiceRegistration _instance =
      MDNSServiceRegistration._internal();
  factory MDNSServiceRegistration() => _instance;
  MDNSServiceRegistration._internal();

  static MDNSServiceRegistration get I => _instance;

  bool _isRegistered = false;
  ServerSocket? _dummyServer;

  bool get isRegistered => _isRegistered;

  /// 注册 mDNS 服务
  ///
  /// 注意：Dart 的 multicast_dns 包主要用于发现，不支持服务注册。
  /// 在 iOS/macOS 上，真正的服务注册需要使用原生代码（如 NWListener）。
  ///
  /// 这里提供一个占位实现，实际的 mDNS 服务注册应该通过 MethodChannel 调用原生代码。
  Future<bool> registerService({
    required String name,
    required int port,
    Map<String, String>? txtRecord,
  }) async {
    if (kIsWeb) return false;

    // 目前 Dart 的 multicast_dns 包不支持服务注册
    // 在 iOS 上，UDP 组播发送需要 multicast entitlement
    // 而 mDNS 服务注册使用系统 API，不需要该 entitlement
    //
    // TODO: 实现原生 mDNS 服务注册
    // - iOS: 使用 Network.framework 的 NWListener
    // - Android: 使用 NsdManager.registerService
    // - macOS: 使用 DNSServiceRegister

    logWarning(
      'mdns_register_not_implemented - native code required',
      source: 'mDNS',
    );

    // 暂时标记为已注册，依赖 UDP 组播
    _isRegistered = true;
    return true;
  }

  /// 注销 mDNS 服务
  Future<void> unregisterService() async {
    _dummyServer?.close();
    _dummyServer = null;
    _isRegistered = false;
    logInfo('mdns_unregister', source: 'mDNS');
  }
}
