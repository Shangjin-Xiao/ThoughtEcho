import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/ai/cactus_service.dart';
import '../../gen_l10n/app_localizations.dart';

class VoiceRecordDialog extends StatefulWidget {
  const VoiceRecordDialog({super.key});

  @override
  State<VoiceRecordDialog> createState() => _VoiceRecordDialogState();
}

class _VoiceRecordDialogState extends State<VoiceRecordDialog> {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isProcessing = false;
  String _statusText = '';
  String _recordingPath = '';

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    final l10n = AppLocalizations.of(context);

    try {
      if (_isRecording) {
        // Stop recording
        final path = await _recorder.stop();
        if (path != null) {
          setState(() {
            _isRecording = false;
            _recordingPath = path;
            _statusText = l10n.voiceTranscribing;
            _isProcessing = true;
          });
          await _transcribe();
        }
      } else {
        // Ensure STT is initialized before recording.
        final cactus = Provider.of<CactusService>(context, listen: false);
        await cactus.ensureInitialized(lm: false, stt: true, rag: false);

        // Start recording
        if (await _recorder.hasPermission()) {
          final directory = await getTemporaryDirectory();
          final path =
              '${directory.path}/audio_${DateTime.now().millisecondsSinceEpoch}.wav';

          // Use WAV to improve offline STT compatibility.
          await _recorder.start(
            const RecordConfig(
              encoder: AudioEncoder.wav,
              sampleRate: 16000,
              numChannels: 1,
            ),
            path: path,
          );

          setState(() {
            _isRecording = true;
            _statusText = l10n.voiceRecording;
          });
        } else {
          setState(() {
            _statusText = l10n.startFailed(l10n.permissionText);
          });
        }
      }
    } catch (e) {
      setState(() {
        _isRecording = false;
        _statusText = l10n.startFailed(e.toString());
        _isProcessing = false;
      });
    }
  }

  Future<void> _transcribe() async {
    final l10n = AppLocalizations.of(context);
    try {
      final cactus = Provider.of<CactusService>(context, listen: false);
      final text = await cactus.transcribe(_recordingPath);

      if (mounted) {
        Navigator.pop(context, text);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusText = l10n.startFailed(e.toString());
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final displayStatus =
        _statusText.isEmpty ? l10n.voiceRecordingHint : _statusText;

    return AlertDialog(
      title: Text(l10n.voiceInputTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(displayStatus),
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
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}
