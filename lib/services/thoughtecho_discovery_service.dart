import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:thoughtecho/services/localsend/constants.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:thoughtecho/services/localsend/models/device.dart';
import 'package:thoughtecho/services/localsend/models/multicast_dto.dart';
import 'package:thoughtecho/services/localsend/utils/network_interfaces.dart';
import 'device_identity_manager.dart';
import 'package:thoughtecho/utils/app_logger.dart';

/// ThoughtEcho设备发现服务 - 基于UDP组播
class ThoughtEchoDiscoveryService extends ChangeNotifier {
  final List<Device> _devices = [];
  bool _isScanning = false;
  final List<RawDatagramSocket> _sockets = [];
  Timer? _announcementTimer;
  Timer? _healthTimer; // 周期性健康检查
  DateTime _lastMessageTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastAnnouncementSend = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _socketInactivityRestart = Duration(
    seconds: 25,
  ); // 超过该时间未收到消息则重启监听
  static const Duration _announcementInterval = Duration(seconds: 5);
  static const Duration _minAnnouncementGap = Duration(seconds: 2);
  static const Duration _healthCheckInterval = Duration(seconds: 6);
  static const Duration _deviceExpiry = Duration(seconds: 40); // 设备超时移除
  final Map<String, DateTime> _deviceLastSeen = {}; // 指纹->最近见到时间
  int _actualServerPort = defaultPort; // 实际服务器端口
  String _deviceFingerprint = 'initializing'; // 设备指纹，异步获取
  bool _fingerprintReady = false; // 指纹是否已获取
  String _deviceModel = 'ThoughtEcho'; // 真实设备型号（含平台），异步填充
  bool _deviceInfoReady = false;

  List<Device> get devices => List.unmodifiable(_devices);
  bool get isScanning => _isScanning;

  /// 构造函数：开始异步获取指纹
  ThoughtEchoDiscoveryService() {
    _ensureFingerprint();
    _ensureDeviceInfo();
    debugPrint('设备发现服务初始化，设备指纹(占位): $_deviceFingerprint');
  }

  /// 幂等获取设备指纹
  Future<void> _ensureFingerprint() async {
    if (_fingerprintReady && _deviceFingerprint != 'initializing') return;
    try {
      final fp = await DeviceIdentityManager.I.getFingerprint();
      if (!_fingerprintReady) {
        _deviceFingerprint = fp;
        _fingerprintReady = true;
        logDebug('discovery_fp_ready fp=$fp', source: 'LocalSend');
      } else {
        // 已就绪则忽略后续结果
      }
    } catch (e) {
      logWarning('discovery_fp_fetch_fail error=$e', source: 'LocalSend');
    }
  }

