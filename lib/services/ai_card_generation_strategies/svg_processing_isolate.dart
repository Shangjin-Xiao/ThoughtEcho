import '../../utils/app_logger.dart';
import 'card_generation_utils.dart';

/// DTO for passing data to the isolate
///
/// Contains all necessary information to process the SVG card in a background isolate.
class AICardProcessingData {
  final String svgContent;
  final String brandName;
  final String? date;
  final String? location;
  final String? weather;
  final String? temperature;
  final String? author;
  final String? source;
  final String? dayPeriod;
  final String languageCode;

  AICardProcessingData({
    required this.svgContent,
    required this.brandName,
    required this.date,
    this.location,
    this.weather,
    this.temperature,
    this.author,
    this.source,
    this.dayPeriod,
    this.languageCode = 'zh',
  });
}

/// Log entry generated during isolate processing
class AICardProcessingLog {
  final String level; // 'DEBUG', 'INFO', 'WARN', 'ERROR'
  final String message;

  AICardProcessingLog(this.level, this.message);
}

/// DTO for returning results from the isolate
class AICardProcessingResult {
  final String svg;
  final List<AICardProcessingLog> logs;

  AICardProcessingResult({
    required this.svg,
    required this.logs,
  });
}

/// Isolate worker function responsible for cleaning SVG and injecting metadata.
///
/// This runs in a background isolate to prevent UI jank.
Future<AICardProcessingResult> processSVGTask(AICardProcessingData data) async {
  final logs = <AICardProcessingLog>[];
  logs.add(AICardProcessingLog(
      'DEBUG', '开始清理SVG内容，原始长度: ${data.svgContent.length}'));

  try {
    // 1. Clean SVG
    String cleaned = _cleanSVGContentStatic(data.svgContent, logs);

    // 2. Ensure Metadata
    cleaned = _ensureMetadataPresenceStatic(
      cleaned,
      brandName: data.brandName,
      date: data.date,
      location: data.location,
      weather: data.weather,
      temperature: data.temperature,
      author: data.author,
      source: data.source,
      dayPeriod: data.dayPeriod,
      languageCode: data.languageCode,
      logs: logs,
    );

    logs.add(AICardProcessingLog('DEBUG', 'SVG处理完成，最终长度: ${cleaned.length}'));
    return AICardProcessingResult(svg: cleaned, logs: logs);
  } catch (e) {
    logs.add(AICardProcessingLog('ERROR', 'SVG处理失败: $e'));
    rethrow;
  }
}

/// 静态清理SVG内容 (用于Isolate)
String _cleanSVGContentStatic(String response, List<AICardProcessingLog> logs) {
  String cleaned = response.trim();

  // 移除常见的markdown标记和说明文字
  cleaned = cleaned
      .replaceAll('```svg', '')
      .replaceAll('```xml', '')
      .replaceAll('```html', '')
      .replaceAll('```', '')
      .replaceAll('`', '')
      .trim();

  // 移除可能的说明文字（在SVG前后）
  final lines = cleaned.split('\n');
  final svgLines = <String>[];
  bool inSvg = false;
  bool foundSvgStart = false;

  for (final line in lines) {
    final trimmedLine = line.trim();

    // 跳过空行和注释行（除非在SVG内部）
    if (!inSvg && (trimmedLine.isEmpty || trimmedLine.startsWith('//'))) {
      continue;
    }

    // 检测SVG开始
    if (trimmedLine.startsWith('<svg')) {
      inSvg = true;
      foundSvgStart = true;
      svgLines.add(line);
      continue;
    }

    // 检测SVG结束
    if (inSvg && trimmedLine.contains('</svg>')) {
      // 提取结束标签及之前的内容
      final endIndex = line.indexOf('</svg>') + 6;
      svgLines.add(line.substring(0, endIndex));
      inSvg = false;
      break; // 结束标签后的内容全部丢弃
    }

    if (inSvg) {
      svgLines.add(line);
    } else if (foundSvgStart) {
      // 如果已经找到过开始标签，但当前不在svg内部（可能因为中间有异常截断），尝试继续
      svgLines.add(line);
    }
  }

  if (svgLines.isNotEmpty) {
    cleaned = svgLines.join('\n');
    // 如果没有找到结束标签，强制补全
    if (!cleaned.contains('</svg>')) {
      logs.add(AICardProcessingLog('WARN', 'SVG缺少结束标签，自动补全'));
      cleaned += '\n</svg>';
    }
  } else {
    // 降级处理：如果没有匹配到标准的<svg>结构，直接查找第一个<svg和最后一个</svg>
    final startIndex = cleaned.indexOf('<svg');
    final endIndex = cleaned.lastIndexOf('</svg>');

    if (startIndex != -1 && endIndex != -1) {
      cleaned = cleaned.substring(startIndex, endIndex + 6);
    } else {
      logs.add(AICardProcessingLog('WARN', '无法提取标准SVG内容，将尝试直接解析'));
    }
  }

  // 深度清理：修复AI常见的XML语法错误
  // 1. 修复重复的 xmlns 属性
  cleaned = cleaned.replaceAll(RegExp(r'xmlns="[^"]+"\s+xmlns="[^"]+"'),
      'xmlns="http://www.w3.org/2000/svg"');

  // 2. 修复未闭合的标签（简单修复，针对单标签如 <path ... > 变 <path ... />）
  // 这种修复比较危险，仅在无法解析时作为备选方案，这里暂且跳过

  // 3. 移除不支持的标签或属性
  // cleaned = cleaned.replaceAll(RegExp(r'<script.*?>.*?</script>', dotAll: true), '');

  if (!_isValidSVGStructure(cleaned)) {
    throw Exception('提取到的内容不是有效的SVG结构');
  }

  cleaned = _normalizeSVGAttributes(cleaned);

  if (!_isSafeSVGContent(cleaned, logs)) {
    throw Exception('生成的内容包含潜在危险的元素，已被拦截');
  }

  return cleaned;
}

