import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_key_manager.dart';
import '../services/settings_service.dart';

/// API密钥诊断工具
class ApiKeyDiagnosticsPage extends StatefulWidget {
  const ApiKeyDiagnosticsPage({super.key});

  @override
  State<ApiKeyDiagnosticsPage> createState() => _ApiKeyDiagnosticsPageState();
}

class _ApiKeyDiagnosticsPageState extends State<ApiKeyDiagnosticsPage> {
  String _diagnosticResult = '';
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('API密钥诊断'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'API密钥诊断工具',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              '此工具将检查API密钥的存储和获取情况，帮助诊断401认证错误。',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _runDiagnostics,
              child:
                  _isLoading
                      ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Text('运行诊断'),
            ),
            const SizedBox(height: 24),
            if (_diagnosticResult.isNotEmpty) ...[
              const Text(
                '诊断结果:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      _diagnosticResult,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _runDiagnostics() async {
    setState(() {
      _isLoading = true;
      _diagnosticResult = '';
    });

    final buffer = StringBuffer();
    buffer.writeln('=== API密钥诊断报告 ===');
    buffer.writeln('时间: ${DateTime.now()}');
    buffer.writeln();

    try {
      // 获取设置服务
      final settingsService = Provider.of<SettingsService>(
        context,
        listen: false,
      );

      // 使用多供应商API密钥管理器
      final apiKeyManager = APIKeyManager();
      final multiSettings = settingsService.multiAISettings;
      final currentProvider = multiSettings.currentProvider;

      // 1. 多供应商配置检查
      buffer.writeln('1. 多供应商配置...');
      buffer.writeln('   - 当前供应商: ${currentProvider?.name ?? "未选择"}');
      buffer.writeln('   - 可用供应商数量: ${multiSettings.providers.length}');
      buffer.writeln('   - 已启用供应商: ${multiSettings.providers.where((p) => p.isEnabled).length}');
      buffer.writeln();

      if (currentProvider != null) {
        // 2. 当前供应商详情
        buffer.writeln('2. 当前供应商详情...');
        buffer.writeln('   - ID: ${currentProvider.id}');
        buffer.writeln('   - 名称: ${currentProvider.name}');
        buffer.writeln('   - API URL: ${currentProvider.apiUrl}');
        buffer.writeln('   - 模型: ${currentProvider.model}');
        buffer.writeln('   - 已启用: ${currentProvider.isEnabled ? "是" : "否"}');
        buffer.writeln();

        // 3. API密钥检查
        buffer.writeln('3. API密钥检查...');
        final hasApiKeyInSettings = currentProvider.apiKey.trim().isNotEmpty;
        buffer.writeln('   - 设置中有密钥: ${hasApiKeyInSettings ? "是" : "否"}');

        if (hasApiKeyInSettings) {
          buffer.writeln('   - 设置中密钥长度: ${currentProvider.apiKey.length}');
          buffer.writeln('   - 设置中密钥前缀: ${currentProvider.apiKey.length > 15 ? currentProvider.apiKey.substring(0, 15) + "..." : currentProvider.apiKey}');
        }

        // 检查安全存储中的密钥
        final secureApiKey = await apiKeyManager.getProviderApiKey(currentProvider.id);
        final hasSecureApiKey = secureApiKey.isNotEmpty;
        buffer.writeln('   - 安全存储中有密钥: ${hasSecureApiKey ? "是" : "否"}');

        if (hasSecureApiKey) {
          buffer.writeln('   - 安全存储密钥长度: ${secureApiKey.length}');
          buffer.writeln('   - 安全存储密钥前缀: ${secureApiKey.length > 15 ? secureApiKey.substring(0, 15) + "..." : secureApiKey}');
        }
        buffer.writeln();

        // 4. 密钥验证
        buffer.writeln('4. 密钥验证...');
        final isValidSync = apiKeyManager.hasValidProviderApiKeySync(currentProvider);
        final isValidAsync = await apiKeyManager.hasValidProviderApiKey(currentProvider.id);
        buffer.writeln('   - 同步验证: ${isValidSync ? "通过" : "失败"}');
        buffer.writeln('   - 异步验证: ${isValidAsync ? "通过" : "失败"}');

        if (hasSecureApiKey) {
          final isFormatValid = apiKeyManager.isValidApiKeyFormat(secureApiKey);
          buffer.writeln('   - 格式验证: ${isFormatValid ? "通过" : "失败"}');
        }
        buffer.writeln();
      } else {
        buffer.writeln('2. 错误: 未选择当前供应商');
        buffer.writeln();
      }

      // 5. 所有供应商状态
      buffer.writeln('5. 所有供应商状态...');
      for (final provider in multiSettings.providers) {
        final hasKey = await apiKeyManager.hasValidProviderApiKey(provider.id);
        buffer.writeln('   - ${provider.name}: ${hasKey ? "✓" : "✗"} ${provider.isEnabled ? "(已启用)" : "(已禁用)"}');
      }
      buffer.writeln();

      // 6. 建议
      buffer.writeln('6. 建议...');
      if (currentProvider == null) {
        buffer.writeln('   - 请选择一个AI服务商');
      } else if (!currentProvider.isEnabled) {
        buffer.writeln('   - 请启用当前选择的AI服务商');
      } else {
        final hasValidKey = await apiKeyManager.hasValidProviderApiKey(currentProvider.id);
        if (!hasValidKey) {
          buffer.writeln('   - 请为 ${currentProvider.name} 配置有效的API密钥');
        } else {
          buffer.writeln('   - ✓ API密钥配置正常');
        }
      }

      buffer.writeln();
      buffer.writeln('=== 诊断完成 ===');
    } catch (e) {
      buffer.writeln('诊断过程中发生错误: $e');
    }

    setState(() {
      _isLoading = false;
      _diagnosticResult = buffer.toString();
    });
  }
}
