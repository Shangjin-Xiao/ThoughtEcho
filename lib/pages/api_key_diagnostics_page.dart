import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/secure_storage_service.dart';
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
              child: _isLoading 
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

    try {      // 1. 检查设置服务
      buffer.writeln('1. 检查设置服务...');
      final settingsService = Provider.of<SettingsService>(context, listen: false);
      final aiSettings = settingsService.aiSettings;
      
      buffer.writeln('   - API URL: ${aiSettings.apiUrl.isNotEmpty ? "已配置" : "未配置"}');
      buffer.writeln('   - 模型: ${aiSettings.model.isNotEmpty ? "已配置 (${aiSettings.model})" : "未配置"}');
      buffer.writeln('   - 设置中的API密钥: ${aiSettings.apiKey.isNotEmpty ? "存在 (长度: ${aiSettings.apiKey.length})" : "不存在"}');
      
      if (aiSettings.apiKey.isNotEmpty) {
        buffer.writeln('   - 密钥前缀: ${aiSettings.apiKey.substring(0, aiSettings.apiKey.length > 15 ? 15 : aiSettings.apiKey.length)}...');
        buffer.writeln('   - 包含换行符: ${aiSettings.apiKey.contains('\n') || aiSettings.apiKey.contains('\r')}');
        buffer.writeln('   - 包含前后空格: ${aiSettings.apiKey.startsWith(' ') || aiSettings.apiKey.endsWith(' ')}');
      }
      buffer.writeln();

      // 2. 检查安全存储
      buffer.writeln('2. 检查安全存储...');
      final secureStorage = SecureStorageService();
      await secureStorage.ensureInitialized();
      
      final secureApiKey = await secureStorage.getApiKey();
      buffer.writeln('   - 安全存储中的API密钥: ${secureApiKey != null ? "存在 (长度: ${secureApiKey.length})" : "不存在"}');
      
      if (secureApiKey != null) {
        buffer.writeln('   - 密钥前缀: ${secureApiKey.substring(0, secureApiKey.length > 15 ? 15 : secureApiKey.length)}...');
        buffer.writeln('   - 包含换行符: ${secureApiKey.contains('\n') || secureApiKey.contains('\r')}');
        buffer.writeln('   - 包含前后空格: ${secureApiKey.startsWith(' ') || secureApiKey.endsWith(' ')}');
      }
      buffer.writeln();

      // 3. 比较两个密钥
      buffer.writeln('3. 密钥一致性检查...');
      if (aiSettings.apiKey.isNotEmpty && secureApiKey != null) {
        final isEqual = aiSettings.apiKey == secureApiKey;
        buffer.writeln('   - 设置密钥与安全存储密钥一致: $isEqual');
        if (!isEqual) {
          buffer.writeln('   - 设置密钥长度: ${aiSettings.apiKey.length}');
          buffer.writeln('   - 安全存储密钥长度: ${secureApiKey.length}');
        }
      } else if (aiSettings.apiKey.isNotEmpty) {
        buffer.writeln('   - 仅设置中有密钥，安全存储为空');
      } else if (secureApiKey != null) {
        buffer.writeln('   - 仅安全存储中有密钥，设置为空');
      } else {
        buffer.writeln('   - 两处都没有密钥');
      }
      buffer.writeln();

      // 4. 确定最终使用的密钥
      buffer.writeln('4. 最终使用的密钥...');
      final effectiveKey = secureApiKey ?? aiSettings.apiKey;
      buffer.writeln('   - 有效密钥: ${effectiveKey.isNotEmpty ? "存在 (长度: ${effectiveKey.length})" : "不存在"}');
      
      if (effectiveKey.isNotEmpty) {
        buffer.writeln('   - 来源: ${secureApiKey != null ? "安全存储" : "设置"}');
        buffer.writeln('   - 密钥前缀: ${effectiveKey.substring(0, effectiveKey.length > 15 ? 15 : effectiveKey.length)}...');
        
        // 5. 密钥格式验证
        buffer.writeln();
        buffer.writeln('5. 密钥格式验证...');
        
        // 检查常见的API密钥格式
        if (effectiveKey.startsWith('sk-')) {
          buffer.writeln('   - OpenAI格式: ✓');
        } else if (effectiveKey.startsWith('sk_') || effectiveKey.startsWith('or_')) {
          buffer.writeln('   - OpenRouter格式: ✓');
        } else if (effectiveKey.startsWith('Bearer ')) {
          buffer.writeln('   - 警告: 密钥包含"Bearer "前缀，这可能导致重复Authorization头');
        } else {
          buffer.writeln('   - 其他格式 (可能正常)');
        }
        
        // 检查长度
        if (effectiveKey.length < 20) {
          buffer.writeln('   - 警告: 密钥长度过短 (${effectiveKey.length})，可能无效');
        } else if (effectiveKey.length > 200) {
          buffer.writeln('   - 警告: 密钥长度过长 (${effectiveKey.length})，可能包含多余内容');
        } else {
          buffer.writeln('   - 密钥长度正常: ${effectiveKey.length}');
        }
        
        // 检查特殊字符
        final hasSpecialChars = effectiveKey.contains('\n') || 
                               effectiveKey.contains('\r') || 
                               effectiveKey.contains('\t');
        buffer.writeln('   - 包含特殊字符: ${hasSpecialChars ? "是 (可能导致问题)" : "否"}');
        
        // 检查空格
        final hasSpaces = effectiveKey.startsWith(' ') || effectiveKey.endsWith(' ');
        buffer.writeln('   - 前后空格: ${hasSpaces ? "是 (可能导致问题)" : "否"}');
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
