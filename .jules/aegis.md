## 2026-03-29 - [消息模型异构反序列化类型守卫与日志兜底]
**Learning:** 在解析从 SQLite、网络同步或备份还原反序列化获取的 JSON/Map 字段时，使用 `as String?` 或 `as bool?` 等强转在遇上 `int`/`Map`/`List` 或非标准类型值时会直接触发 `TypeError` 运行时崩溃，且在嵌套列表遍历中引发整个会话/消息列表被清空丢弃。
**Action:** 使用安全类型解析辅助函数（如 `_parseBool`、`_parseString`、`.toString()`）处理异构字段提取，同时对解析重试标志进行状态缓存以防止性能损耗，并在跳过坏数据节点时使用 `AppLogger.w` 补齐上下文日志。

## 2026-03-29 - [模型解构与富文本 SafeDeltaOps 防御性强转]
**Learning:** 在解析由 JSON 反序列化得到的 `List<dynamic>` 集合（例如 Quill Delta JSON 的 ops）时，直接使用 `Map<String, dynamic>.from(item)` 可能在 `item` key 非 String 或元素非 Map (如 null、num、String) 时抛出 `TypeError` 崩溃。
**Action:** 在对 List 动态元素转型为 `Map<String, dynamic>` 前，必须先通过 `item is Map` 进行守卫判断，并显式转换 key（如 `item.map((k, v) => MapEntry(k.toString(), v))`），确保类型转换极致健壮。
