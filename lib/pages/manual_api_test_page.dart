import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'dart:convert';

/// 手动API密钥测试工具
class ManualApiKeyTestPage extends StatefulWidget {
  const ManualApiKeyTestPage({super.key});

  @override
  State<ManualApiKeyTestPage> createState() => _ManualApiKeyTestPageState();
}

class _ManualApiKeyTestPageState extends State<ManualApiKeyTestPage> {
  final _apiKeyController = TextEditingController();
  final _apiUrlController = TextEditingController();
  final _modelController = TextEditingController();
  String _testResult = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // 设置默认值
    _apiUrlController.text = 'https://api.siliconflow.cn/v1/chat/completions';
    _modelController.text = 'gpt-3.5-turbo';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('手动API测试'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '手动API密钥测试',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              '直接输入API参数进行测试，绕过存储系统检查API密钥是否有效。',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _apiUrlController,
              decoration: const InputDecoration(
                labelText: 'API URL',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'API Key',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _modelController,
              decoration: const InputDecoration(
                labelText: 'Model',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _testApiKey,
              child:
                  _isLoading
                      ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Text('测试API密钥'),
            ),
            const SizedBox(height: 24),
            if (_testResult.isNotEmpty) ...[
              const Text(
                '测试结果:',
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
                      _testResult,
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

  Future<void> _testApiKey() async {
    if (_apiKeyController.text.trim().isEmpty ||
        _apiUrlController.text.trim().isEmpty ||
        _modelController.text.trim().isEmpty) {
      setState(() {
        _testResult = '错误: 请填写所有必填字段';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _testResult = '';
    });

    final buffer = StringBuffer();
    buffer.writeln('=== 手动API密钥测试报告 ===');
    buffer.writeln('时间: ${DateTime.now()}');
    buffer.writeln();

    try {
      final apiKey = _apiKeyController.text.trim();
      final apiUrl = _apiUrlController.text.trim();
      final model = _modelController.text.trim();

      buffer.writeln('测试参数:');
      buffer.writeln('  API URL: $apiUrl');
      buffer.writeln('  Model: $model');
      buffer.writeln('  API Key长度: ${apiKey.length}');
      buffer.writeln(
        '  API Key前缀: ${apiKey.substring(0, apiKey.length > 10 ? 10 : apiKey.length)}...',
      );
      buffer.writeln();

      // 检查密钥格式
      buffer.writeln('密钥格式检查:');
      if (apiKey.contains('\n') || apiKey.contains('\r')) {
        buffer.writeln('  ❌ 包含换行符');
      } else {
        buffer.writeln('  ✅ 无换行符');
      }

      if (apiKey.startsWith(' ') || apiKey.endsWith(' ')) {
        buffer.writeln('  ❌ 包含前后空格');
      } else {
        buffer.writeln('  ✅ 无前后空格');
      }

      if (apiKey.startsWith('Bearer ')) {
        buffer.writeln('  ⚠️  包含"Bearer "前缀（可能导致问题）');
      } else {
        buffer.writeln('  ✅ 无"Bearer "前缀');
      }
      buffer.writeln();

      // 创建Dio实例
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 30);
      dio.options.receiveTimeout = const Duration(seconds: 30);

      // 构建请求
      final headers = <String, String>{'Content-Type': 'application/json'};

      final requestBody = <String, dynamic>{
        'model': model,
        'messages': [
          {'role': 'user', 'content': '请简单回复"测试成功"'},
        ],
        'max_tokens': 10,
        'temperature': 0.1,
      };

      // 根据不同的服务商设置认证头
      if (apiUrl.contains('anthropic.com')) {
        headers['x-api-key'] = apiKey;
        headers['anthropic-version'] = '2023-06-01';
        requestBody.remove('model'); // Anthropic在请求体中不需要model
        requestBody['max_tokens'] = 10;
      } else {
        headers['Authorization'] = 'Bearer $apiKey';
      }

      if (apiUrl.contains('openrouter.ai')) {
        headers['HTTP-Referer'] = 'https://thoughtecho.app';
        headers['X-Title'] = 'ThoughtEcho App';
      }

      buffer.writeln('发送请求:');
      buffer.writeln('  Headers: ${headers.keys.join(', ')}');
      buffer.writeln('  Request Body: ${json.encode(requestBody)}');
      buffer.writeln();

      // 发送请求
      final response = await dio.post(
        apiUrl,
        data: requestBody,
        options: Options(headers: headers),
      );

      buffer.writeln('响应结果:');
      buffer.writeln('  状态码: ${response.statusCode}');
      buffer.writeln('  响应头: ${response.headers}');

      if (response.statusCode == 200) {
        buffer.writeln('  ✅ 请求成功!');
        buffer.writeln('  响应内容: ${json.encode(response.data)}');

        // 尝试解析响应
        try {
          final responseData = response.data;
          if (responseData is Map<String, dynamic>) {
            if (responseData.containsKey('choices')) {
              buffer.writeln('  ✅ 响应格式正确，包含choices字段');
            }
            if (responseData.containsKey('error')) {
              buffer.writeln('  ❌ 响应包含错误: ${responseData['error']}');
            }
          }
        } catch (e) {
          buffer.writeln('  ⚠️  响应解析失败: $e');
        }
      } else {
        buffer.writeln('  ❌ 请求失败，状态码: ${response.statusCode}');
        buffer.writeln('  错误响应: ${response.data}');
      }
    } catch (e) {
      buffer.writeln('测试失败:');
      buffer.writeln('  错误类型: ${e.runtimeType}');
      buffer.writeln('  错误信息: $e');

      if (e is DioException) {
        buffer.writeln('  Dio错误类型: ${e.type}');
        buffer.writeln('  响应状态码: ${e.response?.statusCode}');
        buffer.writeln('  响应数据: ${e.response?.data}');
        buffer.writeln('  错误消息: ${e.message}');
      }
    }

    buffer.writeln();
    buffer.writeln('=== 测试完成 ===');

    setState(() {
      _isLoading = false;
      _testResult = buffer.toString();
    });
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _apiUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }
}
