import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../gen_l10n/app_localizations.dart';
import '../services/api_key_manager.dart';
import '../services/settings_service.dart';

/// API密钥诊断工具
class ApiKeyDiagnosticsPage extends StatefulWidget {
  const ApiKeyDiagnosticsPage({super.key});

  @override
  State<ApiKeyDiagnosticsPage> createState() => _ApiKeyDiagnosticsPageState();
}

class _ApiKeyDiagnosticsPageState extends State<ApiKeyDiagnosticsPage> {
  AppLocalizations get l10n => AppLocalizations.of(context);
  String _diagnosticResult = '';
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.apiKeyDiagnosticsTitle),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.apiKeyDiagnosticsTool,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.apiKeyDiagnosticsDesc,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _runDiagnostics,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.runDiagnostics),
            ),
            const SizedBox(height: 24),
            if (_diagnosticResult.isNotEmpty) ...[
              Text(
                l10n.diagnosticResultLabel,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      _diagnosticResult,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _runDiagnostics() async {
    setState(() {
      _isLoading = true;
      _diagnosticResult = '';
    });

    final buffer = StringBuffer();
    buffer.writeln(l10n.diagnosticReportHeader);
    buffer.writeln(l10n.diagnosticReportTime(DateTime.now().toString()));
    buffer.writeln();

    try {
      // 获取设置服务
      final settingsService = Provider.of<SettingsService>(
        context,
        listen: false,
      );

      // 使用多供应商API密钥管理器
      final apiKeyManager = APIKeyManager();
      final multiSettings = settingsService.multiAISettings;
      final currentProvider = multiSettings.currentProvider;

      // 1. 多供应商配置检查
      buffer.writeln(l10n.diagnosticMultiProviderCheck);
      buffer.writeln(
        l10n.diagnosticCurrentProvider(
          currentProvider?.name ?? l10n.notSelectedStatus,
        ),
      );
      buffer.writeln(
        l10n.diagnosticAvailableProviders(multiSettings.providers.length),
      );
      buffer.writeln(
        l10n.diagnosticEnabledProviders(
          multiSettings.providers.where((p) => p.isEnabled).length,
        ),
      );
      buffer.writeln();

      if (currentProvider != null) {
        // 2. 当前供应商详情
        buffer.writeln(l10n.diagnosticProviderDetails);
        buffer.writeln(l10n.diagnosticProviderId(currentProvider.id));
        buffer.writeln(l10n.diagnosticProviderName(currentProvider.name));
        buffer.writeln(l10n.diagnosticProviderUrl(currentProvider.apiUrl));
        buffer.writeln(l10n.diagnosticProviderModel(currentProvider.model));
        buffer.writeln(
          l10n.diagnosticProviderEnabled(
            currentProvider.isEnabled ? l10n.yesStatus : l10n.noStatus,
          ),
        );
        buffer.writeln();

        // 3. API密钥检查
        buffer.writeln(l10n.diagnosticApiKeyCheck);
        final hasApiKeyInSettings = currentProvider.apiKey.trim().isNotEmpty;
        buffer.writeln(
          l10n.diagnosticApiKeyInSettings(
            hasApiKeyInSettings ? l10n.yesStatus : l10n.noStatus,
          ),
        );

        if (hasApiKeyInSettings) {
          buffer.writeln(
            l10n.diagnosticApiKeyLength(currentProvider.apiKey.length),
          );
          buffer.writeln(
            l10n.diagnosticApiKeyPrefix(
              currentProvider.apiKey.length > 15
                  ? "${currentProvider.apiKey.substring(0, 15)}..."
                  : currentProvider.apiKey,
            ),
          );
        }

        // 检查安全存储中的密钥
        final secureApiKey = await apiKeyManager.getProviderApiKey(
          currentProvider.id,
        );
        final hasSecureApiKey = secureApiKey.isNotEmpty;
        buffer.writeln(
          l10n.diagnosticSecureApiKeyExists(
            hasSecureApiKey ? l10n.yesStatus : l10n.noStatus,
          ),
        );

        if (hasSecureApiKey) {
          buffer.writeln(
            l10n.diagnosticSecureApiKeyLength(secureApiKey.length),
          );
          buffer.writeln(
            l10n.diagnosticSecureApiKeyPrefix(
              secureApiKey.length > 15
                  ? "${secureApiKey.substring(0, 15)}..."
                  : secureApiKey,
            ),
          );
        }
        buffer.writeln();

        // 4. 密钥验证
        buffer.writeln(l10n.diagnosticApiKeyValidation);
        final isValidAsync = await apiKeyManager.hasValidProviderApiKey(
          currentProvider.id,
        );
        buffer.writeln(
          l10n.diagnosticAsyncValidation(
            isValidAsync ? l10n.passStatus : l10n.failStatus,
          ),
        );

        if (hasSecureApiKey) {
          final isFormatValid = apiKeyManager.isValidApiKeyFormat(secureApiKey);
          buffer.writeln(
            l10n.diagnosticFormatValidation(
              isFormatValid ? l10n.passStatus : l10n.failStatus,
            ),
          );
        }
        buffer.writeln();
      } else {
        buffer.writeln(l10n.diagnosticErrorNoProvider);
        buffer.writeln();
      }

      // 5. 所有供应商状态
      buffer.writeln(l10n.diagnosticAllProvidersStatus);
      for (final provider in multiSettings.providers) {
        final hasKey = await apiKeyManager.hasValidProviderApiKey(provider.id);
        buffer.writeln(
          l10n.diagnosticProviderStatusItem(
            provider.name,
            hasKey ? "✓" : "✗",
            provider.isEnabled
                ? "(${l10n.settingsLocationEnabled})"
                : "(${l10n.locationServiceDisabled})",
          ),
        );
      }
      buffer.writeln();

      // 6. 建议
      buffer.writeln(l10n.diagnosticSuggestions);
      if (currentProvider == null) {
        buffer.writeln(l10n.diagnosticSuggestionSelectProvider);
      } else if (!currentProvider.isEnabled) {
        buffer.writeln(l10n.diagnosticSuggestionEnableProvider);
      } else {
        final hasValidKey = await apiKeyManager.hasValidProviderApiKey(
          currentProvider.id,
        );
        if (!hasValidKey) {
          buffer.writeln(
            l10n.diagnosticSuggestionConfigureKey(currentProvider.name),
          );
        } else {
          buffer.writeln(l10n.diagnosticSuggestionNormal);
        }
      }

      buffer.writeln();
      buffer.writeln(l10n.diagnosticComplete);
    } catch (e) {
      buffer.writeln(l10n.diagnosticError(e.toString()));
    }

    setState(() {
      _isLoading = false;
      _diagnosticResult = buffer.toString();
    });
  }
}