  /// 异步获取真实设备型号并缓存。保持轻量：只获取一次。
  Future<void> _ensureDeviceInfo() async {
    if (_deviceInfoReady) return;
    if (kIsWeb) {
      _deviceModel = 'Web';
      _deviceInfoReady = true;
      return;
    }
    try {
      final plugin = DeviceInfoPlugin();
      String model;
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        final brand = info.brand.trim();
        final m = info.model.trim();
        model = [brand, m].where((e) => e.isNotEmpty).join(' ');
      } else if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        // name 例如“张三的 iPhone”，model 如 “iPhone15,2” (代号)
        final name = info.name.trim();
        final machine = info.utsname.machine.trim();
        model = name.isNotEmpty && machine.isNotEmpty
            ? '$name ($machine)'
            : (name.isNotEmpty ? name : machine);
      } else if (Platform.isMacOS) {
        final info = await plugin.macOsInfo;
        model = info.model.trim().isEmpty ? 'macOS' : info.model.trim();
      } else if (Platform.isWindows) {
        final info = await plugin.windowsInfo;
        model = info.computerName.trim().isEmpty
            ? 'Windows'
            : info.computerName.trim();
      } else if (Platform.isLinux) {
        final info = await plugin.linuxInfo;
        model =
            info.prettyName.trim().isEmpty ? 'Linux' : info.prettyName.trim();
      } else {
        model = Platform.operatingSystem;
      }
      if (model.isEmpty) model = 'Unknown Device';
      _deviceModel = model;
      _deviceInfoReady = true;
      logDebug(
        'discovery_device_model_ready model=$_deviceModel',
        source: 'LocalSend',
      );
    } catch (e) {
      _deviceModel = 'Unknown Device';
      _deviceInfoReady = true;
      logWarning('discovery_device_model_fail error=$e', source: 'LocalSend');
    }
  }

  /// 设置实际的服务器端口
  void setServerPort(int port) {
    _actualServerPort = port;
    debugPrint('设备发现服务更新服务器端口为: $port');
    logInfo('discovery_port_set port=$port', source: 'LocalSend');
  }

  /// 开始设备发现
  Future<void> startDiscovery() async {
    if (_isScanning) return;

    // Check if we're running on web platform
    if (kIsWeb) {
      debugPrint('Device discovery not supported on web platform');
      return;
    }

    _isScanning = true;
    _devices.clear();
    notifyListeners();

    try {
      // 确保指纹已就绪，避免首次广播使用占位
      if (_deviceFingerprint == 'initializing' || !_fingerprintReady) {
        await _ensureFingerprint();
      }
      if (!_deviceInfoReady) {
        await _ensureDeviceInfo();
      }

      // 启动UDP组播监听（若失败自动重试一次）
      await _startMulticastListener();
      if (_sockets.isEmpty) {
        logWarning(
          'discovery_no_socket_first_try retrying...',
          source: 'LocalSend',
        );
        await Future.delayed(const Duration(milliseconds: 400));
        await _startMulticastListener();
      }

      // 首次公告
      await _sendAnnouncement(force: true);

      // 定期发送公告 + 自愈机制
      _announcementTimer = Timer.periodic(_announcementInterval, (_) {
        _sendAnnouncement();
      });

      // 健康检查：检测长期无消息、设备过期、套接字是否关闭
      _healthTimer?.cancel();
      _healthTimer = Timer.periodic(_healthCheckInterval, (_) async {
        if (!_isScanning) return;
        final now = DateTime.now();
        // 1. 长时间无消息 => 重启监听
        if (now.difference(_lastMessageTime) > _socketInactivityRestart) {
          logWarning('discovery_inactive_restart', source: 'LocalSend');
          await _restartSockets();
          await _sendAnnouncement(force: true);
        }
        // 2. 移除过期设备（不改变功能：只是去掉不再在线的幽灵设备）
        final removed = <String>[];
        _deviceLastSeen.forEach((fp, ts) {
          if (now.difference(ts) > _deviceExpiry) {
            removed.add(fp);
          }
        });
        if (removed.isNotEmpty) {
          _devices.removeWhere((d) => removed.contains(d.fingerprint));
          for (final r in removed) {
            _deviceLastSeen.remove(r);
          }
          if (removed.isNotEmpty) {
            notifyListeners();
            logInfo(
              'discovery_prune old=${removed.length}',
              source: 'LocalSend',
            );
          }
        }
        // 3. 套接字数量为0 => 重启
        if (_sockets.isEmpty) {
          await _restartSockets();
          await _sendAnnouncement(force: true);
        }
      });

      debugPrint('ThoughtEcho设备发现已启动');
      logInfo('discovery_started', source: 'LocalSend');
    } catch (e) {
      debugPrint('启动设备发现失败: $e');
      logError('discovery_start_fail error=$e', source: 'LocalSend');
      _isScanning = false;
      notifyListeners();
    }
  }

  /// 停止设备发现
  Future<void> stopDiscovery() async {
    _isScanning = false;
    _announcementTimer?.cancel();
    _healthTimer?.cancel();

    for (final socket in _sockets) {
      socket.close();
    }
    _sockets.clear();

    notifyListeners();
    debugPrint('ThoughtEcho设备发现已停止');
    logInfo('discovery_stopped', source: 'LocalSend');
  }

  /// 启动UDP组播监听
  Future<void> _startMulticastListener() async {
    try {
      debugPrint('开始获取网络接口...');
      debugPrint('当前平台: ${Platform.operatingSystem}');
      logInfo(
        'discovery_start_listen platform=${Platform.operatingSystem}',
        source: 'LocalSend',
      );

      final interfaces = await getNetworkInterfaces(
        whitelist: null,
        blacklist: null,
      );

      debugPrint('发现 ${interfaces.length} 个网络接口');
      logInfo(
        'discovery_interfaces count=${interfaces.length}',
        source: 'LocalSend',
      );

      if (interfaces.isEmpty) {
        debugPrint('警告: 未发现活动网络接口');
        logWarning('discovery_no_interfaces', source: 'LocalSend');
      }

      for (final interface in interfaces) {
        try {
          debugPrint('尝试在接口 ${interface.name} 上绑定UDP组播');
          final addresses = interface.addresses
              .where((a) => a.type == InternetAddressType.IPv4)
              .map((a) => a.address)
              .join(', ');
          debugPrint('接口地址: $addresses');

          // Windows 平台不使用 reusePort（可能不支持或导致问题）
          final socket = Platform.isWindows
              ? await RawDatagramSocket.bind(
                  InternetAddress.anyIPv4,
                  defaultMulticastPort,
                  reuseAddress: true,
                )
              : await RawDatagramSocket.bind(
                  InternetAddress.anyIPv4,
                  defaultMulticastPort,
                  reuseAddress: true,
                  reusePort: true,
                );

          debugPrint('UDP套接字成功绑定到端口 ${socket.port}');

          // 启用功能
          socket.readEventsEnabled = true;
          socket.broadcastEnabled = true;
          socket.multicastLoopback = true; // 允许本机收到自己发出的组播
          debugPrint('套接字功能已启用: readEvents, broadcast, multicastLoopback');

          // 加入组播组
          try {
            socket.joinMulticast(
              InternetAddress(defaultMulticastGroup),
              interface,
            );
            debugPrint(
              '✓ 成功加入组播组 $defaultMulticastGroup (接口: ${interface.name})',
            );
          } catch (e) {
            debugPrint('❌ 加入组播组失败: $e');
            socket.close();
            continue; // 跳过这个接口
          }

          // 设置监听
          socket.listen(
            (event) {
              if (event == RawSocketEvent.read) {
                final datagram = socket.receive();
                if (datagram != null) {
                  _lastMessageTime = DateTime.now();
                  _handleMulticastMessage(datagram);
                }
              } else if (event == RawSocketEvent.closed) {
                debugPrint('❌ 套接字被关闭，标记自愈');
                // 延迟触发一个自愈（不直接重启，避免多次触发）
                Future.microtask(() async {
                  if (_isScanning) {
                    await _restartSockets();
                  }
                });
              }
            },
            onError: (error) {
              debugPrint('❌ 套接字监听错误: $error');
            },
          );

          _sockets.add(socket);
          debugPrint('✓ UDP组播监听已绑定到接口: ${interface.name}');
        } catch (e, stack) {
          debugPrint('绑定UDP组播到接口 ${interface.name} 失败: $e');
          debugPrint('堆栈: $stack');
        }
      }

      if (_sockets.isEmpty) {
        debugPrint('警告: 未能绑定到任何网络接口');
        logWarning('discovery_no_sockets_bound', source: 'LocalSend');
      } else {
        debugPrint('成功绑定到 ${_sockets.length} 个网络接口');
        logInfo(
          'discovery_sockets_bound count=${_sockets.length}',
          source: 'LocalSend',
        );
      }
    } catch (e, stack) {
      debugPrint('启动UDP组播监听失败: $e');
      debugPrint('堆栈: $stack');
      logError('discovery_start_fail error=$e', source: 'LocalSend');
    }
  }

  /// 处理接收到的组播消息
  void _handleMulticastMessage(Datagram datagram) {
    try {
      final message = utf8.decode(datagram.data);
      debugPrint('=== 收到UDP组播消息 ===');
      debugPrint('来源: ${datagram.address.address}:${datagram.port}');
      debugPrint('消息长度: ${message.length} 字符');
      debugPrint('完整消息: $message');

      final json = jsonDecode(message) as Map<String, dynamic>;
      debugPrint('解析JSON成功: $json');

      final dto = MulticastDto.fromJson(json);
      debugPrint('创建MulticastDto成功');

      // 详细记录指纹信息
      final remoteFingerprint = dto.fingerprint;
      final localFingerprint = _getDeviceFingerprint();
      debugPrint('远程设备指纹: $remoteFingerprint');
      debugPrint('本机设备指纹: $localFingerprint');
      debugPrint('指纹匹配: ${remoteFingerprint == localFingerprint}');

      // 忽略自己发送的消息
      if (remoteFingerprint == localFingerprint) {
        debugPrint('✓ 忽略自己发送的消息');
        return;
      }

      final ip = datagram.address.address;
      final devicePort = dto.port ?? defaultPort;
      debugPrint('创建设备对象，IP: $ip, 端口: $devicePort');
      final device = dto.toDevice(ip, devicePort, false);
      debugPrint('设备信息: ${device.alias} (${device.ip}:${device.port})');

      // 检查是否已存在
      final existingIndex = _devices.indexWhere(
        (d) => d.ip == device.ip && d.port == device.port,
      );

      if (existingIndex == -1) {
        _devices.add(device);
        _deviceLastSeen[device.fingerprint] = DateTime.now();
        notifyListeners();
        debugPrint('✓ 发现新设备: ${device.alias} (${device.ip}:${device.port})');
        debugPrint(
          '当前设备列表: ${_devices.map((d) => '${d.alias}(${d.ip}:${d.port})').join(', ')}',
        );

        // 如果是公告消息，回应一个注册消息
        if (dto.announcement == true || dto.announce == true) {
          debugPrint('收到公告消息，准备发送回应');
          _respondToAnnouncement(device);
        }
      } else {
        // 更新 last seen
        _deviceLastSeen[device.fingerprint] = DateTime.now();
        debugPrint('设备已存在: ${device.alias} (${device.ip}:${device.port})');
      }
    } catch (e, stack) {
      debugPrint('解析组播消息失败: $e');
      debugPrint('堆栈: $stack');
      debugPrint('原始消息: ${utf8.decode(datagram.data, allowMalformed: true)}');
    }
  }

  /// 发送公告消息
  Future<void> _sendAnnouncement({bool force = false}) async {
    if (_sockets.isEmpty) {
      debugPrint('❌ 没有可用的套接字发送公告');
      return;
    }
    final now = DateTime.now();
    if (!force && now.difference(_lastAnnouncementSend) < _minAnnouncementGap) {
      // 防抖：避免外部频繁调用导致广播风暴
      return;
    }

    if (!_fingerprintReady) {
      await _ensureFingerprint();
    }
    if (!_deviceInfoReady) {
      await _ensureDeviceInfo();
    }
    final fingerprint = _getDeviceFingerprint();
    final dto = MulticastDto(
      alias: 'ThoughtEcho-${Platform.localHostname}',
      version: protocolVersion,
      deviceModel: _deviceModel,
      deviceType: DeviceType.mobile,
      fingerprint: fingerprint,
      port: _actualServerPort, // 使用实际服务器端口
      protocol: ProtocolType.http,
      download: true,
      announcement: true,
      announce: true,
    );

    final messageJson = jsonEncode(dto.toJson());
    final message = utf8.encode(messageJson);

    debugPrint('=== 发送公告消息 ===');
    logInfo(
      'discovery_broadcast_send port=$_actualServerPort sockets=${_sockets.length}',
      source: 'LocalSend',
    );
    debugPrint('设备指纹: $fingerprint');
    debugPrint('服务器端口: $_actualServerPort');
    debugPrint('组播地址: $defaultMulticastGroup:$defaultMulticastPort');
    debugPrint('消息内容: $messageJson');
    debugPrint('消息字节数: ${message.length}');
    debugPrint('可用套接字数: ${_sockets.length}');

    if (_sockets.isEmpty) {
      logWarning(
        'discovery_broadcast_no_sockets',
        source: 'LocalSend',
      );
      return;
    }

    int successCount = 0;

    for (int i = 0; i < _sockets.length; i++) {
      final socket = _sockets[i];
      try {
        final result = socket.send(
          message,
          InternetAddress(defaultMulticastGroup),
          defaultMulticastPort,
        );
        if (result > 0) {
          successCount++;
          debugPrint('✓ 套接字 $i 发送成功，字节数: $result');
          logInfo(
            'discovery_broadcast_sent sock=$i bytes=$result',
            source: 'LocalSend',
          );
        } else {
          debugPrint('❌ 套接字 $i 发送失败，返回: $result');
          logWarning(
            'discovery_broadcast_fail sock=$i result=$result',
            source: 'LocalSend',
          );
        }

        // 额外的广播兜底（部分路由器/平台屏蔽组播）
        try {
          final br = socket.send(
            message,
            InternetAddress('255.255.255.255'),
            defaultMulticastPort,
          );
          if (br > 0) {
            logDebug(
              'discovery_broadcast_fallback sock=$i bytes=$br',
              source: 'LocalSend',
            );
          }
        } catch (e) {
          debugPrint('广播兜底发送失败: $e');
        }
      } catch (e) {
        debugPrint('❌ 套接字 $i 发送异常: $e');
      }
    }

    _lastAnnouncementSend = now;

    if (successCount > 0) {
      debugPrint('✓ 成功通过 $successCount/${_sockets.length} 个套接字发送公告');
      logInfo(
        'discovery_broadcast_summary success=$successCount total=${_sockets.length}',
        source: 'LocalSend',
      );
    } else {
      debugPrint('❌ 警告: 未能通过任何套接字发送公告');
    }
  }

  /// 回应公告消息
  Future<void> _respondToAnnouncement(Device peer) async {
    // 可以通过HTTP发送注册消息，或者通过UDP回应
    if (!_deviceInfoReady) {
      await _ensureDeviceInfo();
    }
    if (!_fingerprintReady) {
      await _ensureFingerprint();
    }
    final dto = MulticastDto(
      alias: 'ThoughtEcho-${Platform.localHostname}',
      version: protocolVersion,
      deviceModel: _deviceModel,
      deviceType: DeviceType.mobile,
      fingerprint: _getDeviceFingerprint(),
      port: _actualServerPort,
      protocol: ProtocolType.http,
      download: true,
      announcement: false,
      announce: false,
    );

    final message = utf8.encode(jsonEncode(dto.toJson()));

    for (final socket in _sockets) {
      try {
        socket.send(
          message,
          InternetAddress(defaultMulticastGroup),
          defaultMulticastPort,
        );
      } catch (e) {
        debugPrint('回应公告失败: $e');
      }
    }
  }

  /// 清空设备列表
  void clearDevices() {
    _devices.clear();
    _deviceLastSeen.clear();
    notifyListeners();
    debugPrint('已清空设备列表');
  }

  /// 主动发送设备公告
  Future<void> announceDevice() async {
    if (!_isScanning) {
      debugPrint('设备发现服务未运行，无法发送公告');
      return;
    }

    try {
      if (!_fingerprintReady) {
        await _ensureFingerprint();
      }
      if (!_deviceInfoReady) {
        await _ensureDeviceInfo();
      }
      final fingerprint = _getDeviceFingerprint();
      debugPrint('创建设备公告，设备指纹: $fingerprint');

      final announcement = MulticastDto(
        alias: 'ThoughtEcho-${Platform.localHostname}',
        version: protocolVersion,
        deviceModel: _deviceModel,
        deviceType: DeviceType.mobile,
        fingerprint: fingerprint,
        port: _actualServerPort, // 使用实际服务器端口
        protocol: ProtocolType.http,
        download: true,
        announcement: true,
        announce: true,
      );

      final message = jsonEncode(announcement.toJson());
      final messageBytes = utf8.encode(message);
      final multicastAddress = InternetAddress(defaultMulticastGroup);

      debugPrint('设备公告内容长度: ${message.length} 字符');

      // 检查套接字是否为空
      if (_sockets.isEmpty) {
        debugPrint('警告: 无可用UDP套接字发送公告，尝试重新初始化...');
        await _startMulticastListener();

        if (_sockets.isEmpty) {
          debugPrint('错误: 无法创建UDP套接字，公告发送失败');
          return;
        }
      }

      int sentCount = 0;
      // 向所有套接字发送公告
      for (final socket in _sockets) {
        try {
          final result = socket.send(
            messageBytes,
            multicastAddress,
            defaultMulticastPort,
          );
          if (result > 0) {
            sentCount++;
            debugPrint(
              '发送设备公告到 ${multicastAddress.address}:$defaultMulticastPort, 发送字节: $result',
            );
          }

          // 额外的广播兜底
          try {
            final br = socket.send(
              messageBytes,
              InternetAddress('255.255.255.255'),
              defaultMulticastPort,
            );
            if (br > 0) {
              logDebug(
                'discovery_broadcast_fallback bytes=$br',
                source: 'LocalSend',
              );
            }
          } catch (e) {
            debugPrint('广播兜底失败: $e');
          }
        } catch (e) {
          debugPrint('发送公告失败: $e');
        }
      }

      if (sentCount > 0) {
        debugPrint('成功通过 $sentCount 个套接字发送设备公告');
      } else {
        debugPrint('警告: 未能通过任何套接字发送设备公告');
      }
    } catch (e, stack) {
      debugPrint('创建设备公告失败: $e');
      debugPrint('堆栈: $stack');
    }
  }

  /// 获取设备指纹
  String _getDeviceFingerprint() {
    return _deviceFingerprint;
  }

  @override
  void dispose() {
    stopDiscovery();
    super.dispose();
  }

  // 重启套接字监听（保持外部功能一致，仅内部自愈）
  Future<void> _restartSockets() async {
    for (final s in _sockets) {
      try {
        s.close();
      } catch (_) {}
    }
    _sockets.clear();
    await _startMulticastListener();
  }
}
