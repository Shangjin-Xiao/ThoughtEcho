import 'dart:convert';

import '../utils/quill_delta_builder.dart';

class Quote {
  static const Object _noValue = Object();

  final String? id;
  final String content;
  final String date;
  final String? aiAnalysis;
  final String? _source;
  final String? sourceAuthor;
  final String? sourceWork;
  final List<String> tagIds;
  final String? sentiment;
  final List<String>? keywords;
  final String? summary;
  final String? categoryId;
  final String? colorHex;
  final String? location;
  final double? latitude; // 位置纬度，支持离线存储
  final double? longitude; // 位置经度，支持离线存储
  final String? poiName; // 用户选择的精确地点名称（如"故宫博物院"）
  final String? weather;
  final String? temperature;
  final String? editSource; // "fullscreen" 或 null
  final String? deltaContent; // 新增：用于存储富文本格式(Delta JSON)
  final String? dayPeriod; // 新增：时间段标识(晨曦、午后、黄昏、夜晚等)
  final String? lastModified;
  final int favoriteCount; // 新增：心形点击次数
  final bool isDeleted; // 回收站标记
  final String? deletedAt; // 删除时间（ISO 8601）

  Quote({
    this.id,
    required this.content,
    required this.date,
    String? source, // 保持构造函数参数名兼容
    this.sourceAuthor,
    this.sourceWork,
    this.tagIds = const [],
    this.aiAnalysis,
    this.sentiment,
    this.keywords,
    this.summary,
    this.categoryId,
    this.colorHex,
    this.location,
    this.latitude,
    this.longitude,
    this.poiName,
    this.weather,
    this.temperature,
    this.editSource,
    this.deltaContent, // 新增：Delta JSON
    this.dayPeriod, // 新增：时间段
    this.lastModified,
    this.favoriteCount = 0, // 新增：心形点击次数，默认为0
    this.isDeleted = false,
    String? deletedAt,
  })  : _source = source,
        deletedAt = isDeleted ? _normalizeToUtc(deletedAt) : null;

  /// 获取来源信息 (兼容性 getter)
  /// 如果 sourceAuthor 和 sourceWork 存在，则优先从它们重建
  String? get source {
    if (sourceAuthor != null &&
        sourceWork != null &&
        sourceAuthor!.isNotEmpty &&
        sourceWork!.isNotEmpty) {
      return '$sourceAuthor - $sourceWork';
    } else if (sourceAuthor != null && sourceAuthor!.isNotEmpty) {
      return sourceAuthor;
    } else if (sourceWork != null && sourceWork!.isNotEmpty) {
      return sourceWork;
    }
    return _source;
  }

  /// 修复：添加数据验证方法
  static bool isValidDate(String date) {
    try {
      DateTime.parse(date);
      return true;
    } catch (e) {
      return false;
    }
  }

  static bool isValidColorHex(String? colorHex) {
    if (colorHex == null) return true;
    final regex = RegExp(r'^#[0-9A-Fa-f]{6}$');
    return regex.hasMatch(colorHex);
  }

  /// 新建笔记时的内容长度上限。
  ///
  /// 这是**输入层**的策略（非全屏对话框的 `maxLength` 用的是同一个数），不是持久化
  /// 不变量：`content` 列是 TEXT 没有长度限制，全屏 Quill 编辑器也不限字数。所以
  /// [validationError] 不查这一条——把已经写好、已经在库里的内容卡在保存这一步，
  /// 丢的是用户的字。
  static const int maxContentLengthForInput = 10000;

  static bool isValidContent(String content) {
    return content.isNotEmpty && content.length <= maxContentLengthForInput;
  }

