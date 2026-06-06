## 2024-05-18 - 优化 Web 平台标签筛选性能，减少 List.contains 的 N+1 查询
**Learning:**
在列表的循环（如 `where` 和 `any`）中调用 `List.contains` 进行条件判断，会导致 $O(N \times M)$ 的时间复杂度。当被筛选列表较大或者条件数组较长时，这是一个典型的性能热点。对于 Dart 和大多数语言而言，将条件数组预先转换为 `Set`，可以利用 Hash 查找特性将单词检索的时间复杂度降为 $O(1)$，进而将整体时间复杂度从 $O(N \times M)$ 降低至 $O(N)$。在本次通过基准测试发现，在 10,000 条数据、5 个关联标签以及 100 个筛选条件的场景下，替换为 Set 后执行耗时降低了一半左右（约 1.8 倍性能提升）。

**Action:**
修改了 `lib/services/database/database_query_mixin.dart` 与 `lib/services/database/database_query_helpers_mixin.dart` 中 Web 平台的数据内存过滤逻辑。预先使用 `final tagIdSet = tagIds.toSet();`，并在之后的 `.any((tag) => tagIdSet.contains(tag))` 中使用该 Set 替代原有的 `tagIds.contains(tag)`，彻底消除了 N+1 的隐藏复杂度。验证通过了相关多标签过滤的测试。

## 2024-05-30 - 优化 RegExp 编译性能
**Learning:** 在高频调用的方法（如字符串过滤、格式化）中，如果使用字面量正则表达式，Dart 在每次执行到该行时都会调用 `RegExp` 构造函数。由于正则表达式的编译过程（即使带有缓存或者简单匹配）本身具有一定开销，尤其是在长循环或大列表过滤中会被不断放大，应当将其提取为静态只读成员（`static final`）来仅在类加载时编译一次。
**Action:** 在 `lib/services/location_service.dart` 中，将 `_containsLatinOrDigit` 方法里的 `RegExp(r'[A-Za-z0-9]')` 提取为 `static final _latinOrDigitRegex` 并复用。
## 2024-05-30 - 优化 database_backup_service 中的降级插入性能
**Learning:** The fallback block for database record insertion was incorrectly using sequential `await txn.insert()` for every tag of every quote. Although the initial quote array batch failed forcing this fallback, making another N+1 sequential request inside the fallback loop compounded the performance issue significantly.
**Action:** Removed the sequential `txn.insert` call inside the tag resolution loop. Appended the records to `tagRelations` which is eventually processed by an existing, outer batched `txn.batch()` execution.
## 2024-05-30 - 优化 ContentSanitizer 正则表达式编译性能
**Learning:**
在处理基于字符串分析的操作时（如 `injectCsp` 等方法），如果内联声明 `RegExp(...)`，Dart 会在每次调用方法时重新解析和编译正则表达式对象。尽管内部有一定缓存，但对于存在多次替换操作（如连续调用 `replaceAll` 和 `replaceFirstMapped`），频繁的对象分配和匹配查找依然会构成性能开销。
**Action:**
将 `injectCsp` 方法体内的所有用于 CSP 标签过滤、 `<script>` 标签清除以及 `<head>` 和 `<html>` 标签查找的正则表达式提取为类的 `static final RegExp` 字段。这种模式确保它们只会在类第一次被加载时进行编译（单次分配），避免了每次执行清理操作时重复实例化对象的问题，并更新了受影响的单元测试。
