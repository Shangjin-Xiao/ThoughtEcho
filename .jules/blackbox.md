## YYYY-MM-DD - [标题]
**异常:** [发现了何种隐蔽的错误抛出]
**拦截:** [确立的该类错误的日志规范]
## 2025-05-18 - 🗃️ 黑匣: [完善 ApiKeyManager 模块的结构化日志]
**异常:** [APIKeyManager 中获取和验证 API 密钥失败时，仅使用了 logDebug 进行了粗糙的打印，丢失了关键的错误堆栈信息 (stackTrace) 以及错误来源模块 (source) 等上下文，不利于排查安全存储获取失败的根因。]
**拦截:** [已将 getProviderApiKey 和 hasValidProviderApiKey 方法中的错误捕获升级为结构化的 AppLogger.e 调用，注入了明确的错误对象、堆栈轨迹以及模块标识 'APIKeyManager'。同时确认了日志内容未包含任何用户密钥等敏感隐私数据，仅记录了 providerId。]
## 2025-05-18 - 🗃️ 黑匣: [完善 smart_push_analytics 模块的结构化日志]
**异常:** [SmartPushAnalytics 模块在解析应用打开记录、分析内容得分、处理通知指标、计算冷却时间与疲劳预算时，遇到解析失败或取值异常等隐蔽错误仅使用 `catch (e)` 进行了返回默认值或粗糙的 `debugPrint`，丢失了错误来源、异常堆栈等关键上下文。这可能导致推送策略效果恶化而无法被排查。]
**拦截:** [已将上述流程中的 `catch (e)` 替换为结构化的 `AppLogger.e`，注入了具体的报错信息、`error` 对象、`stackTrace` 以及 `source: 'SmartPushAnalytics'` 的模块标识。确认所有记录皆针对解析配置和统计信息失败，不包含任何推送正文或用户隐私等敏感数据。]

## 2025-10-24 - 🗃️ 黑匣: [完善 NetworkService 模块的结构化日志]
**异常:** [NetworkService 模块在处理普通AI请求、流式AI请求以及解析流式响应JSON遇到异常时，仅使用了 logDebug 进行了粗糙的打印，丢失了错误堆栈信息以及明确的模块来源信息，不利于后续快速定位AI请求或者响应解析阶段发生的深层错误。]
**拦截:** [已将上述处理环节中的 `catch (e)` 替换为结构化的 `AppLogger.e`，注入了对应的文字描述、具体的异常对象 `error: e`，以及指定了明确的日志来源模块 `source: 'NetworkService'`。确认了记录的内容皆为报错或解析异常，没有包含用户的敏感数据（如API Key、具体的聊天记录等）。]

## 2025-10-24 - 🗃️ 黑匣: [完善 NoteSyncPage 模块的结构化日志]
**异常:** [NoteSyncPage 模块在初始化同步服务、设备发现、发送笔记以及异常停止等环节遇到错误时，仅使用了 `debugPrint` 进行了粗糙的打印。这不仅丢失了关键的异常堆栈信息，还缺少统一的日志来源（source）标记，使得排查同步相关故障时难以追溯上下文。]
**拦截:** [已将上述流程中的 `debugPrint('...失败: $e')` 替换为结构化的 `AppLogger.e`，注入了对应的报错描述、具体的异常对象 `error: e`、堆栈轨迹 `stackTrace: stack`，以及指定了明确的日志来源模块 `source: 'NoteSyncPage'`。确认所有的错误记录仅涉及连接、通信与网络相关的异常对象自身，未包含任何同步的笔记内容文本、用户凭据等敏感隐私数据。]

## 2024-05-31 - [完善 NetworkService 模块的结构化日志]
**异常:** NetworkService 的 GET 和 POST 方法在遇到 DioException 时，只返回了携带简短 error 信息的 HttpResponse，没有使用统一的 AppLogger 进行上报；AI 流式请求和重试拦截器中的错误捕获存在空捕获或缺失堆栈信息的情况，会导致线上排查困难且掩盖了重试中途的隐蔽错误。
**拦截:** 修改所有拦截点，强制使用 `catch (e, stack)` 进行捕获，并使用 `AppLogger.e('...', error: e, stackTrace: stack, source: 'NetworkService')` 上报。所有日志中均仅记录 url、状态码和异常对象，绝不包含用户授权凭证、请求体或响应体内容。
