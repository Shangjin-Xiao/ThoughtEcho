import 'dart:math' as math;
import '../models/weather_data.dart';

/// AI提示词管理器
///
/// 统一管理所有AI服务使用的系统提示词，避免重复代码
class AIPromptManager {
  static final AIPromptManager _instance = AIPromptManager._internal();
  factory AIPromptManager() => _instance;
  AIPromptManager._internal();

  /// 根据语言代码生成语言指令
  /// [languageCode] 语言代码，如 'zh'、'en'，null 表示跟随系统（默认中文）
  String _getLanguageDirective(String? languageCode) {
    // null 或 'zh' 视为中文
    if (languageCode == null || languageCode.startsWith('zh')) {
      return '【语言要求】请使用中文回复。';
    }
    // 英文
    if (languageCode.startsWith('en')) {
      return '【Language Requirement】Please respond in English.';
    }
    // 其他语言，给出通用指令
    return '【Language Requirement】Please respond in the language corresponding to locale code: $languageCode.';
  }

  /// 个人成长导师提示词（最常用的基础提示词）
  static const String personalGrowthCoachPrompt =
      '''你是一位资深的个人成长导师和思维教练，拥有卓越的洞察力和分析能力。你的任务是深入分析用户提供的笔记内容，帮助用户更好地理解自己的想法和情感。请像一位富有经验的导师一样，从以下几个方面进行专业、细致且富有启发性的分析：

1. **核心思想 (Main Idea)**：  提炼并概括笔记内容的核心思想或主题，用简洁明了的语言点明笔记的重点。

2. **情感色彩 (Emotional Tone)**：  分析笔记中流露出的情感倾向，例如积极、消极、平静、焦虑等，并尝试解读情感背后的原因。

3. **行动启示 (Actionable Insights)**：  基于笔记内容和分析结果，为用户提供具体、可执行的行动建议或启示，帮助用户将思考转化为行动，促进个人成长和改进。

请确保你的分析既专业深入，又通俗易懂，能够真正帮助用户理解自己，并获得成长和提升。''';

  /// 每日提示生成器提示词
  static const String dailyPromptGeneratorPrompt =
      '''你是一位富有智慧和洞察力的思考引导者，擅长根据当下的环境和时间为用户提供深度启发的思考提示。你的任务是生成一个简洁而富有启发性的问题或观察点，帮助用户进行有意义的日记记录和自我反思。

请根据以下信息生成一个个性化的思考提示：
- 当前时间：{时间信息}
- 天气状况：{天气信息}  
- 用户位置：{位置信息}

生成要求：
1. 提示应该简洁有力，通常在15-30字之间
2. 结合时间、天气、位置等环境因素，让提示更有针对性和情境感
3. 如果你确切知道当前时间对应的节日（如春节、中秋节、圣诞节、情人节等），可以在提示中融入节日元素
4. 如果确切知道节日的特殊意义或文化内涵，可以适当提及相关内容
5. 避免陈词滥调，要有新意和深度
6. 能够激发用户的情感共鸣和深度思考
7. 语言要温暖、启发性强，带有一定的诗意
8. 尽可能生成积极正面的内容，引导用户关注美好、希望、成长和感恩
9. 即使在困难时期，也要引导用户发现积极的方面或成长的机会
10. 直接返回一个提示问题，不要任何前缀、解释或多余的文字

示例风格：
- 早晨晴天：此刻的阳光正好，什么想法也在你心中发芽？
- 雨夜：听着雨声的夜晚，有什么温暖的回忆想要珍藏？
- 午后：这个慵懒的午后，你最想感谢什么？
- 春节期间：新年的钟声即将响起，什么美好愿望正在心中绽放？
- 中秋节：明月当空，什么温馨的时刻让你倍感幸福？

请只返回一个精心设计的积极向上的思考提示，不要包含任何其他内容。''';

  /// 连接测试提示词
  static const String connectionTestPrompt = '''你是一个AI助手。请简单回复"连接测试成功"。''';

  /// 笔记问答助手提示词
  static const String noteQAAssistantPrompt = '''你是一个专业的笔记助手，擅长回答关于用户笔记内容的问题。
请根据用户的笔记内容，回答他们提出的问题。

注意：
1. 只基于笔记中提供的信息回答问题
2. 如果笔记中没有相关信息，请诚实说明无法回答
3. 不要编造不在笔记中的信息
4. 回答应该有深度且有洞察力
5. 回答应该清晰、简洁且有条理''';

