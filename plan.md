1.  **Refactor `_extractTitle` in `lib/utils/ai_command_helpers.dart`**:
    *   Currently, it uses `content.split('\n')` to get the first line of the content, which creates unnecessary intermediate `String` and `List` objects, increasing GC pressure.
    *   Replace `content.split('\n')` with `content.indexOf('\n')` to find the end of the first line. If found, extract the substring up to that point. If not found, use the entire string.
2.  **Refactor `_parseKeywords` in `lib/utils/ai_command_helpers.dart`**:
    *   Currently, it uses `keywords.split(',').map((k) => k.trim()).where((k) => k.isNotEmpty).toList()`. This creates a list of strings and uses closures.
    *   Replace it with a `while` loop that uses `indexOf(',')` to iterate over the string without creating intermediate lists, reducing GC pressure.
3.  **Ensure all tests in `test/unit/utils/ai_command_helpers_test.dart` still pass**:
    *   Run `flutter test test/unit/utils/ai_command_helpers_test.dart` to verify the refactored code works correctly.
4.  **Format and Analyze**:
    *   Run `dart format lib/utils/ai_command_helpers.dart`.
    *   Run `flutter analyze --no-fatal-infos`.
5.  **Pre-commit steps**:
    *   Run pre-commit instructions to ensure proper testing, verification, review, and reflection are done.
6.  **Create PR**:
    *   Create a PR with the title `⚡ Bolt: [优化 AI 命令助手中字符串分割造成的 GC 压力]`.
    *   Include `💡 What:`, `🎯 Why:`, `📊 Impact:`, and `🔬 Measurement:` in the description.
    *   Update `.jules/bolt.md` if necessary.
