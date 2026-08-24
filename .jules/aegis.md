## 2026-03-29 - [模型解构与富文本 SafeDeltaOps 防御性强转]
**Learning:** 在解析由 JSON 反序列化得到的 `List<dynamic>` 集合（例如 Quill Delta JSON 的 ops）时，直接使用 `Map<String, dynamic>.from(item)` 可能在 `item` key 非 String 或元素非 Map (如 null、num、String) 时抛出 `TypeError` 崩溃。
**Action:** 在对 List 动态元素转型为 `Map<String, dynamic>` 前，必须先通过 `item is Map` 进行守卫判断，并显式转换 key（如 `item.map((k, v) => MapEntry(k.toString(), v))`），确保类型转换极致健壮。