  /// 把任意来源的情感值收敛成 [sentimentKeyToLabel] 的键，认不出来的返回 null。
  ///
  /// **只在导入边界使用**（[Quote.fromJson] 故意不调用它）：读的时候悄悄洗，库里那
  /// 颗雷就永远藏着，谁也不知道自己存着一条存不回去的笔记。洗要洗在数据进门的
  /// 那一次，而且要有人数得清洗了多少条。
  ///
  /// 应用自身一处都不写 `sentiment`，所以越界值只可能来自外部数据（手写备份 JSON、
  /// 第三方导出、更新版本的对端设备）。原样入库的后果是这条笔记再也保存不了：
  /// [fromJson] 放行读，[validationError] 拦住写。
  static String? normalizeSentiment(Object? raw) {
    if (raw == null) return null;
    final text = raw.toString().trim();
    if (text.isEmpty) return null;
    final key = text.toLowerCase();
    if (sentimentKeyToLabel.containsKey(key)) return key;
    // 也认中文标签：weather / day_period 都有过「存的是展示文案而不是 key」的历史
    // 数据（见 schema_repair_adapter 的两个 migrate*ToKey），这里照同样的规矩收。
    for (final entry in sentimentKeyToLabel.entries) {
      if (entry.value == text) return entry.key;
    }
    return null;
  }

  /// 修复：创建验证过的Quote实例
  factory Quote.validated({
    String? id,
    required String content,
    required String date,
    String? source,
    String? sourceAuthor,
    String? sourceWork,
    List<String> tagIds = const [],
    String? aiAnalysis,
    String? sentiment,
    List<String>? keywords,
    String? summary,
    String? categoryId,
    String? colorHex,
    String? location,
    double? latitude,
    double? longitude,
    String? poiName,
    String? weather,
    String? temperature,
    String? editSource,
    String? deltaContent,
    String? dayPeriod,
    int favoriteCount = 0, // 新增：心形点击次数，默认为0
    bool isDeleted = false,
    String? deletedAt,
  }) {
    // 验证必填字段
    if (!isValidContent(content)) {
      throw ArgumentError('笔记内容无效：内容不能为空且不能超过10000字符');
    }

    if (!isValidDate(date)) {
      throw ArgumentError('日期格式无效：$date');
    }

    if (!isValidColorHex(colorHex)) {
      throw ArgumentError('颜色格式无效：$colorHex，应为#RRGGBB格式');
    }

    // 验证情感分析值
    if (sentiment != null && !sentimentKeyToLabel.containsKey(sentiment)) {
      throw ArgumentError('情感分析值无效：$sentiment');
    }

    return Quote(
      id: id,
      content: content.trim(),
      date: date,
      source: source?.trim(),
      sourceAuthor: sourceAuthor?.trim(),
      sourceWork: sourceWork?.trim(),
      tagIds: tagIds,
      aiAnalysis: aiAnalysis?.trim(),
      sentiment: sentiment,
      keywords: keywords,
      summary: summary?.trim(),
      categoryId: categoryId,
      colorHex: colorHex,
      location: location?.trim(),
      latitude: latitude,
      longitude: longitude,
      poiName: poiName?.trim(),
      weather: weather?.trim(),
      temperature: temperature?.trim(),
      editSource: editSource,
      deltaContent: deltaContent,
      dayPeriod: dayPeriod,
      favoriteCount: favoriteCount, // 新增：心形点击次数
      isDeleted: isDeleted,
      deletedAt: deletedAt,
    );
  }

