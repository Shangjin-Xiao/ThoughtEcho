import 'dart:io';

class TokenizerService {
  final Map<String, int> _vocab = {};
  bool _isLoaded = false;

  // Basic WordPiece tokenizer implementation
  Future<void> loadVocab(String vocabPath) async {
    if (_isLoaded) return;

    try {
      final file = File(vocabPath);
      final lines = await file.readAsLines();
      for (int i = 0; i < lines.length; i++) {
        _vocab[lines[i]] = i;
      }
      _isLoaded = true;
    } catch (e) {
      print('Error loading vocab: $e');
      rethrow;
    }
  }

  Map<String, List<int>> encode(String text, {int maxLen = 128}) {
    if (!_isLoaded) {
      throw Exception('Vocab not loaded');
    }

    final tokens = _tokenize(text);
    // Add [CLS] and [SEP]
    final clsId = _vocab['[CLS]'] ?? 101;
    final sepId = _vocab['[SEP]'] ?? 102;
    final unkId = _vocab['[UNK]'] ?? 100;

    List<int> inputIds = [clsId];
    for (var token in tokens) {
      if (inputIds.length >= maxLen - 1) break; // Reserve space for [SEP]

      // Try to find token in vocab
      if (_vocab.containsKey(token)) {
        inputIds.add(_vocab[token]!);
      } else {
        // Simple subword fallback (WordPiece) not fully implemented here
        // We just use UNK for unknown words in this simplified version
        // To do it properly, we'd need to greedy match subwords from vocab
        inputIds.add(unkId);
      }
    }
    inputIds.add(sepId);

    // Padding
    List<int> attentionMask = List.filled(inputIds.length, 1);
    while (inputIds.length < maxLen) {
      inputIds.add(0); // [PAD]
      attentionMask.add(0);
    }

    // Type IDs (Segment IDs) - all 0 for single sentence
    List<int> tokenTypeIds = List.filled(maxLen, 0);

    return {
      'input_ids': inputIds,
      'attention_mask': attentionMask,
      'token_type_ids': tokenTypeIds,
    };
  }

  List<String> _tokenize(String text) {
    List<String> tokens = [];
    StringBuffer buffer = StringBuffer();

    void flushBuffer() {
      if (buffer.isNotEmpty) {
        // Lowercase and split latin text
        final word = buffer.toString().toLowerCase();
        // Here we could implement proper WordPiece splitting
        // For now, assume strict word matching or treat as unknown
        tokens.add(word);
        buffer.clear();
      }
    }

    for (int i = 0; i < text.length; i++) {
      String char = text[i];
      if (_isChineseChar(char)) {
        flushBuffer();
        tokens.add(char);
      } else if (_isWhitespace(char)) {
        flushBuffer();
      } else if (_isPunctuation(char)) {
         flushBuffer();
         tokens.add(char);
      } else {
        buffer.write(char);
      }
    }
    flushBuffer();

    // Apply MaxMatch WordPiece logic if needed, but for now strict word splitting
    // plus character splitting for CJK is a huge improvement over character-only
    return tokens;
  }

  bool _isChineseChar(String char) {
      int code = char.codeUnitAt(0);
      return (code >= 0x4E00 && code <= 0x9FFF) ||
             (code >= 0x3400 && code <= 0x4DBF) ||
             (code >= 0x20000 && code <= 0x2A6DF);
  }

  bool _isWhitespace(String char) {
    return char.trim().isEmpty;
  }

  bool _isPunctuation(String char) {
    final code = char.codeUnitAt(0);
    // Basic ASCII punctuation check
    if ((code >= 33 && code <= 47) ||
        (code >= 58 && code <= 64) ||
        (code >= 91 && code <= 96) ||
        (code >= 123 && code <= 126)) return true;
    // CJK punctuation (simplified)
    if (code >= 0x3000 && code <= 0x303F) return true;
    return false;
  }
}
