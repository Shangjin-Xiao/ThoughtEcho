import 'dart:io';

class TokenizerService {
  final Map<String, int> _vocab = {};
  bool _isLoaded = false;

  // Basic WordPiece tokenizer implementation
  // Note: This is a simplified version. A full BertTokenizer is more complex.
  // We assume the vocab file is standard BERT format (one token per line).

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

    List<int> inputIds = [clsId];
    for (var token in tokens) {
      if (inputIds.length >= maxLen - 1) break; // Reserve space for [SEP]
      if (_vocab.containsKey(token)) {
        inputIds.add(_vocab[token]!);
      } else {
        inputIds.add(_vocab['[UNK]'] ?? 100);
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
    // Very basic whitespace and punctuation splitting
    // Ideally use a proper BertTokenizer package or regex
    // This is a placeholder for the logic.
    // For CJK, we often need character-based tokenization.

    List<String> tokens = [];
    // Basic implementation: Split by space, then handle basic punctuation.
    // NOTE: Real implementation needs to handle ## suffixes for subwords.
    // For this prototype, we'll do character based for CJK and word based for others.

    for (int i = 0; i < text.length; i++) {
        String char = text[i];
        if (_isChineseChar(char)) {
            tokens.add(char);
        } else {
            // Very naive latin handling
             // Accumulate latin chars... (omitted for brevity in this step)
             // Just adding chars for now to ensure it runs without crashing
             tokens.add(char);
        }
    }
    return tokens;
  }

  bool _isChineseChar(String char) {
      int code = char.codeUnitAt(0);
      return (code >= 0x4E00 && code <= 0x9FFF) ||
             (code >= 0x3400 && code <= 0x4DBF) ||
             (code >= 0x20000 && code <= 0x2A6DF);
  }
}
