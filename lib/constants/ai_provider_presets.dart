import '../gen_l10n/app_localizations.dart';

/// 内置服务商模板的分组。
enum AIPresetKind {
  /// 云端服务，需要 API Key。
  cloud,

  /// 本机运行的推理服务，通常不需要 API Key。
  local,

  /// 完全手填的 OpenAI 兼容服务。
  custom,
}

/// 一个内置的 AI 服务商模板。
///
/// 模板只是「填表助手」：选中后把 [apiUrl] / [defaultModel] 填进表单，
/// 用户仍然可以随意改。它不是保存后的配置本身——保存后的配置是
/// [AIProviderSettings]，两者不要混为一谈。
///
/// 目前所有模板都走 OpenAI 兼容的 `/chat/completions` 协议，包括
/// Gemini（官方提供 OpenAI 兼容端点）。Anthropic 官方的 `/v1/messages`
/// 协议与此不兼容，应用尚未实现对应的请求/响应适配，因此不在模板列表里；
/// 需要 Claude 的用户请通过 OpenRouter 调用。
class AIProviderPreset {
  const AIProviderPreset({
    required this.id,
    required this.apiUrl,
    required this.kind,
    this.defaultModel = '',
    this.suggestedModels = const [],
    this.consoleUrl,
    this.requiresApiKey = true,
    this.recommended = false,
  });

  /// 模板标识，仅用于查找和展示，不会成为保存后配置的 id。
  final String id;

  /// 服务商文档里给出的 base URL，例如 `https://ollama.com/v1`。
  ///
  /// 这里刻意不写成完整的 `/chat/completions`：用户对着官方文档核对时看到的
  /// 应该是同一个地址。发请求前由 [AIProviderSettings.resolveRequestUrl] 补全。
  final String apiUrl;

  final AIPresetKind kind;

  /// 选中模板后预填的模型名，空字符串表示需要用户自己填。
  final String defaultModel;

  /// 展示为快捷选项的常用模型。
  final List<String> suggestedModels;

  /// 申请 / 查看 API Key 的页面，null 表示无需申请。
  final String? consoleUrl;

  final bool requiresApiKey;

  /// 是否作为首推项排在最前面。
  final bool recommended;

  String nameOf(AppLocalizations l10n) {
    switch (id) {
      case 'ollama_cloud':
        return l10n.aiProviderOllamaCloud;
      case 'openai':
        return l10n.aiProviderOpenAI;
      case 'openrouter':
        return l10n.aiProviderOpenRouter;
      case 'deepseek':
        return l10n.aiProviderDeepSeek;
      case 'siliconflow':
        return l10n.siliconflow;
      case 'zhipu':
        return l10n.aiProviderZhipu;
      case 'moonshot':
        return l10n.aiProviderMoonshot;
      case 'dashscope':
        return l10n.aiProviderDashScope;
      case 'volcengine':
        return l10n.aiProviderVolcengine;
      case 'gemini':
        return l10n.aiProviderGemini;
      case 'ollama_local':
        return l10n.aiProviderOllama;
      case 'lmstudio':
        return l10n.aiProviderLMStudio;
      default:
        return l10n.openapiCompatible;
    }
  }

  String descriptionOf(AppLocalizations l10n) {
    switch (id) {
      case 'ollama_cloud':
        return l10n.presetDescOllamaCloud;
      case 'openai':
        return l10n.presetDescOpenAI;
      case 'openrouter':
        return l10n.presetDescOpenRouter;
      case 'deepseek':
        return l10n.presetDescDeepSeek;
      case 'siliconflow':
        return l10n.presetDescSiliconFlow;
      case 'zhipu':
        return l10n.presetDescZhipu;
      case 'moonshot':
        return l10n.presetDescMoonshot;
      case 'dashscope':
        return l10n.presetDescDashScope;
      case 'volcengine':
        return l10n.presetDescVolcengine;
      case 'gemini':
        return l10n.presetDescGemini;
      case 'ollama_local':
        return l10n.presetDescOllamaLocal;
      case 'lmstudio':
        return l10n.presetDescLMStudio;
      default:
        return l10n.presetDescCustom;
    }
  }
}

/// 内置服务商模板目录。
///
/// 顺序即展示顺序：推荐项在最前，然后是其余云端服务、本地服务、自定义。
class AIProviderPresets {
  const AIProviderPresets._();

