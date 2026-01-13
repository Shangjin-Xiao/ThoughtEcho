import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ai/model_manager_service.dart';

class AiModelManagementPage extends StatefulWidget {
  const AiModelManagementPage({super.key});

  @override
  State<AiModelManagementPage> createState() => _AiModelManagementPageState();
}

class _AiModelManagementPageState extends State<AiModelManagementPage> {
  bool _embeddingDownloaded = false;
  bool _asrDownloaded = false;
  bool _isDownloading = false;
  double _progress = 0.0;
  String _status = "";

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final manager = Provider.of<ModelManagerService>(context, listen: false);
    final emb = await manager.areEmbeddingModelsDownloaded();
    final asr = await manager.areAsrModelsDownloaded();
    if (mounted) {
      setState(() {
        _embeddingDownloaded = emb;
        _asrDownloaded = asr;
      });
    }
  }

  Future<void> _downloadEmbedding() async {
    setState(() {
      _isDownloading = true;
      _status = "Downloading Embedding Models...";
      _progress = 0.0;
    });

    try {
      final manager = Provider.of<ModelManagerService>(context, listen: false);
      await manager.downloadEmbeddingModels(onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      await _checkStatus();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _status = "";
        });
      }
    }
  }

  Future<void> _downloadAsr() async {
    setState(() {
        _isDownloading = true;
        _status = "Downloading ASR Models (This involves decompressing, please wait)...";
        _progress = 0.0;
    });

    try {
        final manager = Provider.of<ModelManagerService>(context, listen: false);
        await manager.downloadSherpaModels(onProgress: (p) {
            if (mounted) setState(() => _progress = p);
        });
        await _checkStatus();
    } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
        if (mounted) {
            setState(() {
                _isDownloading = false;
                _status = "";
            });
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("AI Models Management")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_isDownloading)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(_status),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(value: _progress),
                  ],
                ),
              ),
            ),
          ListTile(
            title: const Text("Embedding Model"),
            subtitle: const Text("paraphrase-multilingual-MiniLM-L12-v2 (for Semantic Search)"),
            trailing: _embeddingDownloaded
                ? const Icon(Icons.check_circle, color: Colors.green)
                : ElevatedButton(
                    onPressed: _isDownloading ? null : _downloadEmbedding,
                    child: const Text("Download")
                  ),
          ),
          ListTile(
            title: const Text("ASR Model"),
            subtitle: const Text("Sherpa Onnx Whisper Tiny (for Voice Input)"),
            trailing: _asrDownloaded
                ? const Icon(Icons.check_circle, color: Colors.green)
                : ElevatedButton(
                    onPressed: _isDownloading ? null : _downloadAsr,
                    child: const Text("Download")
                  ),
          ),
        ],
      ),
    );
  }
}