/// 静态元数据补全 (用于Isolate)
String _ensureMetadataPresenceStatic(
  String svg, {
  required String brandName,
  required String? date,
  String? location,
  String? weather,
  String? temperature,
  String? author,
  String? source,
  String? dayPeriod,
  String languageCode = 'zh',
  List<AICardProcessingLog>? logs,
}) {
  final lower = svg.toLowerCase();
  final hasDate = date != null && lower.contains(date.toLowerCase());
  final hasLocation =
      location != null && lower.contains(location.toLowerCase());
  final hasWeather = weather != null && lower.contains(weather.toLowerCase());
  final hasBrand = lower.contains(brandName.toLowerCase());
  final need = !hasBrand ||
      (date != null && !hasDate) ||
      (location != null && !hasLocation) ||
      (weather != null && !hasWeather);
  if (!need) {
    return svg; // 必需元数据已存在
  }
  // 简单插入在 </svg> 前
  final metaParts = <String>[];
  // 规则：程序自动补全 -> 根据语言本地化
  final localizedWeather =
      CardGenerationUtils.localizeWeather(weather, languageCode: languageCode);
  final localizedDayPeriod = CardGenerationUtils.localizeDayPeriod(dayPeriod,
      languageCode: languageCode);

  if (date != null) metaParts.add(date); // 已是格式化的
  if (location != null) metaParts.add(location); // 用户输入不改动
  if (localizedWeather != null) {
    metaParts.add(
      temperature != null ? '$localizedWeather $temperature' : localizedWeather,
    );
  }
  if (author != null) metaParts.add(author);
  if (source != null && source != author) metaParts.add(source);
  if (localizedDayPeriod != null) metaParts.add(localizedDayPeriod);
  metaParts.add(brandName);
  final meta = metaParts.join(' · ');
  final (width, height) = _inferSvgIntrinsicSize(svg);
  final footerX = (double.tryParse(width) ?? 400) / 2;
  final footerY = (double.tryParse(height) ?? 600) - 10;
  final injection =
      '<text x="$footerX" y="$footerY" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="10" fill="#ffffff" fill-opacity="0.75">${_escape(meta)}</text>';
  final idx = svg.lastIndexOf('</svg>');
  if (idx == -1) {
    return svg; // 非法结构保持原样
  }
  return svg.substring(0, idx) + injection + svg.substring(idx);
}

String _escape(String v) =>
    v.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

// 检测是否包含中文
// ignore: unused_element
bool _containsChinese(String text) => RegExp(r'[\u4e00-\u9fff]').hasMatch(text);

/// 验证SVG基本结构
bool _isValidSVGStructure(String svgContent) {
  if (svgContent.trim().isEmpty) return false;

  // 基本结构检查
  if (!svgContent.contains('<svg') || !svgContent.contains('</svg>')) {
    return false;
  }

  // 检查标签是否正确闭合（简单检查）
  final openTags = '<svg'.allMatches(svgContent).length;
  final closeTags = '</svg>'.allMatches(svgContent).length;
  if (openTags != closeTags) {
    return false;
  }

  // 检查是否有基本的SVG内容
  if (svgContent.length < 50) {
    // 太短的SVG可能无效
    return false;
  }

  return true;
}

