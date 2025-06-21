import 'dart:developer' as developer;
import 'dart:io';

void main() async {
  // 需要添加导入的文件列表
  final filesToFix = [
    'lib/utils/multi_provider_manager.dart',
    'lib/utils/ai_request_helper.dart',
    'lib/utils/ai_connection_test.dart',
    'lib/utils/ai_network_manager.dart',
    'lib/utils/streaming_utils.dart',
    'lib/utils/mmkv_ffi_fix.dart',
    'lib/utils/dio_network_utils.dart',
    'lib/utils/http_utils.dart',
    'lib/utils/api_key_save_test.dart',
    'lib/utils/api_key_debugger.dart',
    'lib/widgets/note_list_view.dart',
    'lib/widgets/streaming_text_dialog.dart',
    'lib/widgets/add_note_dialog.dart',
    'lib/widgets/daily_quote_view.dart',
    'lib/widgets/city_search_widget.dart',
    'lib/theme/app_theme.dart',
    'lib/services/weather_service.dart',
    'lib/services/settings_service.dart',
    'lib/services/secure_storage_service.dart',
  ];

  const importStatement = "import 'package:thoughtecho/utils/app_logger.dart';";

  for (final filePath in filesToFix) {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final content = await file.readAsString();

        // 检查是否已经有导入
        if (content.contains(importStatement)) {
          developer.log('$filePath already has the import');
          continue;
        }

        // 找到最后一个import语句的位置
        final lines = content.split('\n');
        int insertIndex = 0;

        for (int i = 0; i < lines.length; i++) {
          if (lines[i].startsWith('import ')) {
            insertIndex = i + 1;
          } else if (lines[i].trim().isEmpty && insertIndex > 0) {
            // 找到import语句后的空行
            break;
          } else if (!lines[i].startsWith('import ') && insertIndex > 0) {
            // 找到非import语句
            break;
          }
        }

        // 插入导入语句
        lines.insert(insertIndex, importStatement);

        // 写回文件
        await file.writeAsString(lines.join('\n'));
        developer.log('Fixed imports for: $filePath');
      } else {
        developer.log('File not found: $filePath');
      }
    } catch (e) {
      developer.log('Error processing $filePath: $e');
    }
  }

  developer.log('Import fixing completed!');
}
