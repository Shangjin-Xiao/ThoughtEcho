import 'package:flutter/material.dart';
import 'package:thoughtecho/utils/multicast_diagnostic_tool.dart';
import 'package:thoughtecho/services/thoughtecho_discovery_service.dart';
import 'package:thoughtecho/services/localsend/constants.dart';
import 'package:thoughtecho/services/localsend/models/device.dart';
import '../gen_l10n/app_localizations.dart';

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
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.diagnosticFailed(e.toString())),
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
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.startDiscoveryFailed(e.toString())),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  Future<void> _announceDevice() async {
    final l10n = AppLocalizations.of(context);
    try {
      await _discoveryService.announceDevice();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.deviceAnnouncementSent),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.sendAnnouncementFailed(e.toString())),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.networkDiagnostic),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 配置信息
            _buildConfigSection(l10n),
            const SizedBox(height: 20),

            // 诊断工具
            _buildDiagnosticSection(l10n),
            const SizedBox(height: 20),

            // 设备发现
            _buildDiscoverySection(l10n),
            const SizedBox(height: 20),

            // 发现的设备
            _buildDevicesSection(l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigSection(AppLocalizations l10n) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.networkConfig,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text('HTTP Server Port: $defaultPort'),
            const Text('Multicast Discovery Port: $defaultMulticastPort'),
            const Text('Multicast Address: $defaultMulticastGroup'),
            const Text('Protocol Version: $protocolVersion'),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticSection(AppLocalizations l10n) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.networkDiagnosticSection,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _isRunningDiagnostic ? null : _runDiagnostic,
              child: _isRunningDiagnostic
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(l10n.diagnosing),
                      ],
                    )
                  : Text(l10n.runNetworkDiagnostic),
            ),
            if (_diagnosticResult != null) ...[
              const SizedBox(height: 10),
              _buildDiagnosticResults(l10n),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticResults(AppLocalizations l10n) {
    final result = _diagnosticResult!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.diagnosticResult(result.successCount, result.totalCount),
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

  Widget _buildDiscoverySection(AppLocalizations l10n) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.deviceDiscovery,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _toggleDiscovery,
                  child: Text(_isDiscoveryRunning ? l10n.stopDiscovery : l10n.startDiscovery),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _isDiscoveryRunning ? _announceDevice : null,
                  child: Text(l10n.sendAnnouncement),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _isDiscoveryRunning ? l10n.statusRunning : l10n.statusStopped,
              style: TextStyle(
                color: _isDiscoveryRunning ? Colors.green : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDevicesSection(AppLocalizations l10n) {
    final devices = _discoveryService.devices;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.discoveredDevicesCount(devices.length),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            if (devices.isEmpty)
              Text(l10n.noDevicesFound)
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
                        '${device.deviceModel ?? l10n.unknownModel}\n'
                        '${l10n.fingerprint(device.fingerprint)}',
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
