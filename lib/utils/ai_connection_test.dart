import '../services/settings_service.dart';
import '../utils/ai_network_manager.dart';
import 'package:thoughtecho/utils/app_logger.dart';

/// 测试多provider AI功能
class AIConnectionTest {
  static Future<void> testMultiProviderConnection(
    SettingsService settingsService,
  ) async {
    logDebug('开始测试多provider AI连接...');

    try {
      final multiSettings = settingsService.multiAISettings;
      logDebug('可用provider数量: ${multiSettings.availableProviders.length}');
      logDebug('当前provider: ${multiSettings.currentProvider?.name ?? "无"}');
      logDebug('启用故障转移: ${multiSettings.enableFailover}');

      // 测试基本请求
      final testMessages = [
        {'role': 'system', 'content': '你是一个AI助手。请简单回复"连接测试成功"。'},
        {'role': 'user', 'content': '测试连接'},
      ];
      final response = await AINetworkManager.makeRequest(
        url: '',
        data: {'messages': testMessages, 'temperature': 0.1, 'max_tokens': 50},
        multiSettings: multiSettings,
        timeout: const Duration(seconds: 30),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        if (data['choices'] != null &&
            data['choices'].isNotEmpty &&
            data['choices'][0]['message'] != null) {
          logDebug(
            '多provider连接测试成功: ${data['choices'][0]['message']['content']}',
          );
        } else {
          logDebug('响应格式异常: $data');
        }
      } else {
        logDebug('响应状态码异常: ${response.statusCode}');
      }
    } catch (e) {
      logDebug('多provider连接测试失败: $e');
    }
  }

  static Future<void> testStreamConnection(
    SettingsService settingsService,
  ) async {
    logDebug('开始测试流式连接...');

    try {
      final multiSettings = settingsService.multiAISettings;

      final testMessages = [
        {'role': 'system', 'content': '你是一个AI助手。请用简单的几句话回复。'},
        {'role': 'user', 'content': '请介绍一下自己'},
      ];
      await AINetworkManager.makeStreamRequest(
        url: '',
        data: {'messages': testMessages, 'temperature': 0.7},
        multiSettings: multiSettings,
        onData: (String text) {
          logDebug('流式数据: $text');
        },
        onComplete: (String fullText) {
          logDebug('流式完成，全文: $fullText');
        },
        onError: (Exception error) {
          logDebug('流式错误: $error');
        },
      );
    } catch (e) {
      logDebug('流式连接测试失败: $e');
    }
  }
}
