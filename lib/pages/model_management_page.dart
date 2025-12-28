import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:thoughtecho/services/model_manager.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';

class ModelManagementPage extends StatelessWidget {
  const ModelManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).modelManagementTitle), // Key needs to be added
      ),
      body: ChangeNotifierProvider.value(
        value: ModelManager.instance,
        child: Consumer<ModelManager>(
          builder: (context, manager, child) {
            return ListView(
              children: [
                _buildModelItem(
                  context,
                  manager,
                  ModelType.gemma,
                  "Gemma 2B (LLM)",
                  "~1.5GB",
                  "Core intelligence for text processing"
                ),
                _buildModelItem(
                  context,
                  manager,
                  ModelType.whisperTiny,
                  "Whisper Tiny (ASR)",
                  "~39MB",
                  "Fast speech recognition"
                ),
                _buildModelItem(
                  context,
                  manager,
                  ModelType.whisperBase,
                  "Whisper Base (ASR)",
                  "~74MB",
                  "Better accuracy speech recognition"
                ),
                _buildModelItem(
                  context,
                  manager,
                  ModelType.tesseractChi,
                  "Tesseract Chinese (OCR)",
                  "~50MB",
                  "Chinese text recognition"
                ),
                 _buildModelItem(
                  context,
                  manager,
                  ModelType.tesseractEng,
                  "Tesseract English (OCR)",
                  "~20MB",
                  "English text recognition"
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildModelItem(
    BuildContext context,
    ModelManager manager,
    ModelType type,
    String title,
    String size,
    String description
  ) {
    final status = manager.getStatus(type);
    final progress = manager.getProgress(type);
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    Text(size, style: theme.textTheme.bodySmall),
                  ],
                ),
                _buildStatusBadge(context, status),
              ],
            ),
            const SizedBox(height: 8),
            Text(description, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            if (status == ModelStatus.downloading)
              LinearProgressIndicator(value: progress),
            if (status != ModelStatus.downloading)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (status != ModelStatus.ready)
                  OutlinedButton.icon(
                    onPressed: () => _importModel(context, manager, type),
                    icon: const Icon(Icons.file_upload),
                    label: const Text('Import'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: status == ModelStatus.ready
                        ? null // Already downloaded
                        : () => manager.downloadModel(type),
                    icon: Icon(status == ModelStatus.ready ? Icons.check : Icons.download),
                    label: Text(status == ModelStatus.ready ? 'Ready' : 'Download'),
                  ),
                ],
              ),
            if (status == ModelStatus.error)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Download failed. Please try again or import manually.', style: TextStyle(color: theme.colorScheme.error)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context, ModelStatus status) {
    Color color;
    String text;

    switch (status) {
      case ModelStatus.notDownloaded:
        color = Colors.grey;
        text = 'Not Installed';
        break;
      case ModelStatus.downloading:
        color = Colors.blue;
        text = 'Downloading';
        break;
      case ModelStatus.ready:
        color = Colors.green;
        text = 'Ready';
        break;
      case ModelStatus.error:
        color = Colors.red;
        text = 'Error';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  Future<void> _importModel(BuildContext context, ModelManager manager, ModelType type) async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      try {
        await manager.importModel(type, result.files.single.path!);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Model imported successfully')),
          );
        }
      } catch (e) {
         if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Import failed: $e')),
          );
        }
      }
    }
  }
}
