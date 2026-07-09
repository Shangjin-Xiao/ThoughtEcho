import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/agent_tool.dart';
import 'package:thoughtecho/services/agent_tools/web_fetch_tool.dart';
import 'package:thoughtecho/services/web_fetch_service.dart';

void main() {
  group('WebFetchTool', () {
    test('rejects localhost before fetching', () async {
      final tool = WebFetchTool(WebFetchService());

      final result = await tool.execute(
        ToolCall(
          id: 'web_fetch_localhost',
          name: 'web_fetch',
          arguments: const {'url': 'http://localhost:8080/private'},
        ),
      );

      expect(result.isError, isTrue);
      expect(result.content, contains('安全限制'));
    });
  });
}
