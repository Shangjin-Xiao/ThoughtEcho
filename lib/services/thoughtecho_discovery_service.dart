import 'dart:async';
import 'dart:math';
import '../models/localsend_device.dart';

/// ThoughtEcho设备发现服务
/// 基于LocalSend的发现机制，但简化用于笔记同步
class ThoughtEchoDiscoveryService {
  bool _isRunning = false;
  final List<Device> _discoveredDevices = [];
  
  /// 开始设备发现
  Future<void> startDiscovery() async {
    if (_isRunning) return;
    
    _isRunning = true;
    // 在实际实现中，这里会启动UDP多播发现
    // 现在作为示例，我们创建一些模拟设备
    await _simulateDeviceDiscovery();
  }
  
  /// 停止设备发现
  Future<void> stopDiscovery() async {
    _isRunning = false;
    _discoveredDevices.clear();
  }
  
  /// 获取发现的设备列表
  List<Device> get discoveredDevices => List.unmodifiable(_discoveredDevices);
  
  /// 模拟设备发现（用于开发测试）
  Future<void> _simulateDeviceDiscovery() async {
    await Future.delayed(const Duration(seconds: 1));
    
    // 模拟发现一些设备
    final random = Random();
    final deviceTypes = DeviceType.values;
    
    for (int i = 0; i < random.nextInt(3) + 1; i++) {
      final device = Device(
        signalingId: null,
        ip: '192.168.1.${100 + i}',
        version: '2.1',
        port: 53317,
        https: false,
        fingerprint: 'mock-fingerprint-$i',
        alias: '测试设备 ${i + 1}',
        deviceModel: 'MockDevice',
        deviceType: deviceTypes[random.nextInt(deviceTypes.length)],
        download: false,
        discoveryMethods: const {MulticastDiscovery()},
      );
      
      _discoveredDevices.add(device);
    }
  }
  
  /// 手动搜索设备
  Future<List<Device>> scanForDevices() async {
    if (!_isRunning) {
      await startDiscovery();
    }
    
    // 清除之前的发现结果
    _discoveredDevices.clear();
    
    // 重新搜索
    await _simulateDeviceDiscovery();
    
    return discoveredDevices;
  }
  
  bool get isRunning => _isRunning;
}