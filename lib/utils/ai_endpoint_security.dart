/// AI 服务端点的传输安全判据。
///
/// **判据是「密钥会不会以明文跨过一段我们不控制的网络」，不是「scheme 是不是
/// https」。** 这两件事在公网上等价，在环回和私有网段上不等价，而后者正是
/// 本地模型（Ollama / LM Studio / vLLM / llama.cpp）唯一的部署形态——它们
/// 基本都只监听 `http://127.0.0.1:<port>`，装不了也不需要证书。
///
/// 一刀切成 https-only 的代价是把「本地模型」整个功能判死：
/// `ai_settings_page_test` 里那条 `id: 'local'` / 名字「本机模型」 /
/// `http://localhost:1234/v1/chat/completions` 的夹具就是这个用法的证据。
library;

import 'dart:io' show InternetAddress, InternetAddressType;

/// 这个端点发请求时是否安全。
///
/// - `https` → 永远安全。
/// - `http` → 只有目标在**环回或私有网段**时才安全（包没有离开本机或本地网络）。
/// - 其它 scheme（含拼错的、空的）→ 一律不安全。
/// - 主机为空（`https:foo`、`https:///`）→ 一律不安全，scheme 对也不行。
bool isSecureAiEndpoint(Uri uri) {
  // **没有主机的绝对 URI 一律不安全**，哪怕 scheme 写着 https：
  // `Uri.parse('https:foo')` 和 `https:///` 的 `host` 都是空串，它们 scheme 对
  // 但根本不是一个端点。放行等于把「这地址无效」推迟到发请求时才由 Dio 报错，
  // 而这个判据存在的理由正是「在输入这一层拦住、在能解释的地方说话」。
  if (uri.host.isEmpty) return false;
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'https') return true;
  if (scheme != 'http') return false;
  return _isLocalHost(uri.host);
}

/// 字符串版，解析不了就是不安全。
bool isSecureAiEndpointUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasScheme) return false;
  return isSecureAiEndpoint(uri);
}

/// 主机名/地址是否落在「包不出本机或本地网络」的范围里。
bool _isLocalHost(String host) {
  if (host.isEmpty) return false;
  final name = host.toLowerCase();

  // 主机名形式。`.local` 是 mDNS，只在本地链路解析。
  if (name == 'localhost' ||
      name.endsWith('.localhost') ||
      name.endsWith('.local')) {
    return true;
  }

  // 字面量地址。`Uri.host` 会把 IPv6 的方括号去掉，可以直接喂给 tryParse。
  final address = InternetAddress.tryParse(name);
  if (address == null) return false;
  if (address.isLoopback || address.isLinkLocal) return true;

  final raw = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    // 10/8、172.16/12、192.168/16 —— RFC 1918。
    if (raw[0] == 10) return true;
    if (raw[0] == 172 && raw[1] >= 16 && raw[1] <= 31) return true;
    if (raw[0] == 192 && raw[1] == 168) return true;
    return false;
  }

  // IPv6 唯一本地地址 fc00::/7（fc.. 和 fd..）。
  return (raw[0] & 0xFE) == 0xFC;
}
