import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:thoughtecho/constants/thoughtecho_constants.dart';
import 'package:thoughtecho/models/localsend_device.dart';
import 'package:thoughtecho/models/thoughtecho_multicast_dto.dart';
import 'package:thoughtecho/models/thoughtecho_register_dto.dart';
import 'package:thoughtecho/utils/thoughtecho_network_interfaces.dart';

/// ThoughtEcho设备发现服务 - 基于UDP组播
class ThoughtEchoDiscoveryService extends ChangeNotifier {
  final List<Device> _devices = [];
  bool _isScanning = false;
  final List<RawDatagramSocket> _sockets = [];
  Timer? _announcementTimer;

  List<Device> get devices => List.unmodifiable(_devices);
  bool get isScanning => _isScanning;

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
    final interfaces = await getNetworkInterfaces(
      whitelist: null,
      blacklist: null,
    );

    for (final interface in interfaces) {
      try {
        final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, defaultPort);
        socket.joinMulticast(InternetAddress(defaultMulticastGroup), interface);
        
        socket.listen((event) {
          if (event == RawSocketEvent.read) {
            final datagram = socket.receive();
            if (datagram != null) {
              _handleMulticastMessage(datagram);
            }
          }
        });
        
        _sockets.add(socket);
        debugPrint('UDP组播监听已绑定到接口: ${interface.name}');
      } catch (e) {
        debugPrint('绑定UDP组播失败: $e');
      }
    }
  }

  /// 处理接收到的组播消息
  void _handleMulticastMessage(Datagram datagram) {
    try {
      final message = utf8.decode(datagram.data);
      final json = jsonDecode(message) as Map<String, dynamic>;
      final dto = MulticastDto.fromJson(json);
      
      // 忽略自己发送的消息
      if (dto.fingerprint == _getDeviceFingerprint()) {
        return;
      }

      final ip = datagram.address.address;
      final device = dto.toDevice(ip, defaultPort, false);
      
      // 检查是否已存在
      final existingIndex = _devices.indexWhere(
        (d) => d.ip == device.ip && d.port == device.port,
      );
      
      if (existingIndex == -1) {
        _devices.add(device);
        notifyListeners();
        debugPrint('发现新设备: ${device.alias} (${device.ip})');
        
        // 如果是公告消息，回应一个注册消息
        if (dto.announcement == true || dto.announce == true) {
          _respondToAnnouncement(device);
        }
      }
    } catch (e) {
      debugPrint('解析组播消息失败: $e');
    }
  }

  /// 发送公告消息
  Future<void> _sendAnnouncement() async {
    final dto = MulticastDto(
      alias: 'ThoughtEcho-${DateTime.now().millisecondsSinceEpoch}',
      version: protocolVersion,
      deviceModel: 'ThoughtEcho',
      deviceType: DeviceType.desktop,
      fingerprint: _getDeviceFingerprint(),
      port: defaultPort,
      protocol: ProtocolType.http,
      download: true,
      announcement: true,
      announce: true,
    );

    final message = utf8.encode(jsonEncode(dto.toJson()));
    
    for (final socket in _sockets) {
      try {
        socket.send(message, InternetAddress(defaultMulticastGroup), defaultPort);
      } catch (e) {
        debugPrint('发送组播消息失败: $e');
      }
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
        socket.send(message, InternetAddress(defaultMulticastGroup), defaultPort);
      } catch (e) {
        debugPrint('回应公告失败: $e');
      }
    }
  }

  /// 获取设备指纹
  String _getDeviceFingerprint() {
    return 'thoughtecho-${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  void dispose() {
    stopDiscovery();
    super.dispose();
  }
}