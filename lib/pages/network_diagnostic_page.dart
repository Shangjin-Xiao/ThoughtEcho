import 'package:flutter/material.dart';
import 'package:thoughtecho/utils/multicast_diagnostic_tool.dart';
import 'package:thoughtecho/services/thoughtecho_discovery_service.dart';
import 'package:thoughtecho/services/localsend/constants.dart';
import 'package:thoughtecho/services/localsend/models/device.dart';

/// 网络诊断页面
/// 用于测试和诊断设备发现功能
class NetworkDiagnosticPage extends StatefulWidget {
  const NetworkDiagnosticPage({super.key});

  @override
  State<NetworkDiagnosticPage> createState() => _NetworkDiagnosticPageState();
}

class _NetworkDiagnosticPageState extends State<NetworkDiagnosticPage> {
  MulticastDiagnosticResult? _diagnosticResult;
  bool _isRunningDiagnostic = false;
  final ThoughtEchoDiscoveryService _discoveryService =
      ThoughtEchoDiscoveryService();
  bool _isDiscoveryRunning = false;

  @override
  void initState() {
    super.initState();
    _discoveryService.addListener(_onDevicesChanged);
  }

  @override
  void dispose() {
    _discoveryService.removeListener(_onDevicesChanged);
    _discoveryService.dispose();
    super.dispose();
  }

  void _onDevicesChanged() {
    setState(() {});
  }

  Future<void> _runDiagnostic() async {
    setState(() {
      _isRunningDiagnostic = true;
      _diagnosticResult = null;
    });

    try {
      final result = await MulticastDiagnosticTool.runFullDiagnostic();
      setState(() {
        _diagnosticResult = result;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('诊断失败: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      setState(() {
        _isRunningDiagnostic = false;
      });
    }
  }

  Future<void> _toggleDiscovery() async {
    if (_isDiscoveryRunning) {
      await _discoveryService.stopDiscovery();
      setState(() {
        _isDiscoveryRunning = false;
      });
    } else {
      try {
        await _discoveryService.startDiscovery();
        setState(() {
          _isDiscoveryRunning = true;
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('启动设备发现失败: $e'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  Future<void> _announceDevice() async {
    try {
      await _discoveryService.announceDevice();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('设备公告已发送'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('发送设备公告失败: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('网络诊断'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 配置信息
            _buildConfigSection(),
            const SizedBox(height: 20),

            // 诊断工具
            _buildDiagnosticSection(),
            const SizedBox(height: 20),

            // 设备发现
            _buildDiscoverySection(),
            const SizedBox(height: 20),

            // 发现的设备
            _buildDevicesSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigSection() {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '网络配置',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text('HTTP服务器端口: $defaultPort'),
            Text('组播发现端口: $defaultMulticastPort'),
            Text('组播地址: $defaultMulticastGroup'),
            Text('协议版本: $protocolVersion'),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '网络诊断',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _isRunningDiagnostic ? null : _runDiagnostic,
              child: _isRunningDiagnostic
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text('诊断中...'),
                      ],
                    )
                  : const Text('运行网络诊断'),
            ),
            if (_diagnosticResult != null) ...[
              const SizedBox(height: 10),
              _buildDiagnosticResults(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticResults() {
    final result = _diagnosticResult!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '诊断结果: ${result.successCount}/${result.totalCount} 项通过',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: result.isSuccess ? Colors.green : Colors.red,
          ),
        ),
        const SizedBox(height: 8),
        ...result.steps.map((step) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    step.success ? Icons.check_circle : Icons.error,
                    color: step.success ? Colors.green : Colors.red,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${step.name}: ${step.message}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  Widget _buildDiscoverySection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '设备发现',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _toggleDiscovery,
                  child: Text(_isDiscoveryRunning ? '停止发现' : '开始发现'),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _isDiscoveryRunning ? _announceDevice : null,
                  child: const Text('发送公告'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '状态: ${_isDiscoveryRunning ? "运行中" : "已停止"}',
              style: TextStyle(
                color: _isDiscoveryRunning ? Colors.green : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDevicesSection() {
    final devices = _discoveryService.devices;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '发现的设备 (${devices.length})',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            if (devices.isEmpty)
              const Text('暂无发现的设备')
            else
              ...devices.map((device) => Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: Icon(
                        device.deviceType == DeviceType.mobile
                            ? Icons.phone_android
                            : Icons.computer,
                      ),
                      title: Text(device.alias),
                      subtitle: Text(
                        '${device.ip}:${device.port}\n'
                        '${device.deviceModel ?? "未知型号"}\n'
                        '指纹: ${device.fingerprint}',
                      ),
                      isThreeLine: true,
                      trailing: Icon(
                        device.download ? Icons.download : Icons.block,
                        color: device.download ? Colors.green : Colors.red,
                      ),
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}
