import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ai/cactus_service.dart';

class LocalAISettingsPage extends StatefulWidget {
  const LocalAISettingsPage({super.key});

  @override
  State<LocalAISettingsPage> createState() => _LocalAISettingsPageState();
}

class _LocalAISettingsPageState extends State<LocalAISettingsPage> {
  // Use final for fields that don't change or are only initialized once.
  // In this case, we might want to update them later with real status, but for now they are static strings.
  // To avoid "prefer_final_fields", we can either make them final or actually update them.
  // I'll make them non-final and add a method to simulate status updates to justify it and avoid the hint,
  // or just ignore the hint since this is a UI state that *will* be dynamic.
  // Actually, the linter is smart: if I assign to it, it won't complain.
  // I'll initialize them in initState to "Unknown" and maybe update them on init.
  String _llmStatus = 'Unknown';
  String _sttStatus = 'Unknown';

  double? _downloadProgress;
  String? _downloadStatusMessage;
  bool _isDownloading = false;

  final String _defaultLLMModel = 'qwen3-0.6';
  final String _defaultVoiceModel = 'whisper-tiny';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local AI Settings'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Local AI Models (Cactus)',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Manage on-device AI models for Chat and Voice transcription.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),

            // LLM Section
            _buildModelCard(
              title: 'LLM (Chat Model)',
              modelName: _defaultLLMModel,
              status: _llmStatus,
              onDownload: () => _downloadModel(_defaultLLMModel, isVoice: false),
            ),

            const SizedBox(height: 16),

            // STT Section
            _buildModelCard(
              title: 'Speech-to-Text (Whisper)',
              modelName: _defaultVoiceModel,
              status: _sttStatus,
              onDownload: () => _downloadModel(_defaultVoiceModel, isVoice: true),
            ),

            if (_isDownloading) ...[
                const SizedBox(height: 24),
                LinearProgressIndicator(value: _downloadProgress),
                const SizedBox(height: 8),
                Text(_downloadStatusMessage ?? 'Downloading...'),
            ],

            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),

            const Text(
              'Test Local AI',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
                onPressed: () {
                     // Initializer
                     _initializeServices();
                },
                icon: const Icon(Icons.bolt),
                label: const Text('Initialize Services')
            ),
             const SizedBox(height: 16),
             OutlinedButton(
                onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const LocalAIChatTestPage()));
                },
                child: const Text('Open Test Chat'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelCard({
    required String title,
    required String modelName,
    required String status,
    required VoidCallback onDownload,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Model: $modelName'),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Status: $status'), // Real status check needed in future
                ElevatedButton(
                  onPressed: _isDownloading ? null : onDownload,
                  child: const Text('Download'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadModel(String slug, {required bool isVoice}) async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      _downloadStatusMessage = 'Starting download for $slug...';
    });

    final cactus = Provider.of<CactusService>(context, listen: false);

    try {
      if (isVoice) {
          await cactus.downloadVoiceModel(slug, onProgress: (progress, status, isError) {
              if (mounted) {
                  setState(() {
                      _downloadProgress = progress;
                      _downloadStatusMessage = status;
                  });
              }
          });
          // Update status on success
          if (mounted) {
              setState(() {
                  _sttStatus = 'Downloaded';
              });
          }
      } else {
          await cactus.downloadModel(slug, onProgress: (progress, status, isError) {
              if (mounted) {
                  setState(() {
                      _downloadProgress = progress;
                      _downloadStatusMessage = status;
                  });
              }
          });
          // Update status on success
          if (mounted) {
              setState(() {
                  _llmStatus = 'Downloaded';
              });
          }
      }

      if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Download complete for $slug')),
          );
      }
    } catch (e) {
      if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Download failed: $e'), backgroundColor: Colors.red),
          );
      }
    } finally {
        if (mounted) {
            setState(() {
                _isDownloading = false;
                _downloadProgress = null;
                _downloadStatusMessage = null;
            });
        }
    }
  }

  Future<void> _initializeServices() async {
      final cactus = Provider.of<CactusService>(context, listen: false);
      await cactus.initialize();
      if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Services Initialized')),
          );
          // Assuming initialization implies readiness
          setState(() {
              if (_llmStatus == 'Downloaded') _llmStatus = 'Ready';
              if (_sttStatus == 'Downloaded') _sttStatus = 'Ready';
          });
      }
  }
}

class LocalAIChatTestPage extends StatefulWidget {
  const LocalAIChatTestPage({super.key});

  @override
  State<LocalAIChatTestPage> createState() => _LocalAIChatTestPageState();
}

class _LocalAIChatTestPageState extends State<LocalAIChatTestPage> {
    final TextEditingController _controller = TextEditingController();
    String _response = '';
    bool _loading = false;

    @override
    Widget build(BuildContext context) {
        return Scaffold(
            appBar: AppBar(title: const Text('Local AI Chat Test')),
            body: Column(
                children: [
                    Expanded(
                        child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Text(_response.isEmpty ? 'Say something...' : _response),
                        ),
                    ),
                    if (_loading) const LinearProgressIndicator(),
                    Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                            children: [
                                Expanded(child: TextField(controller: _controller, decoration: const InputDecoration(hintText: 'Enter message'))),
                                IconButton(icon: const Icon(Icons.send), onPressed: _sendMessage),
                            ],
                        ),
                    )
                ],
            ),
        );
    }

    Future<void> _sendMessage() async {
        if (_controller.text.isEmpty) return;
        final msg = _controller.text;
        _controller.clear();
        setState(() {
            _loading = true;
            _response = 'Thinking...';
        });

        try {
            final cactus = Provider.of<CactusService>(context, listen: false);
            final res = await cactus.chat(msg);
            setState(() {
                _response = res;
            });
        } catch (e) {
            setState(() {
                _response = 'Error: $e';
            });
        } finally {
            setState(() {
                _loading = false;
            });
        }
    }
}
