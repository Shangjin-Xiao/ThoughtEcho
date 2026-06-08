# ThoughtEcho 本地 AI 功能架构更新调研报告

## 执行摘要
针对用户关于 ThoughtEcho 接入本地 AI 功能的最新反馈（`fluttergemma` 切换至 Qdrant、`tostore` 包存在、ASR 方案比对），本报告进行了新一轮的全面梳理。调研确认：`tostore` 确实存在于 pub.dev，它是一个支持向量搜索的跨平台多模态数据引擎；`fluttergemma` (从 0.16.x 版本起) 已将底层向量数据库从 SQLite 升级为内嵌的 `qdrant-edge` (Rust FFI)，性能提升显著；关于 ASR，`sherpa_onnx` (Whisper) 是纯粹的语音转文本方案，而 `fluttergemma` 提供的是输入给大模型的多模态处理能力。对于低性能要求的移动端应用，建议在“智能标签/搜索”侧利用更新后的 `fluttergemma` (含 Qdrant) 与 `tostore` 进行技术选型，在“语音转笔记”侧坚决保留 `sherpa_onnx`。

## 信心评估
- **高信心**：关于 `tostore` 的能力、`fluttergemma` 集成 Qdrant 的具体实现方式、以及 `sherpa_onnx` 和 `fluttergemma` 处理音频差异的对比。
- **说明**：调研完全基于最新的 pub.dev 数据与代码仓库事实。

---

## 1. 向量搜索更新：fluttergemma 与 qdrant-edge

### 1.1 fluttergemma 最新向量搜索实现
用户的反馈完全正确。`fluttergemma` 在最新版本（>= 0.16.x）中，已将传统的 `DartVectorStoreRepository` (基于 SQLite + 本地 HNSW) 标记为弃用，并**默认切换为 `qdrant-edge`**。
- **集成方式**：它并未运行独立的 Qdrant 服务器客户端，而是**在设备本地运行一个内嵌的 Qdrant 实例**。底层通过编译 Rust 的共享库 (`qdrant_edge_ffi`) 并借助 Dart 的 FFI (`dart:ffi`) 直接调用。
- **原理**：初始化时，它在设备本地创建 Shard 目录，将 WAL（预写日志）和段文件落盘。通过 `QdrantEdgeClient.open` 和 `qe_shard_search` 实现数据的增删改查。

### 1.2 对低性能移动端的影响
这不仅不是负担，反而带来了**巨大的性能红利**：
- **速度飙升**：数学计算（距离计算和索引）从 Dart VM 转移到了极度优化的内存安全语言 Rust，官方文档称向量操作速度提升了 **30~300 倍**，大幅减少 UI 线程丢帧和 GC 卡顿。
- **智能索引省内存**：内嵌 Qdrant 根据数据量动态决策，当数据少于约 2 万条阈值时，直接暴力计算纯段，不会强行构建极其消耗内存的 HNSW 图，这对移动端极度友好。

---

## 2. 揭开 `tostore` 的面纱

在 pub.dev 查找到了确切存在的 `tostore` 包（[仓库: tocreator/tostore](https://github.com/tocreator/tostore)）。
- **它是什么？** `tostore` 是一个专为 Flutter/Dart 打造的本地优先、支持多模态数据（关系型、Key-Value、高维向量）的存储引擎。
- **向量搜索机制**：内置支持向量字段 (`DataType.vector`) 和基于近邻图的索引 (`VectorIndexType.ngh`)。支持余弦相似度、欧式距离，可调整精度（float32/int8）和构建参数。
- **性能特性**：它最大的特色是**智能负载调度（时间切片）**，在大量插入或重度查询时，会主动让出主线程（默认每次执行 8ms），确保 Flutter UI 保持 60/120fps 的丝滑。且不依赖臃肿的 C/C++ 数据库库，依赖极少。
- **选型建议**：如果想要一个“All-in-One”的 Dart 原生（不折腾 C 扩展编译）并带流式监听 (`watch`) 功能的轻量数据库，`tostore` 是实现智能笔记检索的优秀候选项。

---

## 3. ASR 方案比对：Sherpa vs fluttergemma

用户疑问：是否可以用 `fluttergemma` 一键搞定语音识别，替代目前的 Sherpa 方案？

**结论：绝不能替换。请继续使用 `sherpa_onnx` 进行语音转文本。**

### 3.1 机制差异
- **`sherpa_onnx` (Whisper)**：**真正的 ASR**。它提取音频特征并专属解码为文本。
- **`fluttergemma`**：**多模态大模型入口**。它将音频当做 Token 喂给百亿参数的通用大语言模型（如 Gemma 3），模型在“理解”音频后通过对话生成文本。它往往带有聊天冗余（如：“好的，您的语音内容是：...”），需要极其严苛的 Prompt 控制，且不支持实时流式语音识别（VAD、随说随出）。

### 3.2 资源消耗极其悬殊
| 维度 | `sherpa_onnx` (Whisper Tiny) | `fluttergemma` (Gemma LLM) | 胜出者 |
| :--- | :--- | :--- | :--- |
| **模型磁盘占用** | **~40 MB** (int8 量化) | **1.5 GB ~ 3 GB+** (int4 量化) | Sherpa (碾压) |
| **运行时内存 (RAM)** | **100 ~ 150 MB** | **2 GB ~ 3.5 GB+** | Sherpa (防 OOM) |
| **执行速度** | 实时或超实时 | 极慢（几 Token/秒，可能需几分钟） | Sherpa |
| **电池与发热** | 中低功耗 | **极端耗电与发热** (重度压榨 CPU/NPU) | Sherpa |

---

## 4. 最佳落地架构建议 (更新版)

结合最新调研，针对 ThoughtEcho 对**性能要求低、高效**的核心诉求，建议从以下方案着手：

### 4.1 智能标签推荐 (基于 fluttergemma)
维持原方案：用户完成笔记记录后，利用 `fluttergemma` 加载 2B 文本模型。
- **优化点**：用完即毁（Dispose）。绝不要让 2GB 的大模型常驻内存。务必放在后台 Isolate 计算。

### 4.2 智能搜索笔记 / 向量数据库 (tostore vs fluttergemma Qdrant)
- **方案 A (低心智负担, All-in-One)**：如果想将 ThoughtEcho 现有的 Sqflite 整体迁移或者只新建一个轻量数据层，可以使用 **`tostore`**。它的 Time-Slicing 防卡顿机制对 Flutter 极度友好，且配置灵活（可直接传 List<num>）。
- **方案 B (极致检索性能)**：继续深挖 **`fluttergemma` 的内嵌 Qdrant**。由于该库已经用 Rust FFI 实现了底层的海量向量搜索，您可以直接通过它暴露的 API 管理 Embeddings，速度最快。只需通过 Gecko 模型抽取出文本特征，存入 `QdrantVectorStoreRepository`，根据 ID 与笔记进行映射。

### 4.3 语音识别输入 (坚守 sherpa_onnx)
完全保留 PR #39 中对 `sherpa_onnx` 的集成。它是将用户语音高效转换为文本的唯一合理选择。只有当需求变为“用语音直接与 AI 助手对话探讨笔记”时，才将音频流交给 `fluttergemma`。