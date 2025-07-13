import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:uuid/uuid.dart';
import '../models/quote_model.dart';
import '../models/generated_card.dart';
import '../constants/ai_card_prompts.dart';
import 'ai_service.dart';
import 'settings_service.dart';

/// AI卡片生成服务
class AICardGenerationService {
  final AIService _aiService;
  final SettingsService _settingsService;
  
  AICardGenerationService(this._aiService, this._settingsService);

  /// 为单条笔记生成卡片（智能选择风格）
  Future<GeneratedCard> generateCard({
    required Quote note,
    String? customStyle,
  }) async {
    try {
      // 1. 使用智能提示词
      final prompt = AICardPrompts.intelligentCardPrompt(
        content: note.content,
        author: note.sourceAuthor,
        date: _formatDate(note.date),
      );

      // 2. 调用AI生成SVG
      final svgContent = await _generateSVGContent(prompt);

      // 3. 清理和验证SVG
      final cleanedSVG = _cleanSVGContent(svgContent);

      // 4. 创建卡片对象（AI会智能选择类型）
      return GeneratedCard(
        id: const Uuid().v4(),
        noteId: note.id!,
        originalContent: note.content,
        svgContent: cleanedSVG,
        type: _parseCardTypeFromSVG(cleanedSVG), // 从SVG内容解析卡片类型
        createdAt: DateTime.now(),
      );
    } catch (e) {
      throw AICardGenerationException('卡片生成失败: $e');
    }
  }

  /// 批量生成（用于周期报告）
  Future<List<GeneratedCard>> generateFeaturedCards(
    List<Quote> notes, {
    int maxCards = 6,
  }) async {
    final cards = <GeneratedCard>[];
    
    for (final note in notes.take(maxCards)) {
      try {
        final card = await generateCard(note: note);
        cards.add(card);
      } catch (e) {
        if (kDebugMode) {
          print('生成卡片失败: ${note.id}, 错误: $e');
        }
        continue; // 跳过失败的卡片，继续生成其他卡片
      }
    }
    
    return cards;
  }

  /// 保存卡片为图片
  Future<String> saveCardAsImage(GeneratedCard card) async {
    try {
      // 使用卡片的toImageBytes方法获取图片数据
      final imageBytes = await card.toImageBytes();

      // 保存到相册
      await Gal.putImageBytes(
        imageBytes,
        name: 'card_${card.id}',
      );

      return 'card_${card.id}';
    } catch (e) {
      throw Exception('保存图片失败: $e');
    }
  }



  /// 增强的SVG清理逻辑，确保只保留SVG代码
  String _cleanSVGContent(String response) {
    if (kDebugMode) {
      print('原始AI响应长度: ${response.length}');
      print('原始AI响应前200字符: ${response.length > 200 ? response.substring(0, 200) : response}');
    }

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
      if (trimmedLine.contains('</svg>')) {
        svgLines.add(line);
        break; // SVG结束后停止处理
      }

      // 在SVG内部时保留所有行
      if (inSvg) {
        svgLines.add(line);
      }
    }

    cleaned = svgLines.join('\n').trim();

    // 如果没有找到完整的SVG，尝试简单的字符串提取
    if (!foundSvgStart || !cleaned.contains('<svg') || !cleaned.contains('</svg>')) {
      if (kDebugMode) {
        print('未找到完整SVG，尝试字符串提取...');
      }

      final svgStartIndex = response.indexOf('<svg');
      if (svgStartIndex >= 0) {
        final svgEndIndex = response.lastIndexOf('</svg>');
        if (svgEndIndex > svgStartIndex) {
          cleaned = response.substring(svgStartIndex, svgEndIndex + 6);
          if (kDebugMode) {
            print('字符串提取成功，SVG长度: ${cleaned.length}');
          }
        }
      }
    }

    // 最终验证和清理
    cleaned = _validateAndFixSVG(cleaned);

    if (kDebugMode) {
      print('清理后SVG长度: ${cleaned.length}');
      print('清理后SVG前200字符: ${cleaned.length > 200 ? cleaned.substring(0, 200) : cleaned}');
    }