  /// 修复：从JSON构建Quote对象，增加数据验证和错误处理
  factory Quote.fromJson(Map<String, dynamic> json) {
    try {
      // 解析tagIds（确保它们是字符串列表）
      List<String> parseTagIds() {
        if (json['tag_ids'] == null) return [];
        if (json['tag_ids'] is String) {
          final tagString = json['tag_ids'] as String;
          if (tagString.isEmpty) return [];
          return tagString
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
        if (json['tag_ids'] is List) {
          return (json['tag_ids'] as List)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
        return [];
      }

      // 解析keywords（确保它们是字符串列表）
      List<String>? parseKeywords() {
        if (json['keywords'] == null) return null;
        if (json['keywords'] is String) {
          final keywordString = json['keywords'] as String;
          if (keywordString.isEmpty) return null;
          return keywordString
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
        if (json['keywords'] is List) {
          final keywords = (json['keywords'] as List)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
          return keywords.isEmpty ? null : keywords;
        }
        return null;
      }

      // 验证必填字段
      final content = json['content']?.toString() ?? '';
      final date = json['date']?.toString() ?? '';

      if (content.isEmpty) {
        throw ArgumentError('笔记内容不能为空');
      }

      if (date.isEmpty) {
        throw ArgumentError('日期不能为空');
      }

      // 验证日期格式
      if (!isValidDate(date)) {
        throw ArgumentError('日期格式无效: $date');
      }

      // 验证颜色格式
      final colorHex = json['color_hex']?.toString();
      if (colorHex != null && !isValidColorHex(colorHex)) {
        throw ArgumentError('颜色格式无效: $colorHex');
      }

      return Quote(
        // 构造函数会做 isDeleted/deletedAt 一致性归一化
        id: json['id']?.toString(),
        content: content,
        date: date,
        aiAnalysis: json['ai_analysis']?.toString(),
        source: json['source']?.toString(),
        sourceAuthor: json['source_author']?.toString(),
        sourceWork: json['source_work']?.toString(),
        tagIds: parseTagIds(),
        sentiment: json['sentiment']?.toString(),
        keywords: parseKeywords(),
        summary: json['summary']?.toString(),
        categoryId: json['category_id']?.toString(),
        colorHex: colorHex,
        location: json['location']?.toString(),
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        poiName: json['poi_name']?.toString(),
        weather: json['weather']?.toString(),
        temperature: json['temperature']?.toString(),
        editSource: json['edit_source']?.toString(),
        deltaContent: json['delta_content']?.toString(),
        dayPeriod: json['day_period']?.toString(),
        lastModified: json['last_modified']?.toString(),
        favoriteCount:
            (json['favorite_count'] as num?)?.toInt() ?? 0, // 新增：心形点击次数
        isDeleted: _parseDeletedFlag(json['is_deleted']),
        deletedAt: _normalizeDeletedAtForState(
          isDeleted: _parseDeletedFlag(json['is_deleted']),
          deletedAt: json['deleted_at']?.toString(),
        ),
      );
    } on ArgumentError {
      rethrow;
    } catch (e) {
      // 这里绝不能把 $json 或 $e 字符串拼进异常信息：$json 含 content 与
      // delta_content（用户笔记正文与富文本），而 $e 字符串可能携带非法字段值；
      // 调用方普遍把异常直接喂给日志服务，会把笔记明文落进本地日志文件。
      // 只暴露异常类型、定位所需的 id 与字段名。
      throw FormatException(
        '解析Quote JSON失败: ${e.runtimeType}, id: ${json['id']}, '
        'fields: ${json.keys.join(',')}',
      );
    }
  }

  // 将Quote对象转换为JSON
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {
      'id': id,
      'content': content,
      'date': date,
      'ai_analysis': aiAnalysis,
      'source': source,
      'source_author': sourceAuthor,
      'source_work': sourceWork,
      // 'tag_ids' 不再直接保存到此表中，它将通过关联表进行管理
      'sentiment': sentiment,
      'keywords': keywords?.join(','),
      'summary': summary,
      'category_id': categoryId,
      'color_hex': colorHex,
      'location': location,
      'latitude': latitude,
      'longitude': longitude,
      'poi_name': poiName,
      'weather': weather,
      'temperature': temperature,
      'edit_source': editSource,
      'delta_content': deltaContent, // 新增：Delta JSON
      'day_period': dayPeriod, // 新增：时间段
      'last_modified': lastModified,
      'favorite_count': favoriteCount, // 新增：心形点击次数
      'is_deleted': isDeleted ? 1 : 0,
      'deleted_at': isDeleted ? deletedAt : null,
    };
    // 移除tag_ids字段，因为它不再直接存储在quotes表中
    json.remove('tag_ids');
    return json;
  }

  // 复制并修改当前Quote对象
  Quote copyWith({
    String? id,
    String? content,
    String? date,
    String? aiAnalysis,
    Object? source = _noValue,
    Object? sourceAuthor = _noValue,
    Object? sourceWork = _noValue,
    List<String>? tagIds,
    String? sentiment,
    List<String>? keywords,
    String? summary,
    String? categoryId,
    String? colorHex,
    Object? location = _noValue,
    Object? latitude = _noValue,
    Object? longitude = _noValue,
    Object? poiName = _noValue,
    Object? weather = _noValue,
    Object? temperature = _noValue,
    Object? editSource = _noValue,
    Object? deltaContent = _noValue, // 新增：Delta JSON
    String? dayPeriod, // 新增：时间段
    String? lastModified,
    int? favoriteCount, // 新增：心形点击次数
    Object? isDeleted = _noValue,
    Object? deletedAt = _noValue,
  }) {
    final nextIsDeleted = identical(isDeleted, _noValue)
        ? this.isDeleted
        : (isDeleted is bool ? isDeleted : this.isDeleted);
    final nextDeletedAt = identical(deletedAt, _noValue)
        ? this.deletedAt
        : (deletedAt is String? ? deletedAt : this.deletedAt);

    return Quote(
      id: id ?? this.id,
      content: content ?? this.content,
      date: date ?? this.date,
      aiAnalysis: aiAnalysis ?? this.aiAnalysis,
      source: identical(source, _noValue) ? this.source : source as String?,
      sourceAuthor: identical(sourceAuthor, _noValue)
          ? this.sourceAuthor
          : sourceAuthor as String?,
      sourceWork: identical(sourceWork, _noValue)
          ? this.sourceWork
          : sourceWork as String?,
      tagIds: tagIds ?? this.tagIds,
      sentiment: sentiment ?? this.sentiment,
      keywords: keywords ?? this.keywords,
      summary: summary ?? this.summary,
      categoryId: categoryId ?? this.categoryId,
      colorHex: colorHex ?? this.colorHex,
      location:
          identical(location, _noValue) ? this.location : location as String?,
      latitude:
          identical(latitude, _noValue) ? this.latitude : latitude as double?,
      longitude: identical(longitude, _noValue)
          ? this.longitude
          : longitude as double?,
      poiName: identical(poiName, _noValue) ? this.poiName : poiName as String?,
      weather: identical(weather, _noValue) ? this.weather : weather as String?,
      temperature: identical(temperature, _noValue)
          ? this.temperature
          : temperature as String?,
      editSource: identical(editSource, _noValue)
          ? this.editSource
          : editSource as String?,
      deltaContent: identical(deltaContent, _noValue)
          ? this.deltaContent
          : deltaContent as String?, // 新增：Delta JSON
      dayPeriod: dayPeriod ?? this.dayPeriod, // 新增：时间段
      lastModified: lastModified ?? this.lastModified,
      favoriteCount: favoriteCount ?? this.favoriteCount, // 新增：心形点击次数
      isDeleted: nextIsDeleted,
      deletedAt: _normalizeDeletedAtForState(
        isDeleted: nextIsDeleted,
        deletedAt: nextDeletedAt,
      ),
    );
  }

  static bool _parseDeletedFlag(dynamic raw) {
    if (raw == null) return false;
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    final text = raw.toString().trim().toLowerCase();
    return text == '1' || text == 'true';
  }

  /// 将 deletedAt 归一化到 UTC，缺失时生成当前 UTC 时间
  static String _normalizeToUtc(String? deletedAt) {
    final trimmed = deletedAt?.trim();
    if (trimmed != null && trimmed.isNotEmpty && isValidDate(trimmed)) {
      // 若已是 UTC 格式（以 Z 结尾），直接保留原字符串，避免
      // DateTime.toIso8601String() 强制补出毫秒导致与测试预期不符。
      if (trimmed.endsWith('Z')) {
        return trimmed;
      }
      return DateTime.parse(trimmed).toUtc().toIso8601String();
    }
    return DateTime.now().toUtc().toIso8601String();
  }

  static String? _normalizeDeletedAtForState({
    required bool isDeleted,
    required String? deletedAt,
  }) {
    if (!isDeleted) {
      return null;
    }

    final trimmed = deletedAt?.trim();
    if (trimmed != null && trimmed.isNotEmpty && isValidDate(trimmed)) {
      // 若已是 UTC 格式（以 Z 结尾），直接保留原字符串，避免
      // DateTime.toIso8601String() 强制补出毫秒导致与测试预期不符。
      if (trimmed.endsWith('Z')) {
        return trimmed;
      }
      return DateTime.parse(trimmed).toUtc().toIso8601String();
    }
    // 缺失时生成当前 UTC 时间，而非回退到 quote.date
    return DateTime.now().toUtc().toIso8601String();
  }

  // 静态key-label映射
  static const Map<String, String> sentimentKeyToLabel = {
    'positive': '积极',
    'negative': '消极',
    'neutral': '中性',
    'mixed': '复杂',
  };
  static const Map<String, String> sourceTypeKeyToLabel = {
    'manual': '手动',
    'ai': 'AI生成',
    'import': '导入',
  };

  /// 修复：添加工具方法
  bool get hasPoiName => poiName != null && poiName!.isNotEmpty;
  bool get hasLocation =>
      (location != null && location!.isNotEmpty) || hasCoordinates;
  bool get hasDisplayLocation =>
      hasPoiName || (location != null && location!.isNotEmpty);
  bool get hasCoordinates => latitude != null && longitude != null;
  bool get hasWeather => weather != null && weather!.isNotEmpty;
  bool get hasAiAnalysis => aiAnalysis != null && aiAnalysis!.isNotEmpty;
  bool get hasTags => tagIds.isNotEmpty;
  bool get hasKeywords => keywords != null && keywords!.isNotEmpty;

  /// 这条笔记带没带归属标注（作者 / 出处 / 旧数据里未拆分的来源串）。
  bool get hasAttribution =>
      (sourceAuthor?.trim().isNotEmpty ?? false) ||
      (sourceWork?.trim().isNotEmpty ?? false) ||
      (_source?.trim().isNotEmpty ?? false);

  /// 喂给模型时用的归属类型：`excerpt`（摘录）/ `original`（用户原创）。
  ///
  /// 模型反复把摘录当成用户的自白——「我看到了这段文字，却在分析时把它当成了
  /// 你的自白」是它自己的原话。根因是它只拿到 author / source 两个字段，
  /// 得自己推断这条是谁写的，而推断在长上下文里第一个失效。这里替它把结论
  /// 算好：有归属标注就是摘录。
  ///
  /// 判断依据只有标注，所以不是绝对的——用户也可能给自己的原创署名。那种
  /// 情况由提示词里的例外条款兜底（署的是用户自己的称呼时按原创对待），
  /// 而不是在这里猜。
  String get attributionKind => hasAttribution ? 'excerpt' : 'original';

  /// 获取情感分析的中文标签
  String? get sentimentLabel =>
      sentiment != null ? sentimentKeyToLabel[sentiment] : null;

  /// 获取完整的来源信息
  String get fullSource {
    final s = source;
    if (s != null && s.isNotEmpty) return s;
    return '未知来源';
  }

  /// 安全解析 deltaContent JSON，防止由于无效/损坏的 JSON 导致异常或编辑器崩溃。
  /// 如果 deltaContent 为空、格式非法或包含无效 JSON，则降级返回基于 [content] 的合法 Delta ops。
  List<Map<String, dynamic>> get safeDeltaOps {
    if (deltaContent == null || deltaContent!.trim().isEmpty) {
      return DeltaBuilder.textToDelta(content);
    }
    try {
      final decoded = jsonDecode(deltaContent!);
      List<dynamic>? opsList;
      if (decoded is List) {
        opsList = decoded;
      } else if (decoded is Map && decoded['ops'] is List) {
        opsList = decoded['ops'] as List;
      }
      if (opsList != null) {
        final result = <Map<String, dynamic>>[];
        for (final item in opsList) {
          if (item is Map) {
            result.add(
              item.map(
                (k, v) => MapEntry(k.toString(), v),
              ),
            );
          }
        }
        if (result.isNotEmpty) return result;
      }
    } catch (_) {
      // 降级处理
    }
    return DeltaBuilder.textToDelta(content);
  }

  /// 获取经过校验的安全 Delta JSON 字符串。若原字符串损坏，返回由 content 生成的标准 Delta JSON 字符串。
  String get safeDeltaContent {
    return DeltaBuilder.deltaToJson(safeDeltaOps);
  }

  /// 这条笔记为什么不能持久化；没问题时返回 null。
  ///
  /// 存在的理由是**报错要指名道姓**：原来写库失败只抛一句「请检查内容、日期和其他
  /// 字段」，而真凶往往是没被提到的第四个字段（导入进来的越界 `sentiment`），
  /// 用户和日志都看不出该修哪里。
  ///
  /// 判据要和 [fromJson] 对齐：**读得出来的行必须写得回去**。两边尺子不一样的那道
  /// 缝里，笔记会变成只能看、不能改的砖。所以这里不查内容长度上限——那是输入层的
  /// 策略（见 [maxContentLengthForInput]），`fromJson` 也不查它。
  String? get validationError {
    if (content.isEmpty) return '笔记内容不能为空';
    if (!isValidDate(date)) return '日期格式无效：$date';
    if (!isValidColorHex(colorHex)) {
      return '颜色格式无效：$colorHex，应为 #RRGGBB 格式';
    }
    final s = sentiment;
    if (s != null && !sentimentKeyToLabel.containsKey(s)) {
      return '情感分析值无效：$s，应为 ${sentimentKeyToLabel.keys.join(' / ')} 之一';
    }
    return null;
  }

  /// 验证Quote对象的完整性
  bool get isValid => validationError == null;

  /// 这一行的**内容**是否和 [other] 完全一致。
  ///
  /// [operator ==] 只比 `id`（笔记的身份），回答不了「这一行变了没有」。列表侧
  /// 需要后者：数据库每次重新查询都会造一批全新的 [Quote] 对象，内容一个字没改
  /// 身份却全变了，按 `identical` 判断的卡片记忆化于是整屏失效。
  ///
  /// 判据是「持久化的全部字段」：[toJson] 覆盖 quotes 表那一行，[tagIds] 补上走
  /// 关联表、因而不在 [toJson] 里的标签。新增持久化字段时本来就要同步 [toJson]
  /// （见 AGENTS.md），这里跟着自动生效 —— 不再单列一份会漏掉新字段的清单。
  bool hasSameContentAs(Quote other) {
    if (identical(this, other)) return true;
    if (other.id != id) return false;
    if (other.tagIds.length != tagIds.length) return false;
    for (var i = 0; i < tagIds.length; i++) {
      if (other.tagIds[i] != tagIds[i]) return false;
    }
    final mine = toJson();
    final theirs = other.toJson();
    if (mine.length != theirs.length) return false;
    for (final entry in mine.entries) {
      if (theirs[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Quote && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Quote(id: $id, content: ${content.length > 50 ? '${content.substring(0, 50)}...' : content}, date: $date)';
  }
}

// 移除了冗余的QuoteModel类，该类在项目中未被使用
// 如果将来需要类似功能，可以直接在Quote类中添加相应方法
