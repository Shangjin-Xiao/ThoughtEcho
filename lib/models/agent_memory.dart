import 'dart:convert';

import 'package:flutter/foundation.dart';

/// 画像层条目的类别。
///
/// 准入标准是三条同时满足：**归纳成本高、结论稳定、复用频率高**。
/// 满足三条的东西值得缓存进画像，因为每次重新推导都很贵；不满足的应当
/// 现查——用户写过什么归 `explore_notes`，对话里说过什么归 `session_search`。
///
/// 边界是**存结论不存原文**：文风、品味这类结论要扫很多篇笔记才归纳得出，
/// 缓存下来才划算；笔记正文本身永远现查，不进记忆。
enum AgentMemoryKind {
  /// 身份、职业、长期在做的事。
  identity,

  /// 内容偏好：想聊什么、不想被提起什么。
  preference,

  /// 表达偏好：希望 Thoughter 怎么表达（篇幅、语气、格式）。
  style,

  /// 用户对 Thoughter 做法的纠正或确认。
  feedback,

  /// 摘录品味：用户常摘什么类型、题材、调性的内容。
  ///
  /// 和 [preference] 的区别是「爱读什么」而不是「想聊什么」；和 [voice] 的
  /// 区别见后者。**只可用于共鸣与推荐，不可用于评价**——这条约束靠注入层的
  /// kind 投影执行（见 `AgentMemoryService.profileKindsForGeneration`），
  /// 不是只写在提示词里。
  taste,

  /// 用户自己的写作声音：篇幅、句式、人称、收尾方式。
  ///
  /// 必须和 [taste] 分开。一个人爱摘的和自己写的常常不是一回事（爱摘凝练的
  /// 古文、自己写口语化的碎句是很正常的组合），混成一类会让代笔时照着他
  /// **摘的**去写，产出完全不像他本人。
  voice,
}

extension AgentMemoryKindStorage on AgentMemoryKind {
  String get storageValue => name;

  static AgentMemoryKind fromStorage(String? value) {
    for (final kind in AgentMemoryKind.values) {
      if (kind.name == value) {
        return kind;
      }
    }
    return AgentMemoryKind.preference;
  }
}

/// 画像层条目的生命周期状态。
///
/// 偏好变化时**原位 supersede**，不追加一条矛盾的 active 条目——两条互相打架的
/// 指令会让模型随机挑一条遵守。
enum AgentMemoryStatus { active, superseded }

extension AgentMemoryStatusStorage on AgentMemoryStatus {
  String get storageValue => name;

  static AgentMemoryStatus fromStorage(String? value) {
    return value == AgentMemoryStatus.superseded.name
        ? AgentMemoryStatus.superseded
        : AgentMemoryStatus.active;
  }
}

/// 画像层条目：每次对话都会注入，因此有硬预算。
///
/// [directive] 写成指令而不是观察（"回复保持碎句" 而不是 "用户喜欢碎句"）——
/// 长对话里观察句的遵循度会显著下降，指令句不会。
@immutable
class AgentMemoryProfileEntry {
  const AgentMemoryProfileEntry({
    required this.id,
    required this.kind,
    required this.directive,
    required this.observedAt,
    this.status = AgentMemoryStatus.active,
    this.supersededBy,
    this.source,
    this.sourceNoteIds = const <String>[],
  });

  final String id;
  final AgentMemoryKind kind;
  final String directive;
  final DateTime observedAt;
  final AgentMemoryStatus status;

  /// 取代本条的新条目 id；仅当 [status] 为 superseded 时有值。
  final String? supersededBy;

  /// 记录来源，例如 `thoughter` / `user_edit`。仅用于排查，不注入模型。
  final String? source;

  /// 归纳出这条画像所依据的笔记 id。
  ///
  /// 只有 Dreaming 的后台归纳会填：用户能在记忆管理里看到"这条是根据哪几篇
  /// 笔记得出的"，才有可能判断它是不是瞎猜。`remember` 手动写入的条目留空——
  /// 手动记下的东西本就没有笔记来源，硬造一个是假归因。
  ///
  /// 同样不注入模型：它是给用户看的证据，不是给模型的上下文。
  final List<String> sourceNoteIds;

