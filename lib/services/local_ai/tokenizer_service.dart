import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../utils/app_logger.dart';

/// Tokenized 输入结构
class TokenizedInput {
  /// Token IDs
  final List<int> inputIds;
  
  /// Attention mask (1 表示有效 token, 0 表示 padding)
  final List<int> attentionMask;
  
  /// Token type IDs (用于区分句子)
  final List<int> tokenTypeIds;
  
  /// 原始 tokens
  final List<String> tokens;

  const TokenizedInput({
    required this.inputIds,
    required this.attentionMask,
    required this.tokenTypeIds,
    required this.tokens,
  });

  /// 获取序列长度
  int get length => inputIds.length;

  /// 转换为模型输入格式
  Map<String, List<List<int>>> toModelInput() {
    return {
      'input_ids': [inputIds],
      'attention_mask': [attentionMask],
      'token_type_ids': [tokenTypeIds],
    };
  }

  @override
  String toString() {
    return 'TokenizedInput(length: $length, tokens: $tokens)';
  }
}

/// WordPiece Tokenizer 服务
/// 
/// 实现 BERT 风格的 WordPiece 分词
class TokenizerService extends ChangeNotifier {
  static final TokenizerService _instance = TokenizerService._internal();
  factory TokenizerService() => _instance;
  TokenizerService._internal();

  /// 词汇表: token -> id
  Map<String, int> _vocab = {};
  
  /// 反向词汇表: id -> token
  Map<int, String> _idToToken = {};
  
  /// 是否已加载词汇表
  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  /// 特殊标记
  static const String padToken = '[PAD]';
  static const String unkToken = '[UNK]';
  static const String clsToken = '[CLS]';
  static const String sepToken = '[SEP]';
  static const String maskToken = '[MASK]';

  /// 特殊标记 ID
  int get padTokenId => _vocab[padToken] ?? 0;
  int get unkTokenId => _vocab[unkToken] ?? 100;
  int get clsTokenId => _vocab[clsToken] ?? 101;
  int get sepTokenId => _vocab[sepToken] ?? 102;
  int get maskTokenId => _vocab[maskToken] ?? 103;

  /// 词汇表大小
  int get vocabSize => _vocab.length;

  /// 从文件加载词汇表
  /// 
  /// 词汇表格式: 每行一个 token
  Future<void> loadVocab(String vocabPath, {bool isAsset = false}) async {
    try {
      String vocabContent;
      
      if (isAsset) {
        vocabContent = await rootBundle.loadString(vocabPath);
      } else {
        final file = File(vocabPath);
        if (!await file.exists()) {
          throw FileSystemException('词汇表文件不存在', vocabPath);
        }
        vocabContent = await file.readAsString();
      }

      _parseVocab(vocabContent);
      _isLoaded = true;
      
      logInfo(
        '词汇表加载成功, 词汇量: ${_vocab.length}',
        source: 'TokenizerService',
      );
      notifyListeners();
    } catch (e, stackTrace) {
      logError(
        '加载词汇表失败: $e',
        error: e,
        stackTrace: stackTrace,
        source: 'TokenizerService',
      );
      rethrow;
    }
  }

  /// 从 JSON 格式加载词汇表
  Future<void> loadVocabFromJson(String jsonPath, {bool isAsset = false}) async {
    try {
      String jsonContent;
      
      if (isAsset) {
        jsonContent = await rootBundle.loadString(jsonPath);
      } else {
        final file = File(jsonPath);
        if (!await file.exists()) {
          throw FileSystemException('词汇表 JSON 文件不存在', jsonPath);
        }
        jsonContent = await file.readAsString();
      }

      final Map<String, dynamic> vocabJson = json.decode(jsonContent);
      _vocab = vocabJson.map((key, value) => MapEntry(key, value as int));
      _idToToken = _vocab.map((key, value) => MapEntry(value, key));
      _isLoaded = true;
      
      logInfo(
        '词汇表 JSON 加载成功, 词汇量: ${_vocab.length}',
        source: 'TokenizerService',
      );
      notifyListeners();
    } catch (e, stackTrace) {
      logError(
        '加载词汇表 JSON 失败: $e',
        error: e,
        stackTrace: stackTrace,
        source: 'TokenizerService',
      );
      rethrow;
    }
  }

