import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/quote_model.dart';
import '../utils/app_logger.dart';
import '../utils/platform_helper.dart';

/// 专用于向 Pico 发送数据的低功耗蓝牙 (BLE) 服务
class PicoBleService {
  static final PicoBleService instance = PicoBleService._init();
  PicoBleService._init();

  // 约定好 Pico 端将广播的设备名称
  static const String targetDeviceName = 'Pico_ThoughtEcho';

  // 约定好的 BLE Service 和 Characteristic UUID
  static const String picoServiceUuid = '0000ffe0-0000-1000-8000-00805f9b34fb';
  static const String picoCharacteristicUuid =
      '0000ffe1-0000-1000-8000-00805f9b34fb';

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _targetCharacteristic;
  bool _isConnecting = false;

  /// 本次进程内蓝牙不可用（没有硬件 / 用户拒绝授权）时置位，
  /// 之后所有推送直接跳过 BLE，不再反复唤起系统蓝牙栈。
  bool _bleUnavailable = false;

  /// 发送笔记到 Pico（自动处理连接与数据打包发送）
  Future<bool> sendQuoteToPico(Quote quote) async {
    // BLE 发送只在移动端启用（Web / 桌面端既没有硬件适配也没有权限声明）
    if (!PlatformHelper.isAndroid && !PlatformHelper.isIOS) {
      AppLogger.w('当前平台默认不开启或不支持 BLE 发送功能');
      return false;
    }

    if (_bleUnavailable) {
      AppLogger.d('蓝牙本次运行已判定不可用，跳过向 Pico 发送');
      return false;
    }

    try {
      final isSupported = await FlutterBluePlus.isSupported;
      if (!isSupported) {
        AppLogger.w('设备不支持蓝牙 BLE');
        _bleUnavailable = true;
        return false;
      }

      // 为了不打扰主 UI 流程，静默失败。
      // 加超时兜底：iOS 上系统蓝牙权限弹窗未处理前状态会一直停在 unknown，
      // 不设超时会把这个 future 永久挂起。
      final state = await FlutterBluePlus.adapterState.first
          .timeout(const Duration(seconds: 5), onTimeout: () {
        AppLogger.w('读取蓝牙适配器状态超时');
        return BluetoothAdapterState.unknown;
      });
      if (state == BluetoothAdapterState.unauthorized ||
          state == BluetoothAdapterState.unavailable) {
        AppLogger.w('蓝牙不可用或未授权（$state），本次运行不再尝试向 Pico 发送');
        _bleUnavailable = true;
        return false;
      }
      if (state != BluetoothAdapterState.on) {
        AppLogger.w('蓝牙未开启，取消向 Pico 发送');
        return false;
      }

      bool connected = await _ensureConnected();
      if (!connected) {
        AppLogger.e('找不到或无法连接到名为 $targetDeviceName 的 Pico 蓝牙设备');
        return false;
      }

      if (_targetCharacteristic == null) {
        AppLogger.e('未找到目标蓝牙特征值，可能 Pico 固件有误');
        return false;
      }

      // 构建要发送给 Pico 的精简型 JSON 数据
      // 水墨屏通常不需要太长且繁重的数据格式，只取展示核心
      final payload = {
        'type': 'note',
        'content': quote.content,
        // 如果没有作者信息，传默认值
        'author': quote.sourceAuthor ?? 'ThoughtEcho',
        'weather': quote.weather,
        'loc': quote.location,
        'date': quote.date.split('T').first,
      };

      // 剔除空值减轻传输负担
      payload.removeWhere(
          (key, value) => value == null || value.toString().isEmpty);

      final jsonStr = jsonEncode(payload);
      final bytes = utf8.encode(jsonStr); // 必须是 UTF-8 编码避免水墨屏中文乱码

      AppLogger.i('准备通过 BLE 将笔记发送到 Pico: $jsonStr (总字节数: ${bytes.length})');

      // Android 下请求提升 MTU，允许一次发长数据 (最大512)
      // 这可以避免底层蓝牙分包导致的复杂组包逻辑
      if (PlatformHelper.isAndroid) {
        try {
          await _connectedDevice!.requestMtu(512);
        } catch (e) {
          AppLogger.w('MTU 提升请求失败，可能会走系统的自动分包: $e');
        }
      }

      // 写入数据包
      await _targetCharacteristic!.write(bytes, withoutResponse: true);
      AppLogger.i('✅ BLE 传向水墨屏：发送成功!');
      return true;
    } catch (e) {
      AppLogger.e('BLE 发送笔记到 Pico 失败', error: e);
      return false;
    }
  }