  bool get isActive => status == AgentMemoryStatus.active;

  AgentMemoryProfileEntry copyWith({
    String? id,
    AgentMemoryKind? kind,
    String? directive,
    DateTime? observedAt,
    AgentMemoryStatus? status,
    String? supersededBy,
    String? source,
    List<String>? sourceNoteIds,
  }) {
    return AgentMemoryProfileEntry(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      directive: directive ?? this.directive,
      observedAt: observedAt ?? this.observedAt,
      status: status ?? this.status,
      supersededBy: supersededBy ?? this.supersededBy,
      source: source ?? this.source,
      sourceNoteIds: sourceNoteIds ?? this.sourceNoteIds,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'kind': kind.storageValue,
      'directive': directive,
      'observed_at': observedAt.toIso8601String(),
      'status': status.storageValue,
      'superseded_by': supersededBy,
      'source': source,
      // 空列表存 NULL 而不是 '[]'：一期的旧行、以及 remember 手动写入的条目
      // 都是 NULL，两者语义同为"无来源"，别让存储层出现两种空。
      'source_note_ids':
          sourceNoteIds.isEmpty ? null : jsonEncode(sourceNoteIds),
    };
  }

  static AgentMemoryProfileEntry fromMap(Map<String, Object?> map) {
    return AgentMemoryProfileEntry(
      id: map['id'] as String,
      kind: AgentMemoryKindStorage.fromStorage(map['kind'] as String?),
      directive: (map['directive'] as String?) ?? '',
      // 时间戳解析不出来就回退到最早：既然只能猜，宁可让坏行排在最后被淘汰，
      // 也不要让它伪装成"刚刚观察到"、抢占每轮注入的名额。
      observedAt: DateTime.tryParse((map['observed_at'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      status: AgentMemoryStatusStorage.fromStorage(map['status'] as String?),
      supersededBy: map['superseded_by'] as String?,
      source: map['source'] as String?,
      sourceNoteIds: _decodeNoteIds(map['source_note_ids']),
    );
  }
}

/// 解析 `source_note_ids` 列。
///
/// 一期的旧行没有这一列（值为 NULL），解析失败也按无来源处理：归因信息缺失
/// 只是少展示一行证据，不该让整条记忆读不出来。
List<String> _decodeNoteIds(Object? raw) {
  if (raw is! String || raw.isEmpty) return const <String>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <String>[];
    return decoded
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  } catch (_) {
    return const <String>[];
  }
}

/// 事实层条目：不默认注入，由 `recall` 工具按需检索。
///
/// [embedding] 目前恒为 null，为将来换向量检索预留列位，避免二期再写一次迁移。
@immutable
class AgentMemoryFact {
  const AgentMemoryFact({
    required this.id,
    required this.content,
    required this.createdAt,
    this.category,
    this.importance = 5,
    this.triggerPhrases = const <String>[],
    this.lastRecalledAt,
    this.recallCount = 0,
    this.sourceRef,
  });

  static const int minImportance = 1;
  static const int maxImportance = 10;

  final String id;
  final String content;
  final DateTime createdAt;
  final String? category;

  /// 1-10，写入时由模型标注，参与检索排序。
  final int importance;

  /// 额外的检索关键词。内容本身没出现、但用户可能用来提问的说法写在这里。
  final List<String> triggerPhrases;

  final DateTime? lastRecalledAt;
  final int recallCount;
  final String? sourceRef;

  AgentMemoryFact copyWith({
    String? id,
    String? content,
    DateTime? createdAt,
    String? category,
    int? importance,
    List<String>? triggerPhrases,
    DateTime? lastRecalledAt,
    int? recallCount,
    String? sourceRef,
  }) {
    return AgentMemoryFact(
      id: id ?? this.id,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      category: category ?? this.category,
      importance: importance ?? this.importance,
      triggerPhrases: triggerPhrases ?? this.triggerPhrases,
      lastRecalledAt: lastRecalledAt ?? this.lastRecalledAt,
      recallCount: recallCount ?? this.recallCount,
      sourceRef: sourceRef ?? this.sourceRef,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'category': category,
      'content': content,
      'importance': importance,
      'trigger_phrases':
          triggerPhrases.isEmpty ? null : triggerPhrases.join('\n'),
      'created_at': createdAt.toIso8601String(),
      'last_recalled_at': lastRecalledAt?.toIso8601String(),
      'recall_count': recallCount,
      'source_ref': sourceRef,
    };
  }

  static AgentMemoryFact fromMap(Map<String, Object?> map) {
    final rawPhrases = (map['trigger_phrases'] as String?) ?? '';
    return AgentMemoryFact(
      id: map['id'] as String,
      content: (map['content'] as String?) ?? '',
      // 同 [AgentMemoryProfileEntry.fromMap]：坏时间戳排最后，不排最前。
      createdAt: DateTime.tryParse((map['created_at'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      category: map['category'] as String?,
      importance: (map['importance'] as int?) ?? 5,
      triggerPhrases: rawPhrases.isEmpty
          ? const <String>[]
          : rawPhrases
              .split('\n')
              .map((phrase) => phrase.trim())
              .where((phrase) => phrase.isNotEmpty)
              .toList(growable: false),
      lastRecalledAt: DateTime.tryParse(
        (map['last_recalled_at'] as String?) ?? '',
      ),
      recallCount: (map['recall_count'] as int?) ?? 0,
      sourceRef: map['source_ref'] as String?,
    );
  }
}

/// 一条事实的检索结果，附带排序得分供调试与截断决策。
@immutable
class AgentMemoryFactHit {
  const AgentMemoryFactHit({required this.fact, required this.score});

  final AgentMemoryFact fact;
  final double score;
}

/// 近况切片：最近在做什么、去过哪里、反复提到什么。
///
/// **刻意不做成画像层条目。** 画像层装的是"数月尺度上不变"的结论，而近况必然
/// 过期；把会过期的内容放进常驻注入，两周后每日提示还在说"你最近在准备考试"，
/// 而考试早考完了，且没有任何机制会去撤掉它。所以单独存、带 [expiresAt]，
/// 过期即不注入，不需要额外的清理任务。
///
/// 全库只有一条，Dreaming 每次覆盖式重写，不追加。
@immutable
class AgentMemoryRecentSlice {
  const AgentMemoryRecentSlice({
    required this.content,
    required this.observedAt,
    required this.expiresAt,
    this.sourceNoteIds = const <String>[],
  });

  /// 单行表的固定主键。近况只有"当前这一份"，用固定 id 让写入天然是覆盖。
  static const String singletonId = 'current';

  /// 内容长度上限。它只是每日提示里的一两句背景，不是周报。
  static const int maxChars = 200;

  /// 默认有效期。
  ///
  /// 周报周期是 7 天，14 天能跨过一个"这周没写"的空窗，又不至于陈旧到出错。
  /// 初值，需要按实际数据校准。
  static const Duration defaultTtl = Duration(days: 14);

  final String content;
  final DateTime observedAt;
  final DateTime expiresAt;
  final List<String> sourceNoteIds;

  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': singletonId,
      'content': content,
      'observed_at': observedAt.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
      'source_note_ids':
          sourceNoteIds.isEmpty ? null : jsonEncode(sourceNoteIds),
    };
  }

  static AgentMemoryRecentSlice fromMap(Map<String, Object?> map) {
    // 时间戳坏掉时按「已过期」处理（observedAt 取纪元、expiresAt 同）：
    // 近况读不准就不要注入，宁可少说一句，也不要拿一段来历不明的描述
    // 去跟用户讲他最近在干什么。
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    return AgentMemoryRecentSlice(
      content: (map['content'] as String?) ?? '',
      observedAt:
          DateTime.tryParse((map['observed_at'] as String?) ?? '') ?? epoch,
      expiresAt:
          DateTime.tryParse((map['expires_at'] as String?) ?? '') ?? epoch,
      sourceNoteIds: _decodeNoteIds(map['source_note_ids']),
    );
  }
}