    return cleaned;
  }

  /// 验证和修复SVG代码
  String _validateAndFixSVG(String svgContent) {
    // 基本结构验证
    if (!svgContent.contains('<svg') || !svgContent.contains('</svg>')) {
      throw const AICardGenerationException('AI返回的内容不包含有效的SVG代码');
    }

    String fixed = svgContent;

    // 确保SVG有正确的命名空间
    if (!fixed.contains('xmlns="http://www.w3.org/2000/svg"')) {
      fixed = fixed.replaceFirst('<svg', '<svg xmlns="http://www.w3.org/2000/svg"');
    }

    // 确保有viewBox或width/height
    if (!fixed.contains('viewBox') && !fixed.contains('width=') && !fixed.contains('height=')) {
      fixed = fixed.replaceFirst('<svg', '<svg viewBox="0 0 400 600"');
    }

    // 移除可能导致渲染问题的属性
    fixed = fixed
        .replaceAll(RegExp(r'style\s*=\s*"[^"]*font-family:[^"]*"'), '') // 移除可能不存在的字体
        .replaceAll(RegExp(r'xmlns:xlink="[^"]*"'), '') // 移除xlink命名空间（可能不需要）
        .trim();

    // 验证是否为有效的XML结构（简单检查）
    final openTags = RegExp(r'<(\w+)').allMatches(fixed).length;
    final closeTags = RegExp(r'</(\w+)>').allMatches(fixed).length;
    final selfClosingTags = RegExp(r'<\w+[^>]*/>').allMatches(fixed).length;

    if (kDebugMode) {
      print('SVG标签统计 - 开始标签: $openTags, 结束标签: $closeTags, 自闭合标签: $selfClosingTags');
    }

    return fixed;
  }



  /// 格式化日期
  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return '${date.year}年${date.month}月${date.day}日';
    } catch (e) {
      return dateStr;
    }
  }

  /// 生成SVG内容
  Future<String> _generateSVGContent(String prompt) async {
    // 检查AI服务是否可用
    if (!await _aiService.hasValidApiKeyAsync()) {
      throw const AICardGenerationException('请先在设置中配置 API Key');
    }

    try {
      // 获取当前provider
      final multiSettings = _settingsService.multiAISettings;
      final currentProvider = multiSettings.currentProvider;

      if (currentProvider == null) {
        throw const AICardGenerationException('未找到可用的AI提供商配置');
      }

      // 使用专门的SVG生成方法
      final svgContent = await _aiService.generateSVG(prompt);

      // 验证生成的SVG是否有效
      if (svgContent.trim().isEmpty) {
        throw const AICardGenerationException('AI返回了空的SVG内容');
      }

      return svgContent;
    } catch (e) {
      if (kDebugMode) {
        print('AI SVG生成失败: $e，尝试使用备用方案');
      }

      // 如果AI生成失败，使用备用的简单SVG
      return _generateFallbackSVG(prompt);
    }
  }

  /// 生成备用的简单SVG卡片
  String _generateFallbackSVG(String prompt) {
    // 从prompt中提取内容
    final contentMatch = RegExp(r'待处理内容：\n(.+?)(?:\n|$)', dotAll: true).firstMatch(prompt);
    final content = contentMatch?.group(1)?.trim() ?? '无法生成卡片内容';

    // 限制内容长度
    final displayContent = content.length > 100 ? '${content.substring(0, 100)}...' : content;

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 600">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#667eea;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#764ba2;stop-opacity:1" />
    </linearGradient>
  </defs>

  <!-- 背景 -->
  <rect width="400" height="600" fill="url(#bg)" rx="20"/>

  <!-- 装饰圆圈 -->
  <circle cx="350" cy="50" r="30" fill="rgba(255,255,255,0.1)"/>
  <circle cx="50" cy="550" r="40" fill="rgba(255,255,255,0.1)"/>

  <!-- 标题区域 -->
  <rect x="30" y="80" width="340" height="2" fill="rgba(255,255,255,0.8)"/>
  <text x="200" y="120" text-anchor="middle" fill="white" font-family="Arial, sans-serif" font-size="18" font-weight="bold">
    ThoughtEcho
  </text>

  <!-- 内容区域 -->
  <rect x="30" y="160" width="340" height="300" fill="rgba(255,255,255,0.9)" rx="15"/>

  <!-- 内容文字 -->
  <foreignObject x="50" y="180" width="300" height="260">
    <div xmlns="http://www.w3.org/1999/xhtml" style="font-family: Arial, sans-serif; font-size: 16px; line-height: 1.5; color: #333; padding: 20px; text-align: center;">
      ${displayContent.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')}
    </div>
  </foreignObject>

  <!-- 底部装饰 -->
  <rect x="30" y="520" width="340" height="2" fill="rgba(255,255,255,0.8)"/>
  <text x="200" y="550" text-anchor="middle" fill="white" font-family="Arial, sans-serif" font-size="12">
    ${DateTime.now().year}年${DateTime.now().month}月${DateTime.now().day}日
  </text>
</svg>
''';
  }

  /// 从SVG内容解析卡片类型
  /// 通过分析SVG中的元数据或内容特征来确定卡片类型
  CardType _parseCardTypeFromSVG(String svgContent) {
    try {
      // 查找SVG中的元数据注释或特定标识
      if (svgContent.contains('data-card-type="quote"') || 
          svgContent.contains('<!-- card-type: quote -->')) {
        return CardType.quote;
      }
      
      if (svgContent.contains('data-card-type="philosophical"') || 
          svgContent.contains('<!-- card-type: philosophical -->')) {
        return CardType.philosophical;
      }
      
      if (svgContent.contains('data-card-type="knowledge"') || 
          svgContent.contains('<!-- card-type: knowledge -->')) {
        return CardType.knowledge;
      }
      
      // 基于内容特征进行智能判断
      final lowerContent = svgContent.toLowerCase();
      
      // 检查是否包含引用特征
      if (lowerContent.contains('"') || lowerContent.contains('"') || 
          lowerContent.contains('quote') || lowerContent.contains('说') ||
          lowerContent.contains('引用') || lowerContent.contains('名言')) {
        return CardType.quote;
      }
      
      // 检查是否包含哲学思考特征
      if (lowerContent.contains('philosophy') || lowerContent.contains('philosophical') ||
          lowerContent.contains('哲学') || lowerContent.contains('思辨') ||
          lowerContent.contains('反思') || lowerContent.contains('思考') ||
          lowerContent.contains('人生') || lowerContent.contains('智慧')) {
        return CardType.philosophical;
      }
      
      // 默认返回知识类型
      return CardType.knowledge;
    } catch (e) {
      // 解析失败时返回默认类型
      return CardType.knowledge;
    }
  }

  /// 检查AI卡片生成功能是否启用
  bool get isEnabled {
    // 从设置服务中获取AI卡片生成开关状态
    return _settingsService.aiCardGenerationEnabled;
  }
}