  static const List<AIProviderPreset> all = [
    // 首推：免费额度充足，注册即可用，是普通用户成本最低的入口。
    AIProviderPreset(
      id: 'ollama_cloud',
      apiUrl: 'https://ollama.com/v1',
      kind: AIPresetKind.cloud,
      defaultModel: 'gpt-oss:120b',
      suggestedModels: [
        'gpt-oss:120b',
        'gpt-oss:20b',
        'qwen3-coder:480b',
        'deepseek-v3.1:671b',
      ],
      consoleUrl: 'https://ollama.com/settings/keys',
      recommended: true,
    ),
    AIProviderPreset(
      id: 'openai',
      apiUrl: 'https://api.openai.com/v1',
      kind: AIPresetKind.cloud,
      defaultModel: 'gpt-4o-mini',
      suggestedModels: ['gpt-4o-mini', 'gpt-4o'],
      consoleUrl: 'https://platform.openai.com/api-keys',
    ),
    AIProviderPreset(
      id: 'openrouter',
      apiUrl: 'https://openrouter.ai/api/v1',
      kind: AIPresetKind.cloud,
      defaultModel: 'openai/gpt-4o-mini',
      suggestedModels: [
        'openai/gpt-4o-mini',
        'anthropic/claude-sonnet-4.5',
        'google/gemini-2.5-flash',
      ],
      consoleUrl: 'https://openrouter.ai/keys',
    ),
    AIProviderPreset(
      id: 'deepseek',
      apiUrl: 'https://api.deepseek.com/v1',
      kind: AIPresetKind.cloud,
      defaultModel: 'deepseek-chat',
      suggestedModels: ['deepseek-chat', 'deepseek-reasoner'],
      consoleUrl: 'https://platform.deepseek.com/api_keys',
    ),
    AIProviderPreset(
      id: 'siliconflow',
      apiUrl: 'https://api.siliconflow.cn/v1',
      kind: AIPresetKind.cloud,
      defaultModel: 'Qwen/Qwen2.5-7B-Instruct',
      suggestedModels: [
        'Qwen/Qwen2.5-7B-Instruct',
        'deepseek-ai/DeepSeek-V3',
      ],
      consoleUrl: 'https://cloud.siliconflow.cn/account/ak',
    ),
    AIProviderPreset(
      id: 'zhipu',
      apiUrl: 'https://open.bigmodel.cn/api/paas/v4',
      kind: AIPresetKind.cloud,
      defaultModel: 'glm-4-flash',
      suggestedModels: ['glm-4-flash', 'glm-4-plus'],
      consoleUrl: 'https://open.bigmodel.cn/usercenter/apikeys',
    ),
    AIProviderPreset(
      id: 'moonshot',
      apiUrl: 'https://api.moonshot.cn/v1',
      kind: AIPresetKind.cloud,
      defaultModel: 'moonshot-v1-8k',
      suggestedModels: ['moonshot-v1-8k', 'moonshot-v1-32k'],
      consoleUrl: 'https://platform.moonshot.cn/console/api-keys',
    ),
    AIProviderPreset(
      id: 'dashscope',
      apiUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      kind: AIPresetKind.cloud,
      defaultModel: 'qwen-plus',
      suggestedModels: ['qwen-plus', 'qwen-turbo', 'qwen-max'],
      consoleUrl: 'https://bailian.console.aliyun.com/?tab=model#/api-key',
    ),
    AIProviderPreset(
      id: 'volcengine',
      apiUrl: 'https://ark.cn-beijing.volces.com/api/v3',
      kind: AIPresetKind.cloud,
      consoleUrl: 'https://console.volcengine.com/ark',
    ),
    AIProviderPreset(
      id: 'gemini',
      apiUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      kind: AIPresetKind.cloud,
      defaultModel: 'gemini-2.5-flash',
      suggestedModels: ['gemini-2.5-flash', 'gemini-2.5-pro'],
      consoleUrl: 'https://aistudio.google.com/apikey',
    ),
    AIProviderPreset(
      id: 'ollama_local',
      apiUrl: 'http://localhost:11434/v1',
      kind: AIPresetKind.local,
      requiresApiKey: false,
    ),
    AIProviderPreset(
      id: 'lmstudio',
      apiUrl: 'http://localhost:1234/v1',
      kind: AIPresetKind.local,
      requiresApiKey: false,
    ),
    AIProviderPreset(
      id: 'custom',
      apiUrl: '',
      kind: AIPresetKind.custom,
    ),
  ];

  static AIProviderPreset get recommended =>
      all.firstWhere((preset) => preset.recommended);

  static AIProviderPreset? byId(String id) {
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  /// 按 API 地址反查模板，用于把老配置对上号后展示图标和帮助链接。
  ///
  /// 先精确匹配，再退回到 host + 端口匹配，这样用户把 `/v1` 补成
  /// `/v1/chat/completions`（或反过来）之后依然认得出来。端口必须一起比，
  /// 否则 Ollama 本地（11434）和 LM Studio（1234）会互相认错。
  static AIProviderPreset? matchApiUrl(String apiUrl) {
    final trimmed = apiUrl.trim();
    if (trimmed.isEmpty) return null;

    for (final preset in all) {
      if (preset.apiUrl.isNotEmpty && preset.apiUrl == trimmed) {
        return preset;
      }
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) return null;
    for (final preset in all) {
      if (preset.apiUrl.isEmpty) continue;
      final presetUri = Uri.tryParse(preset.apiUrl);
      if (presetUri != null &&
          presetUri.host == uri.host &&
          presetUri.port == uri.port) {
        return preset;
      }
    }
    return null;
  }

  static List<AIProviderPreset> ofKind(AIPresetKind kind) =>
      all.where((preset) => preset.kind == kind).toList(growable: false);
}
