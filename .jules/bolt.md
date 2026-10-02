## 2026-10-26 - 消除 ChatSessionService.getSessionOverviews 中的 N+1 相关子查询

**Learning:** 在 SQLite 查询中，如果在主查询的 `SELECT` 列表中包含对每一行关联数据逐行执行的关联子查询（如 `SELECT s.id, (SELECT COUNT(*) FROM chat_messages c WHERE c.session_id = s.id), (SELECT m.content FROM chat_messages m WHERE m.session_id = s.id ORDER BY m.created_at DESC LIMIT 1) FROM chat_sessions s`），SQLite 引擎需要为每一行目标记录分别扫描/索引检索子表，形成 N+1 相关子查询。改用 SQLite 支持的窗口函数 CTE（例如 `WITH ranked_messages AS (SELECT session_id, content, ROW_NUMBER() OVER (PARTITION BY session_id ORDER BY created_at DESC) AS rn, COUNT(*) OVER (PARTITION BY session_id) AS total_count FROM chat_messages WHERE session_id IN (...)) SELECT ... WHERE rn = 1`），并为其建立复合索引 `(session_id, created_at DESC)`，可一次性在单个 SQL 语句内完成所有会话的最近消息及总条数计算，避免逐行子查询开销。

**Action:** 在 `lib/services/chat_session_service.dart` 中为 `chat_messages` 添加复合索引 `idx_chat_messages_session_created`，并重构 `getSessionOverviews` 使用 `ROW_NUMBER() OVER` 窗口函数单次查出所有匹配 session 的统计与最新消息正文，同时预置默认值兜底，消除列表加载时的 N+1 SQL 耗时。