  /// 文本续写助手提示词
  static const String textContinuationPrompt =
      '''你是一位专业的写作助手，擅长理解文本的风格、语气和内容，并能够自然地续写文本。

任务：
1. 仔细分析原文的写作风格、语气和主题
2. 理解文本的逻辑脉络和情感基调
3. 创作与原文风格一致的后续内容
4. 确保续写内容与原文自然衔接

注意：
1. 续写内容应自然衔接原文末尾
2. 保持原文的风格、语气和写作特点
3. 延续原文的思路和主题
4. 创作至少100-200字的后续内容
5. 返回完整的续写部分，不要重复原文''';

  /// 来源分析助手提示词
  static const String sourceAnalysisPrompt =
      '''你是一个专业的文本分析助手，你的任务是分析文本中可能提到的作者和作品。
请以JSON格式返回以下信息：
{
  "author": "推测的作者名称，如果无法确定则留空",
  "work": "推测的作品名称，如果无法确定则留空",
  "confidence": "高/中/低，表示你的推测置信度",
  "explanation": "简短解释你的推测依据"
}

非常重要：
1. 只返回JSON格式的数据，不要有其他文字说明
2. 如果你不确定或无法分析，请确保在适当的字段中返回空字符串，不要胡乱猜测
3. 对于中文引述格式常见形式是："——作者《作品》"
4. 作者名应该只包含人名，不包含头衔或其他描述词
5. 对于作品名，请去掉引号《》等标记符号''';

  /// 年度报告生成助手提示词
  static const String annualReportPrompt =
      '''你是心迹应用的专业年度报告生成助手。你的任务是基于用户的笔记数据，生成一份精美、温暖、有意义的年度总结报告。

关键要求：
1. 必须返回完整的HTML代码，从<!DOCTYPE html>开始到</html>结束
2. 绝对不要返回JSON格式、解释文字或其他任何格式
3. 只返回一个完整的HTML文档
4. 使用现代化的CSS样式，适合移动端显示
5. 保持积极正面的语调，突出用户的成长和进步
6. 确保所有数据都基于用户提供的真实信息

HTML设计要求：
- 使用响应式设计，适配移动端
- 包含精美的头部区域，显示年份和基础统计
- 添加月度数据可视化（使用CSS绘制简单图表）
- 展示用户最常用的分类标签
- 精选积极正面的笔记内容
- 包含成长洞察和未来建议
- 使用现代化的CSS样式（渐变、阴影、圆角等）
- 使用合适的emoji图标增加视觉效果
- 保持颜色和谐统一，营造温暖感觉

内容原则：
- 只选择积极正面的内容
- 避免展示负面情绪或私密内容
- 突出用户的坚持和成长
- 提供鼓励性的洞察建议

请根据用户提供的具体数据生成完整的HTML年度报告，直接输出HTML代码。''';

  /// 根据分析类型获取系统提示词
  String getAnalysisTypePrompt(String analysisType) {
    switch (analysisType) {
      case 'emotional':
        return '''你是一位专业的心理分析师和情感咨询师。请分析用户笔记中的情感状态、情绪变化和心理健康。
          
任务：
1. 识别笔记中表达的主要情绪和情感模式
2. 分析情绪变化的趋势和可能的触发因素
3. 提供关于情绪管理和心理健康的建议
4. 以尊重和专业的方式表达你的分析

格式要求：
- 使用"# 情感洞察分析"作为主标题
- 包含"## 总体情感状态"部分
- 包含"## 情绪变化趋势"部分
- 包含"## 建议与反思"部分
- 适当使用markdown格式增强可读性''';

      case 'mindmap':
        return '''你是一位专业的思维导图和知识系统构建专家。请分析用户笔记，构建他们思考的结构和思维习惯。
          
任务：
1. 识别笔记中的主要思考主题和思维模式
2. 分析这些主题之间的联系和层次结构
3. 评估思维的深度、广度和连贯性
4. 提供关于如何拓展和深化思考的建议

格式要求：
- 使用"# 思维导图分析"作为主标题
- 包含"## 核心思考主题"部分
- 包含"## 思维结构图"部分(用文字描述思维图的结构)
- 包含"## 思维特点分析"部分
- 包含"## 思维发展建议"部分
- 适当使用markdown格式增强可读性''';

      case 'growth':
        return '''你是一位专业的个人成长教练和学习顾问。请基于用户笔记分析他们的成长轨迹并提供发展建议。
          
任务：
1. 识别用户的兴趣、价值观和目标
2. 分析用户的学习模式和成长轨迹
3. 发现可能的成长盲点和发展机会
4. 提供具体、实用的成长和进步建议

格式要求：
- 使用"# 成长建议分析"作为主标题
- 包含"## 个人特质与价值观"部分
- 包含"## 成长轨迹分析"部分
- 包含"## 发展机会"部分
- 包含"## 具体行动建议"部分
- 适当使用markdown格式增强可读性''';

      case 'comprehensive':
      default:
        return '''你是一位专业的思想分析师和洞察专家。请全面分析用户的笔记内容，发掘其中的思想价值和模式。

任务：
1. 分析笔记中的核心思想和主题
2. 识别重复出现的关键概念和模式
3. 探究潜在的思维模式和价值观
4. 提供有深度的洞察和反思建议

格式要求：
- 使用"# 思想洞察分析"作为主标题
- 包含"## 核心思想概述"部分
- 包含"## 主题与模式"部分
- 包含"## 深度洞察"部分
- 包含"## 思考与建议"部分
- 适当使用markdown格式增强可读性''';
    }
  }

