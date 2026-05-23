## 2024-05-24 - [优化 getUserQuotes 标签查询的并发处理]
**Learning:** SQLite 的 `IN` 子句批量查询中，当 ID 过多需要分块循环时，顺序 `await` 每个 chunk 的查询会导致不必要的 N+1 延迟。由于这些查询是互相独立的，可以并行发起并在 Dart 层等待。
**Action:** 将 `database_query_helpers_mixin.dart` 中的顺序分块查询改写为收集 `Future<List<Map>>` 并使用 `Future.wait` 并发等待，成功将 `getUserQuotes` 在大分页时的标签查询基准耗时从 ~500ms 降低至 ~200ms。
