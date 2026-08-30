## 2026-08-30 - [Stability & Availability] JSON 恢复/反序列化时的枚举索引类型强转陷阱
**Learning:** 在解析备份数据或 JSON 负载中的 enum 索引（如 `ThemeMode.values[index]`）时，不可直接使用 `as int` 强转。若数据源由 JavaScript/Web 生成（可能将 int 序列化为 double，如 `2.0`），或输入越界索引/非法类型，直接强转会导致 `TypeError` 或 `RangeError` 崩溃。
**Action:** 使用 `(raw is num) ? raw.toInt() : int.tryParse(raw?.toString() ?? '')` 安全解析，并校验 `index >= 0 && index < Enum.values.length` 范围后再取枚举值。
