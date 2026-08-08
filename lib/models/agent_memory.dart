import 'package:flutter/foundation.dart';

/// 画像层条目的类别。
///
/// 只覆盖「从笔记内容里推导不出来」的信息：用户是谁、希望 Thoughter 怎么表达、
/// 以及用户对 Thoughter 做法的纠正。写作素材本身归 `explore_notes` 检索，
/// 不进记忆。
enum AgentMemoryKind {
  /// 身份、职业、长期在做的事。
  identity,

  /// 内容偏好：想聊什么、不想被提起什么。
  preference,

  /// 表达偏好：篇幅、语气、格式。
  style,

  /// 用户对 Thoughter 做法的纠正或确认。
  feedback,
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

  bool get isActive => status == AgentMemoryStatus.active;

  AgentMemoryProfileEntry copyWith({
    String? id,
    AgentMemoryKind? kind,
    String? directive,
    DateTime? observedAt,
    AgentMemoryStatus? status,
    String? supersededBy,
    String? source,
  }) {
    return AgentMemoryProfileEntry(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      directive: directive ?? this.directive,
      observedAt: observedAt ?? this.observedAt,
      status: status ?? this.status,
      supersededBy: supersededBy ?? this.supersededBy,
      source: source ?? this.source,
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
    };
  }

  static AgentMemoryProfileEntry fromMap(Map<String, Object?> map) {
    return AgentMemoryProfileEntry(
      id: map['id'] as String,
      kind: AgentMemoryKindStorage.fromStorage(map['kind'] as String?),
      directive: (map['directive'] as String?) ?? '',
      observedAt: DateTime.tryParse((map['observed_at'] as String?) ?? '') ??
          DateTime.now(),
      status: AgentMemoryStatusStorage.fromStorage(map['status'] as String?),
      supersededBy: map['superseded_by'] as String?,
      source: map['source'] as String?,
    );
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
      createdAt: DateTime.tryParse((map['created_at'] as String?) ?? '') ??
          DateTime.now(),
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
