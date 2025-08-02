import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:thoughtecho/services/localsend/constants.dart';
import 'package:thoughtecho/services/localsend/models/device.dart';
import 'package:thoughtecho/services/localsend/models/multicast_dto.dart';
import 'package:thoughtecho/services/localsend/utils/network_interfaces.dart';

/// ThoughtEcho设备发现服务 - 基于UDP组播
class ThoughtEchoDiscoveryService extends ChangeNotifier {
  final List<Device> _devices = [];
  bool _isScanning = false;
  final List<RawDatagramSocket> _sockets = [];
  Timer? _announcementTimer;
  int _actualServerPort = defaultPort; // 实际服务器端口
  late final String _deviceFingerprint; // 设备指纹，在初始化时生成一次

  List<Device> get devices => List.unmodifiable(_devices);
  bool get isScanning => _isScanning;

  /// 构造函数，生成唯一的设备指纹
  ThoughtEchoDiscoveryService() {
    _deviceFingerprint = _generateDeviceFingerprint();
    debugPrint('设备发现服务初始化，设备指纹: $_deviceFingerprint');
  }

  /// 设置实际的服务器端口
  void setServerPort(int port) {
    _actualServerPort = port;
    debugPrint('设备发现服务更新服务器端口为: $port');
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
      // 启动UDP组播监听
      await _startMulticastListener();

      // 发送公告消息
      await _sendAnnouncement();

      // 定期发送公告
      _announcementTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        _sendAnnouncement();
      });

      debugPrint('ThoughtEcho设备发现已启动');
    } catch (e) {
      debugPrint('启动设备发现失败: $e');
      _isScanning = false;
      notifyListeners();
    }
  }

  /// 停止设备发现
  Future<void> stopDiscovery() async {
    _isScanning = false;
    _announcementTimer?.cancel();
    
    for (final socket in _sockets) {
      socket.close();
    }
    _sockets.clear();
    
    notifyListeners();
    debugPrint('ThoughtEcho设备发现已停止');
  }

  /// 启动UDP组播监听
  Future<void> _startMulticastListener() async {
    try {
      debugPrint('开始获取网络接口...');
      final interfaces = await getNetworkInterfaces(
        whitelist: null,
        blacklist: null,
      );
      
      debugPrint('发现 ${interfaces.length} 个网络接口');
      
      if (interfaces.isEmpty) {
        debugPrint('警告: 未发现活动网络接口');
      }

      for (final interface in interfaces) {
        try {
          debugPrint('尝试在接口 ${interface.name} 上绑定UDP组播');
          final addresses = interface.addresses
            .where((a) => a.type == InternetAddressType.IPv4)
            .map((a) => a.address)
            .join(', ');
          debugPrint('接口地址: $addresses');
          
          final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, defaultMulticastPort);
          
          debugPrint('UDP套接字成功绑定到端口 ${socket.port}');
          
          // 启用功能
          socket.readEventsEnabled = true;
          socket.broadcastEnabled = true;
          socket.multicastLoopback = true; // 允许本机收到自己发出的组播
          debugPrint('套接字功能已启用: readEvents, broadcast, multicastLoopback');
          
          // 加入组播组
          try {
            socket.joinMulticast(InternetAddress(defaultMulticastGroup), interface);
            debugPrint('✓ 成功加入组播组 $defaultMulticastGroup (接口: ${interface.name})');
          } catch (e) {
            debugPrint('❌ 加入组播组失败: $e');
            socket.close();
            continue; // 跳过这个接口
          }

          // 设置监听
          socket.listen((event) {
            if (event == RawSocketEvent.read) {
              final datagram = socket.receive();
              if (datagram != null) {
                _handleMulticastMessage(datagram);
              }
            }
          }, onError: (error) {
            debugPrint('❌ 套接字监听错误: $error');
          });

          _sockets.add(socket);
          debugPrint('✓ UDP组播监听已绑定到接口: ${interface.name}');
        } catch (e, stack) {
          debugPrint('绑定UDP组播到接口 ${interface.name} 失败: $e');
          debugPrint('堆栈: $stack');
        }
      }
      
      if (_sockets.isEmpty) {
        debugPrint('警告: 未能绑定到任何网络接口');
      } else {
        debugPrint('成功绑定到 ${_sockets.length} 个网络接口');
      }
    } catch (e, stack) {
      debugPrint('启动UDP组播监听失败: $e');
      debugPrint('堆栈: $stack');
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
      debugPrint('创建设备对象，IP: $ip, 端口: ${dto.port ?? defaultPort}');
      final device = dto.toDevice(ip, defaultPort, false);
      debugPrint('设备信息: ${device.alias} (${device.ip}:${device.port})');

      // 检查是否已存在
      final existingIndex = _devices.indexWhere(
        (d) => d.ip == device.ip && d.port == device.port,
      );

      if (existingIndex == -1) {
        _devices.add(device);
        notifyListeners();
        debugPrint('✓ 发现新设备: ${device.alias} (${device.ip}:${device.port})');
        debugPrint('当前设备列表: ${_devices.map((d) => '${d.alias}(${d.ip}:${d.port})').join(', ')}');

        // 如果是公告消息，回应一个注册消息
        if (dto.announcement == true || dto.announce == true) {
          debugPrint('收到公告消息，准备发送回应');
          _respondToAnnouncement(device);
        }
      } else {
        debugPrint('设备已存在: ${device.alias} (${device.ip}:${device.port})');
      }
    } catch (e, stack) {
      debugPrint('解析组播消息失败: $e');
      debugPrint('堆栈: $stack');
      debugPrint('原始消息: ${utf8.decode(datagram.data, allowMalformed: true)}');
    }
  }

  /// 发送公告消息
  Future<void> _sendAnnouncement() async {
    if (_sockets.isEmpty) {
      debugPrint('❌ 没有可用的套接字发送公告');
      return;
    }

    final fingerprint = _getDeviceFingerprint();
    final dto = MulticastDto(
      alias: 'ThoughtEcho-${Platform.localHostname}',
      version: protocolVersion,
      deviceModel: 'ThoughtEcho App',
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
    debugPrint('设备指纹: $fingerprint');
    debugPrint('服务器端口: $_actualServerPort');
    debugPrint('组播地址: $defaultMulticastGroup:$defaultMulticastPort');
    debugPrint('消息内容: $messageJson');
    debugPrint('消息字节数: ${message.length}');
    debugPrint('可用套接字数: ${_sockets.length}');

    int successCount = 0;

    for (int i = 0; i < _sockets.length; i++) {
      final socket = _sockets[i];
      try {
        final result = socket.send(message, InternetAddress(defaultMulticastGroup), defaultMulticastPort);
        if (result > 0) {
          successCount++;
          debugPrint('✓ 套接字 $i 发送成功，字节数: $result');
        } else {
          debugPrint('❌ 套接字 $i 发送失败，返回: $result');
        }
      } catch (e) {
        debugPrint('❌ 套接字 $i 发送异常: $e');
      }
    }

    if (successCount > 0) {
      debugPrint('✓ 成功通过 $successCount/${_sockets.length} 个套接字发送公告');
    } else {
      debugPrint('❌ 警告: 未能通过任何套接字发送公告');
    }
  }

  /// 回应公告消息
  Future<void> _respondToAnnouncement(Device peer) async {
    // 可以通过HTTP发送注册消息，或者通过UDP回应
    final dto = MulticastDto(
      alias: 'ThoughtEcho-${DateTime.now().millisecondsSinceEpoch}',
      version: protocolVersion,
      deviceModel: 'ThoughtEcho',
      deviceType: DeviceType.desktop,
      fingerprint: _getDeviceFingerprint(),
      port: defaultPort,
      protocol: ProtocolType.http,
      download: true,
      announcement: false,
      announce: false,
    );

    final message = utf8.encode(jsonEncode(dto.toJson()));
    
    for (final socket in _sockets) {
      try {
        socket.send(message, InternetAddress(defaultMulticastGroup), defaultMulticastPort);
      } catch (e) {
        debugPrint('回应公告失败: $e');
      }
    }
  }

  /// 清空设备列表
  void clearDevices() {
    _devices.clear();
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
      final fingerprint = _getDeviceFingerprint();
      debugPrint('创建设备公告，设备指纹: $fingerprint');

      final announcement = MulticastDto(
        alias: 'ThoughtEcho-${Platform.localHostname}',
        version: protocolVersion,
        deviceModel: 'ThoughtEcho App',
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
          final result = socket.send(messageBytes, multicastAddress, defaultMulticastPort);
          if (result > 0) {
            sentCount++;
            debugPrint('发送设备公告到 ${multicastAddress.address}:$defaultMulticastPort, 发送字节: $result');
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

  /// 生成设备指纹 - 在初始化时调用一次
  String _generateDeviceFingerprint() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final hostname = Platform.localHostname;
    final os = Platform.operatingSystem;
    return 'thoughtecho-$hostname-$os-$timestamp';
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
}