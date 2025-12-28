import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/services/ai_model_manager.dart';
import 'package:thoughtecho/services/local_embedding_service.dart';
import 'package:thoughtecho/services/local_asr_service.dart';
import 'package:thoughtecho/services/local_ocr_service.dart';

class OfflineAISettingsPage extends StatefulWidget {
  const OfflineAISettingsPage({super.key});

  @override
  State<OfflineAISettingsPage> createState() => _OfflineAISettingsPageState();
}

class _OfflineAISettingsPageState extends State<OfflineAISettingsPage> {
  final AIModelManager _modelManager = AIModelManager();
  Map<String, bool> _downloadStatus = {}; // ID -> isDownloaded
  Map<String, double> _downloadProgress = {}; // ID -> progress

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    for (var model in AIModelManager.supportedModels) {
      final exists = await _modelManager.isModelDownloaded(model.fileName);
      setState(() {
        _downloadStatus[model.id] = exists;
      });
    }
  }

  Future<void> _downloadModel(AIModelConfig config) async {
    setState(() {
      _downloadProgress[config.id] = 0.01;
    });

    try {
      await _modelManager.downloadModel(config, onProgress: (progress) {
        if (mounted) {
          setState(() {
            _downloadProgress[config.id] = progress;
          });
        }
      });
      if (mounted) {
        setState(() {
          _downloadStatus[config.id] = true;
          _downloadProgress.remove(config.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${config.name} 下载成功')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadProgress.remove(config.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 模型管理'),
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              '管理本地 AI 模型以启用离线功能 (语义搜索, 语音转文字, OCR)。\n'
              '这些模型将下载到您的设备上。',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          ...AIModelManager.supportedModels.map((config) {
            final isDownloaded = _downloadStatus[config.id] ?? false;
            final progress = _downloadProgress[config.id];

            return ListTile(
              title: Text(config.name),
              subtitle: Text(isDownloaded ? '已下载' : '未下载 (${(config.expectedSize / 1024 / 1024).toStringAsFixed(1)} MB)'),
              trailing: progress != null
                  ? CircularProgressIndicator(value: progress)
                  : isDownloaded
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : IconButton(
                          icon: const Icon(Icons.download),
                          onPressed: () => _downloadModel(config),
                        ),
            );
          }).toList(),
          const Divider(),
          ListTile(
            title: const Text('OCR 模型 (用户导入)'),
            subtitle: const Text('PaddleOCR Lite / Tesseract'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
               // Navigation to manual import page or show dialog
               ScaffoldMessenger.of(context).showSnackBar(
                 const SnackBar(content: Text('请将 .tflite 模型文件放入应用文档目录的 ai_models 文件夹中')),
               );
            },
          ),
        ],
      ),
    );
  }
}