final RegExp _viewBoxRegex = RegExp(r'viewBox="([^"]+)"');
final RegExp _splitSpaceCommaRegex = RegExp(r'[\s,]+');
final RegExp _widthRegex = RegExp(r'width="([^"]+)"');
final RegExp _heightRegex = RegExp(r'height="([^"]+)"');
final RegExp _rectFallbackRegex =
    RegExp(r'<rect[^>]*width="([^"]+)"[^>]*height="([^"]+)"');
final RegExp _numericRegex = RegExp('[^0-9.-]');

/// 标准化SVG属性
String _normalizeSVGAttributes(String svgContent) {
  String normalized = svgContent;

  // 确保SVG有正确的命名空间
  if (!normalized.contains('xmlns="http://www.w3.org/2000/svg"')) {
    normalized = normalized.replaceFirst(
      '<svg',
      '<svg xmlns="http://www.w3.org/2000/svg"',
    );
  }

  final inferredSize = _inferSvgIntrinsicSize(normalized);

  // 移除现有的viewBox、width、height、preserveAspectRatio属性，避免AI返回的百分比尺寸导致错位
  normalized = normalized.replaceFirstMapped(
    RegExp(r'<svg\b[^>]*>'),
    (match) => match
        .group(0)!
        .replaceAll(RegExp(r'\s+viewBox="[^"]*"'), '')
        .replaceAll(RegExp(r'\s+width="[^"]*"'), '')
        .replaceAll(RegExp(r'\s+height="[^"]*"'), '')
        .replaceAll(RegExp(r'\s+preserveAspectRatio="[^"]*"'), ''),
  );

  // 统一设置标准属性: 仅设置viewBox与保留比例，不强制width/height，让预览与导出一致
  normalized = normalized.replaceFirst(
    '<svg',
    '<svg viewBox="0 0 ${inferredSize.$1} ${inferredSize.$2}" preserveAspectRatio="xMidYMid meet"',
  );

  return normalized;
}

/// 推断SVG内在尺寸，忽略百分比/无效尺寸，防止viewBox被错误设置为100导致裁剪
(String, String) _inferSvgIntrinsicSize(String svgContent) {
  // 1) 优先使用合法的viewBox
  final viewBoxMatch = _viewBoxRegex.firstMatch(svgContent);
  if (viewBoxMatch != null) {
    final parts = viewBoxMatch.group(1)!.split(_splitSpaceCommaRegex);
    if (parts.length == 4 && parts.every((p) => double.tryParse(p) != null)) {
      return (parts[2], parts[3]);
    }
  }

  // 2) 解析根节点的width/height（忽略百分比）
  double? w = _parseNumericDimension(
    _widthRegex.firstMatch(svgContent)?.group(1),
  );
  double? h = _parseNumericDimension(
    _heightRegex.firstMatch(svgContent)?.group(1),
  );

  // 3) 如果根尺寸不可靠，尝试从首个rect推断（通常为背景矩形）
  if (w == null || h == null) {
    final rectMatch = _rectFallbackRegex.firstMatch(svgContent);
    if (rectMatch != null) {
      w = _parseNumericDimension(rectMatch.group(1)) ?? w;
      h = _parseNumericDimension(rectMatch.group(2)) ?? h;
    }
  }

  // 4) 回退默认值
  w ??= 400;
  h ??= 600;

  return (w.toString(), h.toString());
}

double? _parseNumericDimension(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  if (raw.contains('%')) return null;
  final cleaned = raw.replaceAll(_numericRegex, '');
  if (cleaned.isEmpty) return null;
  final parsed = double.tryParse(cleaned);
  if (parsed == null || parsed <= 0) return null;
  return parsed;
}

/// 验证SVG内容安全性
bool _isSafeSVGContent(String svgContent, [List<AICardProcessingLog>? logs]) {
  // 检查是否包含潜在危险的元素
  final dangerousPatterns = [
    RegExp(r'<\s*(script|iframe|object|embed|foreignObject)\b',
        caseSensitive: false),
    RegExp(r'\bon[a-z]+\s*=', caseSensitive: false),
    RegExp(r'''(?:javascript:|data:text/html)''', caseSensitive: false),
  ];

  for (final dangerous in dangerousPatterns) {
    if (dangerous.hasMatch(svgContent)) {
      final msg = '发现不安全的SVG元素: ${dangerous.pattern}';
      if (logs != null) {
        logs.add(AICardProcessingLog('WARN', msg));
      } else {
        AppLogger.w(msg, source: 'AICardGeneration');
      }
      return false;
    }
  }

  return true;
}
