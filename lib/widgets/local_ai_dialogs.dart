import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ai/ocr_service.dart';
import 'package:image_picker/image_picker.dart';

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
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    if (!mounted) return;

    setState(() {
      _isProcessing = true;
      _resultText = 'Recognizing text...';
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
          _resultText = 'Error: $e';
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
    return AlertDialog(
      title: const Text('Local OCR'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isProcessing) const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_resultText.isEmpty ? 'Select an image to extract text' : _resultText),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _pickImage, child: const Text('Pick Image')),
        if (_resultText.isNotEmpty)
          TextButton(
            onPressed: () => Navigator.pop(context, _resultText),
            child: const Text('Insert Text'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
