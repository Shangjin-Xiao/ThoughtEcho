import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ai/ocr_service.dart';
import 'package:image_picker/image_picker.dart';
import '../gen_l10n/app_localizations.dart';

class LocalAIOcrDialog extends StatefulWidget {
  const LocalAIOcrDialog({super.key});

  @override
  State<LocalAIOcrDialog> createState() => _LocalAIOcrDialogState();
}

class _LocalAIOcrDialogState extends State<LocalAIOcrDialog> {
  final ImagePicker _picker = ImagePicker();
  String _resultText = '';
  bool _isProcessing = false;

  Future<void> _pickImage() async {
    final l10n = AppLocalizations.of(context);
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    if (!mounted) return;

    setState(() {
      _isProcessing = true;
      _resultText = l10n.ocrProcessing;
    });

    try {
      final ocrService = Provider.of<OCRService>(context, listen: false);
      final text = await ocrService.recognizeText(image.path);
      if (mounted) {
        setState(() {
          _resultText = text;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _resultText = l10n.startFailed(e.toString());
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.localAIOCR),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isProcessing) const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_resultText.isEmpty ? l10n.localAIOCRDesc : _resultText),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _pickImage, child: Text(l10n.ocrCapture)),
        if (_resultText.isNotEmpty)
          TextButton(
            onPressed: () => Navigator.pop(context, _resultText),
            child: Text(l10n.voiceInsertToEditor),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}
