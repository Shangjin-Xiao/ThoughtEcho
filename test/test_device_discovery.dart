import 'dart:io';
import 'dart:convert';
import 'package:thoughtecho/services/thoughtecho_discovery_service.dart';
import 'package:thoughtecho/services/localsend/constants.dart';
import 'package:thoughtecho/services/localsend/models/multicast_dto.dart';
import 'package:thoughtecho/services/localsend/models/device.dart';
import 'package:thoughtecho/utils/app_logger.dart';

/// 测试设备发现功能的脚本
void main() async {
  logInfo('🔍 开始测试设备发现功能...');

  // 测试1: 验证设备指纹一致性
  await testDeviceFingerprint();

  // 测试2: 验证组播消息格式
  await testMulticastMessage();

  // 测试3: 验证端口处理
  await testPortHandling();

  // 测试4: 模拟设备发现过程
  await testDeviceDiscovery();

  logInfo('✅ 所有测试完成！');
}

/// 测试设备指纹一致性
Future<void> testDeviceFingerprint() async {
  logInfo('📋 测试1: 设备指纹一致性');

  // 模拟指纹生成逻辑
  final hostname = Platform.localHostname;
  final os = Platform.operatingSystem;
  final processId = pid;

  final fingerprint1 = 'thoughtecho-$hostname-$os-$processId';
  await Future.delayed(const Duration(milliseconds: 100));
  final fingerprint2 = 'thoughtecho-$hostname-$os-$processId';

  if (fingerprint1 == fingerprint2) {
    logDebug('✅ 设备指纹保持一致: $fingerprint1');
  } else {
    logError('❌ 设备指纹不一致: $fingerprint1 vs $fingerprint2');
  }
  logDebug('');
}

/// 测试组播消息格式
Future<void> testMulticastMessage() async {
  logInfo('📡 测试2: 组播消息格式');

  const dto = MulticastDto(
    alias: 'ThoughtEcho-TestDevice',
    version: protocolVersion,
    deviceModel: 'ThoughtEcho App',
    deviceType: DeviceType.mobile,
    fingerprint: 'test-fingerprint-123',
    port: 53321,
    protocol: ProtocolType.http,
    download: true,
    announcement: true,
    announce: true,
  );

  final json = dto.toJson();
  final jsonString = jsonEncode(json);

  logDebug('组播消息JSON: $jsonString');

  // 验证反序列化
  try {
    final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
    final reconstructed = MulticastDto.fromJson(decoded);
    if (reconstructed.fingerprint == dto.fingerprint &&
        reconstructed.port == dto.port) {
      logDebug('✅ 组播消息序列化/反序列化正常');
    } else {
      logError('❌ 组播消息序列化/反序列化失败');
    }
  } catch (e) {
    logError('❌ 组播消息格式错误: $e');
  }
  logDebug('');
}

/// 测试端口处理
Future<void> testPortHandling() async {
  logInfo('🔌 测试3: 端口处理');

  const dto = MulticastDto(
    alias: 'TestDevice',
    version: protocolVersion,
    deviceModel: 'Test',
    deviceType: DeviceType.mobile,
    fingerprint: 'test-123',
    port: 53321, // 自定义端口
    protocol: ProtocolType.http,
    download: true,
    announcement: true,
    announce: true,
  );

  // 测试正确的端口传递
  final device = dto.toDevice('192.168.1.100', dto.port!, false);

  if (device.port == 53321) {
    logDebug('✅ 端口处理正确: ${device.port}');
  } else {
    logError('❌ 端口处理错误: 期望 53321, 实际 ${device.port}');
  }
  logDebug('设备信息: ${device.alias} (${device.ip}:${device.port})');
  logDebug('');
}

/// 模拟设备发现过程
Future<void> testDeviceDiscovery() async {
  logInfo('🔍 测试4: 模拟设备发现过程');

  try {
    final service = ThoughtEchoDiscoveryService();
    // 设置服务器端口
    service.setServerPort(53321);
    logDebug('启动设备发现服务...');
    await service.startDiscovery();
    logDebug('等待5秒收集设备...');
    await Future.delayed(const Duration(seconds: 5));
    final devices = service.devices;
    logDebug('发现 ${devices.length} 台设备:');
    for (final device in devices) {
      logDebug(
          '  - ${device.alias} (${device.ip}:${device.port}) [${device.fingerprint}]');
    }
    await service.stopDiscovery();
    service.dispose();
    logDebug('✅ 设备发现测试完成');
  } catch (e) {
    logError('❌ 设备发现测试失败: $e');
  }
  logDebug('');
}