  /// 解析词汇表内容
  void _parseVocab(String content) {
    _vocab.clear();
    _idToToken.clear();
    
    final lines = content.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final token = lines[i].trim();
      if (token.isNotEmpty) {
        _vocab[token] = i;
        _idToToken[i] = token;
      }
    }
  }

  /// 对文本进行分词
  /// 
  /// [text] 输入文本
  /// [maxLength] 最大序列长度 (默认 512)
  /// [addSpecialTokens] 是否添加 [CLS] 和 [SEP] 标记
  /// [padding] 是否进行 padding
  /// [truncation] 是否截断超长序列
  TokenizedInput encode(
    String text, {
    int maxLength = 512,
    bool addSpecialTokens = true,
    bool padding = true,
    bool truncation = true,
  }) {
    if (!_isLoaded) {
      throw StateError('词汇表未加载，请先调用 loadVocab');
    }

    // 1. 基础分词
    final tokens = _tokenize(text);
    
    // 2. 转换为 WordPiece tokens
    final wordPieceTokens = _wordPieceTokenize(tokens);
    
    // 3. 添加特殊标记
    List<String> finalTokens;
    if (addSpecialTokens) {
      finalTokens = [clsToken, ...wordPieceTokens, sepToken];
    } else {
      finalTokens = wordPieceTokens;
    }
    
    // 4. 截断
    if (truncation && finalTokens.length > maxLength) {
      finalTokens = finalTokens.sublist(0, maxLength);
      // 确保结尾有 [SEP]
      if (addSpecialTokens && finalTokens.last != sepToken) {
        finalTokens[finalTokens.length - 1] = sepToken;
      }
    }
    
    // 5. 转换为 ID
    final inputIds = finalTokens.map((t) => _vocab[t] ?? unkTokenId).toList();
    
    // 6. 创建 attention mask
    final attentionMask = List.filled(inputIds.length, 1);
    
    // 7. 创建 token type IDs (单句情况全为 0)
    final tokenTypeIds = List.filled(inputIds.length, 0);
    
    // 8. Padding
    if (padding && inputIds.length < maxLength) {
      final padLength = maxLength - inputIds.length;
      inputIds.addAll(List.filled(padLength, padTokenId));
      attentionMask.addAll(List.filled(padLength, 0));
      tokenTypeIds.addAll(List.filled(padLength, 0));
    }
    
    return TokenizedInput(
      inputIds: inputIds,
      attentionMask: attentionMask,
      tokenTypeIds: tokenTypeIds,
      tokens: finalTokens,
    );
  }

  /// 批量编码
  List<TokenizedInput> encodeBatch(
    List<String> texts, {
    int maxLength = 512,
    bool addSpecialTokens = true,
    bool padding = true,
    bool truncation = true,
  }) {
    return texts.map((text) => encode(
      text,
      maxLength: maxLength,
      addSpecialTokens: addSpecialTokens,
      padding: padding,
      truncation: truncation,
    )).toList();
  }

  /// 将 token IDs 解码为文本
  String decode(List<int> tokenIds, {bool skipSpecialTokens = true}) {
    if (!_isLoaded) {
      throw StateError('词汇表未加载，请先调用 loadVocab');
    }

    final tokens = tokenIds
        .map((id) => _idToToken[id] ?? unkToken)
        .where((token) {
          if (skipSpecialTokens) {
            return token != padToken &&
                   token != unkToken &&
                   token != clsToken &&
                   token != sepToken &&
                   token != maskToken;
          }
          return true;
        })
        .toList();

    return _detokenize(tokens);
  }

  /// 基础分词 - 按空格和标点分割
  List<String> _tokenize(String text) {
    // 预处理: 清理和规范化文本
    text = text.toLowerCase().trim();
    
    // 使用正则分割: 保留单词、数字和中文字符
    final pattern = RegExp(
      r"[\u4e00-\u9fff]|[a-z]+|[0-9]+|[^\s\w\u4e00-\u9fff]+",
      caseSensitive: false,
    );
    
    final matches = pattern.allMatches(text);
    return matches.map((m) => m.group(0)!).toList();
  }

  /// WordPiece 分词
  List<String> _wordPieceTokenize(List<String> tokens) {
    final result = <String>[];
    
    for (final token in tokens) {
      if (_vocab.containsKey(token)) {
        result.add(token);
        continue;
      }
      
      // WordPiece 子词分割
      final subTokens = _splitWordPiece(token);
      result.addAll(subTokens);
    }
    
    return result;
  }

  /// 将单词分割为 WordPiece 子词
  List<String> _splitWordPiece(String word) {
    if (word.isEmpty) return [];
    
    // 对于中文字符，每个字符独立处理
    if (_isChinese(word)) {
      return word.split('').map((char) {
        return _vocab.containsKey(char) ? char : unkToken;
      }).toList();
    }
    
    final tokens = <String>[];
    var start = 0;
    
    while (start < word.length) {
      var end = word.length;
      String? foundToken;
      
      while (start < end) {
        var substr = word.substring(start, end);
        if (start > 0) {
          substr = '##$substr';
        }
        
        if (_vocab.containsKey(substr)) {
          foundToken = substr;
          break;
        }
        end--;
      }
      
      if (foundToken == null) {
        // 找不到匹配的子词，使用 [UNK]
        tokens.add(unkToken);
        start++;
      } else {
        tokens.add(foundToken);
        start = end;
      }
    }
    
    return tokens;
  }

  /// 反向分词 - 将 tokens 合并为文本
  String _detokenize(List<String> tokens) {
    final buffer = StringBuffer();
    
    for (var i = 0; i < tokens.length; i++) {
      var token = tokens[i];
      
      // 处理 WordPiece 前缀
      if (token.startsWith('##')) {
        buffer.write(token.substring(2));
      } else {
        if (i > 0 && !_isChinese(token) && !_isChinese(tokens[i - 1])) {
          buffer.write(' ');
        }
        buffer.write(token);
      }
    }
    
    return buffer.toString().trim();
  }

  /// 检查字符是否为中文
  bool _isChinese(String text) {
    return RegExp(r'[\u4e00-\u9fff]').hasMatch(text);
  }

  /// 获取 token 对应的 ID
  int? getTokenId(String token) => _vocab[token];

  /// 获取 ID 对应的 token
  String? getToken(int id) => _idToToken[id];

  /// 清除词汇表
  void clear() {
    _vocab.clear();
    _idToToken.clear();
    _isLoaded = false;
    notifyListeners();
  }
}
