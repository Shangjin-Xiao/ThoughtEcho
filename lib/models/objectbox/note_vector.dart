import 'package:objectbox/objectbox.dart';

// =============================================================================
// 嵌入向量维度配置
// 
// 当前配置为 paraphrase-multilingual-MiniLM-L12-v2 模型 (384 维)
// 如果切换到其他模型，需要:
// 1. 修改下面的 embeddingDimension 常量
// 2. 修改 NoteVector.embedding 的 @HnswIndex(dimensions: xxx) 注解
// 3. 重新运行 dart run build_runner build
// 4. 清除旧的向量数据（维度不同无法兼容）
// =============================================================================
const int embeddingDimension = 384;

/// 笔记向量实体
/// 
/// 用于存储笔记的嵌入向量，支持 HNSW 向量搜索
/// 
/// **维度配置**: 当前为 384 维 (paraphrase-multilingual-MiniLM-L12-v2)
/// 如需支持其他维度，请参考文件顶部的配置说明
@Entity()
class NoteVector {
  @Id()
  int id = 0;

  /// 关联的笔记 ID
  @Unique()
  @Index()
  String noteId;

  /// 嵌入向量
  /// 
  /// 维度由 embeddingDimension 常量定义，当前为 384
  /// 注意: @HnswIndex 的 dimensions 参数必须与实际向量维度匹配
  @HnswIndex(dimensions: 384) // 对应 embeddingDimension
  @Property(type: PropertyType.floatVector)
  List<double> embedding;

  /// 笔记内容摘要 (用于快速预览，最多 200 字符)
  String? contentPreview;

  /// 创建时间
  @Property(type: PropertyType.date)
  DateTime createdAt;

  /// 更新时间
  @Property(type: PropertyType.date)
  DateTime updatedAt;

  /// 嵌入模型版本 (用于模型升级时重新计算向量)
  String modelVersion;

  /// 嵌入向量维度 (用于验证)
  int dimension;

  NoteVector({
    this.id = 0,
    required this.noteId,
    required this.embedding,
    this.contentPreview,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.modelVersion = '1.0.0',
    this.dimension = embeddingDimension,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// 更新嵌入向量
  void updateEmbedding(List<double> newEmbedding, String newModelVersion) {
    if (newEmbedding.length != dimension) {
      throw ArgumentError(
        '嵌入向量维度不匹配: 预期 $dimension, 实际 ${newEmbedding.length}',
      );
    }
    embedding = newEmbedding;
    modelVersion = newModelVersion;
    updatedAt = DateTime.now();
  }

  /// 更新内容预览
  void updatePreview(String content) {
    contentPreview = content.length > 200 
        ? '${content.substring(0, 200)}...' 
        : content;
    updatedAt = DateTime.now();
  }

  /// 验证向量维度是否正确
  bool get isValidDimension => embedding.length == dimension;

  @override
  String toString() {
    return 'NoteVector(id: $id, noteId: $noteId, dimensions: ${embedding.length})';
  }
}

/// 搜索历史实体
/// 
/// 记录用户的搜索历史，用于个性化推荐
@Entity()
class SearchHistory {
  @Id()
  int id = 0;

  /// 搜索查询文本
  String query;

  /// 查询的嵌入向量
  @Property(type: PropertyType.floatVector)
  List<double>? queryEmbedding;

  /// 搜索时间
  @Property(type: PropertyType.date)
  DateTime searchedAt;

  /// 搜索结果数量
  int resultCount;

  /// 用户是否点击了结果
  bool hasClicked;

  SearchHistory({
    this.id = 0,
    required this.query,
    this.queryEmbedding,
    DateTime? searchedAt,
    this.resultCount = 0,
    this.hasClicked = false,
  }) : searchedAt = searchedAt ?? DateTime.now();

  @override
  String toString() {
    return 'SearchHistory(id: $id, query: $query, resultCount: $resultCount)';
  }
}

/// 相似笔记缓存实体
/// 
/// 缓存预计算的相似笔记关系，加速相关笔记推荐
@Entity()
class SimilarNotesCache {
  @Id()
  int id = 0;

  /// 源笔记 ID
  @Index()
  String sourceNoteId;

  /// 相似笔记 ID 列表 (JSON 格式)
  String similarNoteIdsJson;

  /// 相似度分数列表 (JSON 格式，与 similarNoteIds 一一对应)
  String similarityScoresJson;

  /// 缓存创建时间
  @Property(type: PropertyType.date)
  DateTime cachedAt;

  /// 缓存有效期 (小时)
  int validHours;

  SimilarNotesCache({
    this.id = 0,
    required this.sourceNoteId,
    required this.similarNoteIdsJson,
    required this.similarityScoresJson,
    DateTime? cachedAt,
    this.validHours = 24,
  }) : cachedAt = cachedAt ?? DateTime.now();

  /// 检查缓存是否过期
  bool get isExpired {
    final expiryTime = cachedAt.add(Duration(hours: validHours));
    return DateTime.now().isAfter(expiryTime);
  }

  @override
  String toString() {
    return 'SimilarNotesCache(id: $id, sourceNoteId: $sourceNoteId)';
  }
}