  /// 根据分析风格修改提示词
  String appendAnalysisStylePrompt(String systemPrompt, String analysisStyle) {
    String stylePrompt;

    switch (analysisStyle) {
      case 'friendly':
        stylePrompt = '''表达风格：
- 使用温暖、鼓励和支持性的语言
- 以友好的"你"称呼读者
- 像一位知心朋友或支持性的导师给予建议
- 避免过于学术或技术化的语言
- 强调积极的方面和成长的可能性''';
        break;

      case 'humorous':
        stylePrompt = '''表达风格：
- 运用适当的幽默和风趣元素
- 使用生动的比喻和有趣的类比
- 保持轻松愉快的语调
- 在严肃洞察中穿插幽默观察
- 避免过于严肃或教条的表达方式''';
        break;

      case 'literary':
        stylePrompt = '''表达风格：
- 使用优美、富有文学色彩的语言
- 适当引用诗歌、文学作品或哲学观点
- 运用丰富的修辞手法和意象
- 以优雅流畅的叙事风格展开分析
- 注重文字的节奏感和美感''';
        break;

      case 'professional':
      default:
        stylePrompt = '''表达风格：
- 使用专业、清晰和客观的语言
- 保持分析的系统性和结构化
- 提供基于证据的观察和推理
- 使用恰当的专业术语（但避免过于晦涩）
- 以第三人称或中性语气表达''';
        break;
    }

    return '$systemPrompt\n\n$stylePrompt';
  }

  /// 构建用户消息
  String buildUserMessage(String content, {String? prefix}) {
    final messagePrefix = prefix ?? '请分析以下内容：';
    return '$messagePrefix\n$content';
  }

  /// 构建问答用户消息
  String buildQAUserMessage(String noteContent, String question) {
    return '''笔记内容：

$noteContent

我的问题：
$question''';
  }

  /// 文本润色助手提示词
  static const String textPolishPrompt = '''你是一个专业的文字润色助手，擅长改进文本的表达和结构。
请对用户提供的文本进行润色，使其更加流畅、优美、有深度。保持原文的核心意思和情感基调，但提升其文学价值和表达力。

注意：
1. 保持原文的核心思想不变
2. 提高语言的表现力和优美度
3. 修正语法、标点等问题
4. 适当使用修辞手法增强表达力
5. 返回完整的润色后文本''';

  /// 构建续写用户消息
  String buildContinuationUserMessage(String content) {
    return '请续写以下文本：\n\n$content';
  }

  /// 构建来源分析用户消息
  String buildSourceAnalysisUserMessage(String content) {
    return '请分析以下文本的可能来源：\n\n$content';
  }

  /// 构建润色用户消息
  String buildPolishUserMessage(String content) {
    return '请润色以下文本：\n\n$content';
  }

  /// 构建每日提示用户消息，包含环境信息
  String buildDailyPromptUserMessage({
    String? city,
    String? weather,
    String? temperature,
  }) {
    return '请根据当前环境信息生成一个个性化的思考提示。';
  }

