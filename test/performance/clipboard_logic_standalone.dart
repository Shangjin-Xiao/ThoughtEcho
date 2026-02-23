// test/performance/clipboard_logic_standalone.dart
import 'dart:async';

final RegExp _authorWithSourcePattern = RegExp(
  r'[-—–]+\s*([^《（\(]+?)?\s*[《（\(]([^》）\)]+?)[》）\)]\s*$',
);
final RegExp _sourceWithAuthorPattern = RegExp(
  r'[《（\(]([^》）\)]+?)[》）\)]\s*[-—–]+\s*([^，。,、\.\n]+)\s*$',
);
final RegExp _quoteWithAuthorPattern = RegExp(
  r'["""](.+?)["""]\s*[-—–]+\s*([^，。,、\.\n]+)\s*$',
);
final RegExp _fallbackAuthorPattern = RegExp(
  r'[-—–]+\s*([^，。,、\.\n《（\(]{2,20})\s*$',
);
final RegExp _fallbackSourcePattern = RegExp(r'[《（\(]([^》）\)]+?)[》）\)]\s*$');
final RegExp _cleanMetadataPattern = RegExp(r'^[—–\-—\s]+|[—–\-—\s]+$');

String? _cleanMetadata(String? input) {
  return input?.trim().replaceAll(_cleanMetadataPattern, '').trim();
}

Map<String, String?> _extractAuthorAndSource(String content) {
  final text = content.trim();
  String? author;
  String? source;
  String? matchedSubstring;

  // 1. 匹配 ——作者《出处》 或 --作者《出处》 等
  final m1 = _authorWithSourcePattern.firstMatch(text);
  if (m1 != null) {
    author = _cleanMetadata(m1.group(1));
    source = _cleanMetadata(m1.group(2));
    matchedSubstring = m1.group(0);
    return {
      'author': author,
      'source': source,
      'matched_substring': matchedSubstring,
    };
  }

  // 2. 匹配 《出处》——作者 或 《出处》--作者 等
  final m2 = _sourceWithAuthorPattern.firstMatch(text);
  if (m2 != null) {
    source = _cleanMetadata(m2.group(1));
    author = _cleanMetadata(m2.group(2));
    matchedSubstring = m2.group(0);
    return {
      'author': author,
      'source': source,
      'matched_substring': matchedSubstring,
    };
  }

  // 3. 匹配 "文"——作者 或 "文"--作者 等
  final m3 = _quoteWithAuthorPattern.firstMatch(text);
  if (m3 != null) {
    author = _cleanMetadata(m3.group(2));
    matchedSubstring = m3.group(0);
    return {
      'author': author,
      'source': null,
      'matched_substring': matchedSubstring,
    };
  }

  // 4. 回退提取作者
  final m4 = _fallbackAuthorPattern.firstMatch(text);
  if (m4 != null) {
    author = _cleanMetadata(m4.group(1));
    matchedSubstring = m4.group(0);
    final remainingText = text
        .substring(0, text.length - matchedSubstring!.length)
        .trim();
    final m4Source = _fallbackSourcePattern.firstMatch(remainingText);
    if (m4Source != null) {
      source = _cleanMetadata(m4Source.group(1));
      matchedSubstring = text.substring(
        remainingText.length - m4Source.group(0)!.length,
      );
    }
    return {
      'author': author,
      'source': source,
      'matched_substring': matchedSubstring,
    };
  }

  // 5. 回退提取出处
  final m5 = _fallbackSourcePattern.firstMatch(text);
  if (m5 != null) {
    source = _cleanMetadata(m5.group(1));
    matchedSubstring = m5.group(0);
    final remainingText = text
        .substring(0, text.length - matchedSubstring!.length)
        .trim();
    final m5Author = _fallbackAuthorPattern.firstMatch(remainingText);
    if (m5Author != null) {
      author = _cleanMetadata(m5Author.group(1));
      matchedSubstring = text.substring(
        remainingText.length - m5Author.group(0)!.length,
      );
    }
    return {
      'author': author,
      'source': source,
      'matched_substring': matchedSubstring,
    };
  }

  return {'author': null, 'source': null, 'matched_substring': null};
}

void main() {
  final testCases = [
    "这是正文 ——鲁迅《狂人日记》",
    "这是正文 《狂人日记》——鲁迅",
    '这是正文 "名言"——鲁迅',
    "这是正文 ——鲁迅",
    "这是正文 《狂人日记》",
    "没有元数据的正文",
  ];

  print('--- Functional Verification ---');
  for (var content in testCases) {
    final result = _extractAuthorAndSource(content);
    print('Content: $content');
    print('Result: $result');
  }

  print('\n--- Performance Benchmark ---');
  const iterations = 10000;
  final sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    for (var content in testCases) {
      _extractAuthorAndSource(content);
    }
  }
  sw.stop();
  print(
    'Total time for ${iterations * testCases.length} calls: ${sw.elapsedMilliseconds}ms',
  );
  print(
    'Average time per call: ${sw.elapsedMicroseconds / (iterations * testCases.length)}us',
  );
}
