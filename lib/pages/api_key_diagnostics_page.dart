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
      final aiSettings = settingsService.aiSettings;

      // 使用新的API密钥管理器获取诊断信息
      final apiKeyManager = APIKeyManager();
      final diagnosticInfo = await apiKeyManager.getDiagnosticInfo(aiSettings);

      // 1. 基本配置检查
      buffer.writeln('1. 基本配置...');
      buffer.writeln(
        '   - API URL: ${aiSettings.apiUrl.isNotEmpty ? "已配置 (${aiSettings.apiUrl})" : "未配置"}',
      );
      buffer.writeln(
        '   - 模型: ${aiSettings.model.isNotEmpty ? "已配置 (${aiSettings.model})" : "未配置"}',
      );
      buffer.writeln();

      // 2. 设置中的密钥信息
      buffer.writeln('2. 设置中的API密钥...');
      final settings = diagnosticInfo['settings'];
      buffer.writeln('   - 存在: ${settings['hasKey'] ? "是" : "否"}');
      if (settings['hasKey']) {
        buffer.writeln('   - 长度: ${settings['keyLength']}');
        buffer.writeln('   - 前缀: ${settings['keyPrefix']}');
        buffer.writeln('   - 包含换行符: ${settings['hasNewlines'] ? "是" : "否"}');
        buffer.writeln('   - 包含前后空格: ${settings['hasSpaces'] ? "是" : "否"}');
      }
      buffer.writeln();

      // 3. 安全存储中的密钥信息
      buffer.writeln('3. 安全存储中的API密钥...');
      final secureStorage = diagnosticInfo['secureStorage'];
      buffer.writeln('   - 存在: ${secureStorage['hasKey'] ? "是" : "否"}');
      if (secureStorage['hasKey']) {
        buffer.writeln('   - 长度: ${secureStorage['keyLength']}');
        buffer.writeln('   - 前缀: ${secureStorage['keyPrefix']}');
        buffer.writeln(
          '   - 包含换行符: ${secureStorage['hasNewlines'] ? "是" : "否"}',
        );
        buffer.writeln(
          '   - 包含前后空格: ${secureStorage['hasSpaces'] ? "是" : "否"}',
        );
      }
      buffer.writeln();

      // 4. 最终有效密钥
      buffer.writeln('4. 最终有效密钥...');
      final effective = diagnosticInfo['effective'];
      buffer.writeln('   - 存在: ${effective['hasKey'] ? "是" : "否"}');
      if (effective['hasKey']) {
        buffer.writeln('   - 长度: ${effective['keyLength']}');
        buffer.writeln(
          '   - 来源: ${effective['source'] == 'secureStorage' ? "安全存储" : "设置"}',
        );
        buffer.writeln('   - 格式: ${effective['format']}');
        buffer.writeln('   - 格式有效: ${effective['isValid'] ? "是" : "否"}');

        // 根据格式提供建议
        final format = effective['format'] as String;
        if (format.contains('Bearer')) {
          buffer.writeln('   - ⚠️ 警告: 密钥包含"Bearer "前缀，这可能导致重复Authorization头');
        } else if (format == 'Custom/Unknown' && effective['keyLength'] < 20) {
          buffer.writeln('   - ⚠️ 警告: 密钥长度过短，可能无效');
        } else if (format == 'Custom/Unknown' && effective['keyLength'] > 200) {
          buffer.writeln('   - ⚠️ 警告: 密钥长度过长，可能包含多余内容');
        } else if (format.startsWith('OpenAI') ||
            format.startsWith('OpenRouter')) {
          buffer.writeln('   - ✓ 密钥格式正常');
        }
      } else {
        buffer.writeln('   - ❌ 没有可用的API密钥');
      }
      buffer.writeln();

      // 5. 缓存状态
      buffer.writeln('5. 缓存状态...');
      final cache = diagnosticInfo['cache'];
      buffer.writeln('   - 有缓存密钥: ${cache['hasCachedKey'] ? "是" : "否"}');
      buffer.writeln('   - 缓存有效: ${cache['isValid'] ? "是" : "否"}');
      if (cache['cacheTime'] != null) {
        buffer.writeln('   - 缓存时间: ${cache['cacheTime']}');
      }
      buffer.writeln();

      // 6. 一致性检查
      buffer.writeln('6. 密钥一致性检查...');
      if (settings['hasKey'] && secureStorage['hasKey']) {
        final settingsLength = settings['keyLength'] as int;
        final secureLength = secureStorage['keyLength'] as int;
        if (settingsLength == secureLength) {
          buffer.writeln('   - ✓ 设置与安全存储中的密钥长度一致');
        } else {
          buffer.writeln('   - ⚠️ 设置与安全存储中的密钥长度不一致');
          buffer.writeln('     - 设置中长度: $settingsLength');
          buffer.writeln('     - 安全存储长度: $secureLength');
        }
      } else if (settings['hasKey'] && !secureStorage['hasKey']) {
        buffer.writeln('   - ℹ️ 仅设置中有密钥，安全存储为空（将自动迁移）');
      } else if (!settings['hasKey'] && secureStorage['hasKey']) {
        buffer.writeln('   - ✓ 仅安全存储中有密钥，设置为空（推荐状态）');
      } else {
        buffer.writeln('   - ❌ 两处都没有密钥');
      }
      buffer.writeln();

      // 7. 建议
      buffer.writeln('7. 建议...');
      if (!effective['hasKey']) {
        buffer.writeln('   - 请在设置中配置有效的API密钥');
      } else if (effective['source'] == 'settings') {
        buffer.writeln('   - 密钥将自动迁移到安全存储以提高安全性');
      } else if (!effective['isValid']) {
        buffer.writeln('   - 请检查API密钥格式是否正确');
      } else {
        buffer.writeln('   - ✓ API密钥配置正常');
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