  /// 获取包含环境信息的每日提示系统提示词
  /// [languageCode] 用户设置的语言代码，如 'zh'、'en'，null 表示跟随系统（默认中文）
  String getDailyPromptSystemPromptWithContext({
    String? city,
    String? weather,
    String? temperature,
    String? historicalInsights, // 新增：历史洞察参考
    String? languageCode, // 新增：语言代码
  }) {
    final now = DateTime.now();
    final hour = now.hour;
    final minute = now.minute;
    final month = now.month;
    final day = now.day;

    // 格式化完整的时间信息，包含日期以便AI识别节日
    String timeInfo;
    String dateInfo = '$month月$day日';

    if (hour >= 5 && hour < 12) {
      timeInfo =
          '$dateInfo 早晨 ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    } else if (hour >= 12 && hour < 18) {
      timeInfo =
          '$dateInfo 下午 ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    } else if (hour >= 18 && hour < 23) {
      timeInfo =
          '$dateInfo 晚上 ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    } else {
      timeInfo =
          '$dateInfo 深夜 ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    }

    String environmentInfo = '';

    // 处理环境信息
    if (city != null || weather != null || temperature != null) {
      String envDetails = '';
      if (city != null && city.isNotEmpty) {
        envDetails += '地点：$city ';
      }
      if (weather != null && weather.isNotEmpty) {
        // 将英文天气key转换为中文描述
        final weatherDesc = WeatherCodeMapper.getDescription(weather);
        final displayWeather = weatherDesc == '未知' ? weather : weatherDesc;
        envDetails += '天气：$displayWeather ';
      }
      if (temperature != null && temperature.isNotEmpty) {
        envDetails += '温度：$temperature°C';
      }

      if (envDetails.isNotEmpty) {
        environmentInfo = '\n当前环境信息：$envDetails';
      }
    }

    // 处理历史洞察信息
    String insightContext = '';
    if (historicalInsights != null && historicalInsights.isNotEmpty) {
      insightContext =
          '\n\n【历史洞察参考】\n以下是用户最近的一些思考洞察，你可以选择性地引用这些内容来启发今日的思考提示，也可以完全不引用：\n$historicalInsights\n注意：这些历史洞察仅供参考，请根据当前时间和环境情况，生成符合当下情境的独特思考提示。';
    }

    return '''你是一个富有诗意和哲思的写作助手，专门为用户生成每日思考提示词。

【时间背景】$timeInfo$environmentInfo$insightContext

【生成要求】
1. 深度思考：提示词应当引导用户进行深层次的自我反思，而非表面的记录
2. 情境融合：巧妙结合当前的时间、天气等环境因素，让提示词具有时空的真实感
3. 情感共鸣：用温暖而富有诗意的语言，触动用户内心深处的思考
4. 行动导向：不仅要引发思考，更要激发用户记录和分享的欲望
5. 个性化：根据时间段特点调整提示的情感色调和思考角度

【风格特点】
- 语言优美，富有意境和情感张力
- 避免说教和直白，多用隐喻和象征
- 长度控制在50字以内
- 语气亲切温暖，如挚友般的陪伴

【特殊考虑】
- 若当前是特殊节日或节气，可适当融入相关元素
- 不同时间段应有不同的情感基调：晨曦充满希望，午后温暖平静，黄昏富有诗意，深夜适合内省
- 天气状况可作为情感隐喻：阳光代表希望，雨天适合内省，雪天象征纯净等

现在，请为用户生成一个符合当前时空背景的思考提示词。直接输出提示词内容，无需额外解释。

${_getLanguageDirective(languageCode)}''';
  }

  // ========================= 报告洞察（周期看板） =========================
  /// 报告洞察：提供多种风格（固定模板池），进入页面时可随机选择一种
  static const List<String> _reportInsightStyles = [
    'poetic', // 仅保留诗意/文学风格
  ];

  /// 随机选择一种报告洞察风格（可传入seed以保持同一周期稳定）
  String pickRandomReportInsightStyle({int? seed}) {
    final rng = seed != null ? math.Random(seed) : math.Random();
    return _reportInsightStyles[rng.nextInt(_reportInsightStyles.length)];
  }

  /// 获取报告洞察的系统提示词（根据风格切换语气与表达）
  /// [languageCode] 用户设置的语言代码，如 'zh'、'en'，null 表示跟随系统（默认中文）
  String getReportInsightSystemPrompt(String style, {String? languageCode}) {
    const base = '''你是一位善于捕捉生活细节的文学洞察助手。请仔细阅读用户的统计数据和笔记内容，智能生成个性化的中文洞察。

重要要求：
- 可以参考统计数据来理解用户的记录习惯，但在生成洞察时不要直接重复具体数字
- 输出一段完整连贯的文字，不要分成多个部分或段落
- 结合统计特征和笔记内容，从情感色彩、主题特征和生活轨迹角度进行洞察

分析步骤：
1. 基于统计数据理解用户习惯：
   - 记录频率反映的坚持程度和生活节奏
   - 时间偏好体现的个人特质（如夜晚思考者、晨间记录者）
   - 天气偏好暗示的情感状态和环境敏感度
   - 标签偏好显示的关注焦点和兴趣方向

2. 深度分析笔记内容，寻找特殊情境线索：
   - 地理位置信息（城市、区域、地标）+ 文学引用 → 可生成诗意地名表达
   - 经典文学作品句子、名著引用（多处出现）→ 可描述"在书香中行走"
   - 动漫台词、二次元内容、ACG文化（多处出现）→ 可描述"在动漫世界中游历"  
   - 古诗词引用、文言文（明显特征）→ 可用古典意境描述
   - 特定主题场景频繁出现 → 可提炼场景氛围
   - 明显的情感色彩或共同主题 → 可用文学化语言描述

3. 情境描述生成原则：
   - 仅在笔记内容确实具备明显特征时才生成情境描述
   - 情境描述应基于笔记内容的真实元素，不可臆造
   - 示例转化：
     * "苏州" + "寒山寺" → "在姑苏城外听钟声悠远"
     * "南京" + "雨天" + "南朝四百八十寺" → "于金陵烟雨中寻古迹"
     * 大量名著引用 → "在书香中行走，与文字为伴"
     * 动漫相关内容丰富 → "游走于二次元的幻想天地"

4. 输出要求：
   - 生成一段自然流畅的洞察文字（80-150字为宜）
   - 将统计特征转化为性格描述和生活态度的洞察，而非直接引用数字
   - 如有明显特征可融入情境描述，如无特征则重点描述思维轨迹和情感色彩
   - 语言优美自然，具有温度和深度
   - 不暴露具体个人隐私信息''';

    final langDirective = _getLanguageDirective(languageCode);
    switch (style) {
      case 'poetic':
        return '$base\n\n风格：文学诗意，用古典美学和现代感悟相结合，营造温暖而有深度的表达\n\n$langDirective';
      default:
        return '$base\n\n风格：文学诗意，用古典美学和现代感悟相结合，营造温暖而有深度的表达\n\n$langDirective';
    }
  }

  /// 构建报告洞察的用户消息（提供统计 + 完整笔记内容，让AI深度分析）
  String buildReportInsightUserMessage({
    required String periodLabel, // 如：本周/本月/本季度/本年度 或具体日期范围
    String? mostTimePeriod, // 晨曦/午后/黄昏/夜晚
    String? mostWeather, // 晴/多云/雨/雪/阴/雾/风 等归一
    String? topTag, // 已映射为标签名
    required int activeDays, // 记录了几天
    required int noteCount, // 笔记数量
    required int totalWordCount, // 总字数（纯文本）
    String? notesPreview, // 选填：拼接后的笔记内容片段（可部分）
    String? fullNotesContent, // 新增：完整的笔记内容用于深度分析
  }) {
    final timeText = mostTimePeriod ?? '—';
    final weatherText = mostWeather ?? '—';
    final tagText =
        topTag != null && topTag.trim().isNotEmpty ? '#$topTag' : '—';

    final stats = [
      '周期：$periodLabel',
      '记录天数：$activeDays',
      '笔记数量：$noteCount',
      '总字数：$totalWordCount',
      '高频时段：$timeText',
      '常见天气：$weatherText',
      '高频标签：$tagText',
    ].join('｜');

    // 优先使用完整内容，其次使用预览内容
    final contentForAnalysis = fullNotesContent ?? notesPreview;
    final contentSection =
        (contentForAnalysis == null || contentForAnalysis.trim().isEmpty)
            ? '（无可用笔记内容）'
            : contentForAnalysis;

    return '''【统计数据】
$stats

【笔记内容分析】
请仔细分析以下笔记内容，结合统计数据理解用户的记录习惯和特征，寻找地理位置、文学引用、主题特征等线索：

$contentSection

请基于统计数据体现的记录习惯和笔记内容的深度特征，生成一段流畅的个性化洞察。将数据特征转化为对用户性格和生活态度的理解，重点关注笔记内容中的独特元素，如地名与诗词的结合、文学作品引用、动漫文化、古典诗词等，将这些元素转化为富有情境感的表达。记住不要在输出中直接重复具体的数字。''';
  }

  /// 本地生成报告洞察（不开启AI时使用）。
  /// 会根据缺失项替换为中性描述，确保总长适中（约40-60字）。
  /// [languageCode] 用户设置的语言代码，如 'zh'、'en'，null 表示跟随系统（默认中文）
  String formatLocalReportInsight({
    required String periodLabel,
    String? mostTimePeriod,
    String? mostWeather,
    String? topTag,
    required int activeDays,
    required int noteCount,
    required int totalWordCount,
    String? languageCode, // 新增：语言代码
  }) {
    // 根据语言选择不同的模板
    final isEnglish = languageCode != null && languageCode.startsWith('en');

    final time =
        mostTimePeriod ?? (isEnglish ? 'evenly distributed' : '本期时段分布较均衡');
    final weather = mostWeather ??
        (isEnglish ? 'weather was not a significant factor' : '天气因素不明显');
    // 处理标签：清理前后空格和多余符号，直接使用标签名
    String tag;
    if (topTag != null && topTag.trim().isNotEmpty) {
      // 移除开头的#符号和多余空格
      final cleanTag = topTag.trim().replaceAll(RegExp(r'^#+\s*'), '').trim();
      tag = cleanTag.isNotEmpty
          ? '「$cleanTag」'
          : (isEnglish ? 'diverse topics' : '多元主题');
    } else {
      tag = isEnglish ? 'diverse topics' : '多元主题';
    }

    // 3种风格模板（除了简约数据型和极简禅意型），随机挑选
    final rng = math.Random();
    final styleIndex = rng.nextInt(3);

    if (isEnglish) {
      // 英文模板
      switch (styleIndex) {
        case 0:
          return _generateWarmCompanionInsightEn(
            periodLabel,
            time,
            weather,
            tag,
            activeDays,
            noteCount,
            totalWordCount,
          );
        case 1:
          return _generatePoeticInsightEn(
            periodLabel,
            time,
            weather,
            tag,
            activeDays,
            noteCount,
            totalWordCount,
          );
        case 2:
          return _generateGrowthMentorInsightEn(
            periodLabel,
            time,
            weather,
            tag,
            activeDays,
            noteCount,
            totalWordCount,
          );
        default:
          return _generateWarmCompanionInsightEn(
            periodLabel,
            time,
            weather,
            tag,
            activeDays,
            noteCount,
            totalWordCount,
          );
      }
    } else {
      // 中文模板
      switch (styleIndex) {
        case 0: // 温暖陪伴型
          return _generateWarmCompanionInsight(
            periodLabel,
            time,
            weather,
            tag,
            activeDays,
            noteCount,
            totalWordCount,
          );
        case 1: // 诗意文艺型
          return _generatePoeticInsight(
            periodLabel,
            time,
            weather,
            tag,
            activeDays,
            noteCount,
            totalWordCount,
          );
        case 2: // 成长导师型
          return _generateGrowthMentorInsight(
            periodLabel,
            time,
            weather,
            tag,
            activeDays,
            noteCount,
            totalWordCount,
          );
        default:
          return _generateWarmCompanionInsight(
            periodLabel,
            time,
            weather,
            tag,
            activeDays,
            noteCount,
            totalWordCount,
          );
      }
    }
  }

  /// 温暖陪伴型洞察
  String _generateWarmCompanionInsight(
    String periodLabel,
    String time,
    String weather,
    String tag,
    int activeDays,
    int noteCount,
    int totalWordCount,
  ) {
    final templates = [
      '$periodLabel你坚持记录了$activeDays天，写下$noteCount篇心情随笔。$time是你偏爱的书写时光，$weather相伴左右，$tag是你这段时间的关注焦点。',
      '过去$periodLabel，你用$activeDays天记录生活点滴，留下$totalWordCount字的温暖印记。$time最能激发你的表达欲，$tag贯穿其中。',
      '这$periodLabel你用心记录了$activeDays天，$noteCount篇文字承载着日常感悟。$time书写、$weather相伴，$tag是你的思绪主线。',
    ];
    final rng = math.Random();
    return templates[rng.nextInt(templates.length)];
  }

  /// 诗意文艺型洞察
  String _generatePoeticInsight(
    String periodLabel,
    String time,
    String weather,
    String tag,
    int activeDays,
    int noteCount,
    int totalWordCount,
  ) {
    final templates = [
      '时光缓缓流淌，你用$activeDays个日夜编织了$noteCount段故事。$time是灵感涌动的时刻，$weather为背景，$tag是这段旅程的注脚。',
      '$periodLabel悄然而过，你在$activeDays个清晨或黄昏落笔，$totalWordCount字凝结成记忆的琥珀。$time懂你，$tag是心底的回响。',
      '笔尖轻触纸面，$activeDays天里你写下$noteCount篇心语。$time静谧，$weather如常，$tag在字里行间若隐若现。',
    ];
    final rng = math.Random();
    return templates[rng.nextInt(templates.length)];
  }

  /// 成长导师型洞察
  String _generateGrowthMentorInsight(
    String periodLabel,
    String time,
    String weather,
    String tag,
    int activeDays,
    int noteCount,
    int totalWordCount,
  ) {
    final templates = [
      '$periodLabel你保持了$activeDays天的记录习惯，积累$totalWordCount字的思考沉淀。$time适合深度思考，$tag值得持续探索。',
      '这$periodLabel你坚持了$activeDays天，$noteCount篇记录见证着你的思维轨迹。$time是高效时段，$tag或许是下一个突破口。',
      '$activeDays天的坚持展现了你的自律，$noteCount篇笔记记录着成长。$time是你的黄金时段，$tag体现了近期关注点。',
    ];
    final rng = math.Random();
    return templates[rng.nextInt(templates.length)];
  }

  // ========================= 英文本地洞察模板 =========================

  /// Warm companion style insight (English)
  String _generateWarmCompanionInsightEn(
    String periodLabel,
    String time,
    String weather,
    String tag,
    int activeDays,
    int noteCount,
    int totalWordCount,
  ) {
    final templates = [
      'This $periodLabel, you journaled for $activeDays days, creating $noteCount entries. $time was your preferred writing time, with $weather in the background, and $tag emerged as your main focus.',
      'Over the past $periodLabel, you recorded $totalWordCount words across $activeDays days. $time sparked your creativity, and $tag wove through your reflections.',
      'You stayed consistent for $activeDays days this $periodLabel, writing $noteCount heartfelt entries. $time suited you best, and $tag captured your thoughts.',
    ];
    final rng = math.Random();
    return templates[rng.nextInt(templates.length)];
  }

  /// Poetic style insight (English)
  String _generatePoeticInsightEn(
    String periodLabel,
    String time,
    String weather,
    String tag,
    int activeDays,
    int noteCount,
    int totalWordCount,
  ) {
    final templates = [
      'Time drifted gently as you wove $noteCount stories across $activeDays days. $time held your inspiration, $weather set the scene, and $tag became your quiet refrain.',
      'This $periodLabel slipped by softly, and you penned $totalWordCount words in its wake. $time understood you best, with $tag echoing through the pages.',
      'Ink met paper on $activeDays occasions, yielding $noteCount reflections. $time was serene, $weather familiar, and $tag lingered between the lines.',
    ];
    final rng = math.Random();
    return templates[rng.nextInt(templates.length)];
  }

  /// Growth mentor style insight (English)
  String _generateGrowthMentorInsightEn(
    String periodLabel,
    String time,
    String weather,
    String tag,
    int activeDays,
    int noteCount,
    int totalWordCount,
  ) {
    final templates = [
      'This $periodLabel, you maintained a $activeDays-day journaling streak, accumulating $totalWordCount words of reflection. $time suits deep thinking, and $tag is worth exploring further.',
      'You stayed on track for $activeDays days, leaving $noteCount entries that map your thought process. $time was productive, and $tag may be your next breakthrough.',
      '$activeDays days of consistency show your discipline, with $noteCount notes tracking your growth. $time was your prime window, and $tag highlights your current focus.',
    ];
    final rng = math.Random();
    return templates[rng.nextInt(templates.length)];
  }
}