  /// 丢弃当前连接状态（设备与 characteristic 必须成对失效）
  void _clearConnection() {
    _connectedDevice = null;
    _targetCharacteristic = null;
  }

  /// 内部方法：自动扫描、发现设备、建立连接并寻找服务特征
  Future<bool> _ensureConnected() async {
    // 检查是否已经保持连接
    if (_connectedDevice != null && _targetCharacteristic != null) {
      if (_connectedDevice!.isConnected) {
        return true;
      }
      // 连接已断开：characteristic 绑在这台外设上，一并丢掉，
      // 否则后面重连失败时会残留一个指向死连接的引用。
      _clearConnection();
    }

    if (_isConnecting) return false;
    _isConnecting = true;

    try {
      AppLogger.i('开始扫描寻找 Pico ($targetDeviceName)...');

      // 执行带名字过滤的扫描，超时 4 秒
      await FlutterBluePlus.startScan(
        withNames: [targetDeviceName],
        timeout: const Duration(seconds: 4),
      );

      // 等待并找寻结果中匹配的设备。
      // scanResults 是不会关闭的广播流，扫不到设备时 firstWhere 永远不会完成，
      // 必须加超时，否则 _isConnecting 会被永久占住，之后再也发不出去。
      final results = await FlutterBluePlus.scanResults
          .firstWhere(
            (results) =>
                results.isNotEmpty &&
                results.any((r) => r.device.platformName == targetDeviceName),
            orElse: () => <ScanResult>[],
          )
          .timeout(
            const Duration(seconds: 6),
            onTimeout: () => <ScanResult>[],
          );

      if (results.isEmpty) {
        AppLogger.w('蓝牙扫描结束，未找到 Pico');
        return false;
      }

      final targetResult =
          results.firstWhere((r) => r.device.platformName == targetDeviceName);
      _connectedDevice = targetResult.device;

      AppLogger.i('找到 Pico! 准备建立 BLE 连接...');
      await _connectedDevice!.connect(timeout: const Duration(seconds: 5));
      AppLogger.i('连接建立！开始发现约定的服务...');

      final services = await _connectedDevice!.discoverServices();
      for (var service in services) {
        if (service.uuid.toString() == picoServiceUuid) {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid.toString() == picoCharacteristicUuid) {
              _targetCharacteristic = characteristic;
              AppLogger.i('成功打通与 Pico 水墨屏的 BLE 通信通道！');
              return true;
            }
          }
        }
      }

      AppLogger.e('已连接设备，但内部未找到约定的服务 UUID (可能没刷对应的主板固件)');
      await _connectedDevice!.disconnect();
      _clearConnection();
      return false;
    } catch (e) {
      AppLogger.e('Pico 蓝牙连接意外中断 或 扫描失败', error: e);
      return false;
    } finally {
      _isConnecting = false;
      // 无论成功与否，请务必停止扫描以省电
      unawaited(FlutterBluePlus.stopScan().catchError((_) {}));
    }
  }

  /// 供前台“手动发送”按钮调用的 API（如果不想它因为后台逻辑失败被忽略的话）
  Future<bool> triggerManualPush(Quote quote) async {
    return await sendQuoteToPico(quote);
  }
}
