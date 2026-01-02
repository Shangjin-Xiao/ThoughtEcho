import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/ai/cactus_service.dart';

class VoiceRecordDialog extends StatefulWidget {
  const VoiceRecordDialog({super.key});

  @override
  State<VoiceRecordDialog> createState() => _VoiceRecordDialogState();
}

class _VoiceRecordDialogState extends State<VoiceRecordDialog> {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isProcessing = false;
  String _statusText = 'Press button to start recording';
  String _recordingPath = '';

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    try {
      if (_isRecording) {
        // Stop recording
        final path = await _recorder.stop();
        if (path != null) {
          setState(() {
            _isRecording = false;
            _recordingPath = path;
            _statusText = 'Processing...';
            _isProcessing = true;
          });
          await _transcribe();
        }
      } else {
        // Start recording
        if (await _recorder.hasPermission()) {
          final directory = await getTemporaryDirectory();
          final path = '${directory.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

          await _recorder.start(const RecordConfig(), path: path);

          setState(() {
            _isRecording = true;
            _statusText = 'Recording...';
          });
        } else {
          setState(() {
            _statusText = 'Microphone permission denied';
          });
        }
      }
    } catch (e) {
      setState(() {
        _isRecording = false;
        _statusText = 'Error: $e';
        _isProcessing = false;
      });
    }
  }

  Future<void> _transcribe() async {
    try {
      final cactus = Provider.of<CactusService>(context, listen: false);
      final text = await cactus.transcribe(_recordingPath);

      if (mounted) {
        Navigator.pop(context, text);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusText = 'Transcription failed: $e';
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Voice Input'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_statusText),
          const SizedBox(height: 20),
          if (_isProcessing)
            const CircularProgressIndicator()
          else
            GestureDetector(
              onTap: _toggleRecording,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _isRecording ? Colors.red : Colors.blue,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isRecording ? Icons.stop : Icons.mic,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
