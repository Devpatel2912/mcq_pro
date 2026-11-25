import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'package:mcq_test_app/core/services/reaction_diagram_service.dart';
import 'package:mcq_test_app/core/utils/scientific_formatter.dart';
import 'package:mcq_test_app/models/question.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Represents a distinct concept in the Layer 1 concept outline.
class ConceptItem {
  final int id;
  final String concept;

  const ConceptItem({required this.id, required this.concept});

  factory ConceptItem.fromMap(Map<String, dynamic> map) {
    return ConceptItem(
      id: (map['id'] is num) ? (map['id'] as num).toInt() : int.tryParse(map['id']?.toString() ?? '0') ?? 0,
      concept: (map['concept'] ?? map['description'] ?? '').toString().trim(),
    );
  }

  Map<String, dynamic> toMap() => {'id': id, 'concept': concept};
}

class AiGeneratorService {
  static const int _batchSize = 5;
  static const int _maxRetries = 2;

  int _estimatedTokensUsed = 0;
  int get estimatedTokensUsed => _estimatedTokensUsed;
  void resetTokenCount() => _estimatedTokensUsed = 0;

  /// Determines whether to route calls to OpenAI or Google Gemini.
  /// Keys starting with 'AIza' are strictly Google Gemini keys.
  /// Keys starting with 'sk-' are strictly OpenAI keys.
  static bool shouldUseOpenAi({required String apiKey, required String modelName}) {
    final cleanKey = apiKey.trim();
    if (cleanKey.startsWith('AIza')) {
      return false; // Strictly Google Gemini
    }
    if (cleanKey.startsWith('sk-')) {
      return true; // Strictly OpenAI
    }
    if (modelName.toLowerCase().contains('gemini')) {
      return false; // Gemini model selected
    }
    return modelName.toLowerCase().startsWith('gpt');
  }

  Future<bool> verifyApiKey(String apiKey, {String modelName = 'gemini-2.5-flash'}) async {
    final cleanKey = apiKey.trim();
    if (cleanKey.isEmpty) return false;

    if (shouldUseOpenAi(apiKey: cleanKey, modelName: modelName)) {
      try {
        final url = Uri.parse('https://api.openai.com/v1/models');
        final res = await http.get(url, headers: {
          'Authorization': 'Bearer $cleanKey',
        }).timeout(const Duration(seconds: 10));
        return res.statusCode == 200;
      } catch (_) {
        return false;
      }
    }

    try {
      final geminiModel = modelName.toLowerCase().contains('gemini') ? modelName : 'gemini-2.5-flash';
      final model = GenerativeModel(
        model: geminiModel,
        apiKey: cleanKey,
      );
      final response = await model.generateContent([Content.text('Hi')]).timeout(const Duration(seconds: 10));
      return response.text != null && response.text!.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // ── Error Helpers ──────────────────────────────────────────────────────────

  bool _isModelNotAvailableError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('not found') ||
        msg.contains('404') ||
        msg.contains('unsupported') ||
        msg.contains('is not found');
  }

  bool _isQuotaOrRateLimitError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('quota exceeded') ||
        msg.contains('rate limit') ||
        msg.contains('resource_exhausted') ||
        msg.contains('429');
  }

  bool _isTransientError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('503') ||
        msg.contains('unavailable') ||
        msg.contains('500') ||
        msg.contains('internal') ||
        msg.contains('overloaded');
  }

  bool _shouldTryNextModel(Object error) =>
      _isModelNotAvailableError(error) ||
      _isQuotaOrRateLimitError(error) ||
      _isTransientError(error);

  List<String> _modelFallbackChain(String preferred) =>
      <String>[preferred, 'gemini-2.5-flash', 'gemini-2.5-flash-lite']
          .toSet()
          .toList();

  // ── JSON Helpers ───────────────────────────────────────────────────────────

  static dynamic decodeJsonObjectOrArray(String raw) {
    var text = raw.trim();
    text = text.replaceAll(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '');
    text = text.replaceAll(RegExp(r'\s*```$'), '').trim();

    try {
      return jsonDecode(text);
    } catch (_) {
      final sArr = text.indexOf('['), eArr = text.lastIndexOf(']');
      final sObj = text.indexOf('{'), eObj = text.lastIndexOf('}');
      if (sObj != -1 && eObj > sObj && (sArr == -1 || sObj < sArr)) {
        try {
          return jsonDecode(text.substring(sObj, eObj + 1));
        } catch (_) {}
      }
      if (sArr != -1 && eArr > sArr) {
        try {
          return jsonDecode(text.substring(sArr, eArr + 1));
        } catch (_) {}
      }
    }
    throw const FormatException('AI model did not return valid JSON.');
  }

  List<dynamic> _decodeQuestionsJson(String raw) {
    final decoded = decodeJsonObjectOrArray(raw);
    if (decoded is List) return decoded;
    if (decoded is Map) {
      if (decoded['questions'] is List) {
        return decoded['questions'] as List;
      }
      return [decoded];
    }
    throw const FormatException('Expected a JSON array or object with a "questions" key.');
  }

  // ── Text Helpers & Normalization (Language-Safe) ────────────────────────────

  String _compactText(String input) => input
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  List<String> _splitTextIntoChunks(String text, int batchCount) {
    if (batchCount <= 1) return [text];
    final chunkSize = (text.length / batchCount).ceil();
    final chunks = <String>[];
    for (int i = 0; i < batchCount; i++) {
      final start = i * chunkSize;
      if (start >= text.length) break;
      chunks.add(text.substring(start, (start + chunkSize).clamp(0, text.length)));
    }
    return chunks;
  }

  /// LAYER 3(a): Unicode-safe text normalization.
  /// Converts Latin characters to lowercase, strips question prefixes and punctuation
  /// (including Gujarati danda '।' and double danda '॥'),
  /// while STRICTLY PRESERVING Gujarati letters (\u0A80-\u0AFF), Gujarati digits (\u0AE6-\u0AEF),
  /// Devanagari (\u0900-\u097F), and Latin alphanumeric characters.
  static String normalizeText(String text) {
    if (text.isEmpty) return '';
    var s = text.trim();
    // Lowercase Latin text
    s = s.toLowerCase();
    // Strip leading question labels like "1. ", "Q1: ", "પ્રશ્ન 1: "
    s = s.replaceAll(
      RegExp(r'^(?:q\s*\d+[\.\:\)]|\d+[\.\:\)]|પ્રશ્ન\s*\d+[\.\:\)]|प्रश्न\s*\d+[\.\:\)])\s*', caseSensitive: false),
      '',
    );
    // Explicitly remove Gujarati danda (\u0964, \u0965) and abbreviation signs
    s = s.replaceAll(RegExp(r'[\u0964\u0965\u0AF0]'), ' ');
    // Keep letters (Latin, Gujarati U+0A80-U+0AFF, Devanagari U+0900-U+097F), digits, and spaces,
    // removing all punctuation and symbols without stripping non-ASCII characters
    s = s.replaceAll(RegExp(r'[^\w\s\u0A80-\u0AFF\u0900-\u097F]+', unicode: true), ' ');
    // Collapse multi-spaces
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Backward-compatible alias for question text normalization.
  static String normalizeQuestionText(String text) => normalizeText(text);

  /// Calculates word-overlap Jaccard similarity between two normalized strings.
  static double calculateJaccardSimilarity(String text1, String text2) {
    final words1 = text1.split(' ').where((w) => w.trim().isNotEmpty).toSet();
    final words2 = text2.split(' ').where((w) => w.trim().isNotEmpty).toSet();
    if (words1.isEmpty || words2.isEmpty) return 0.0;

    final intersection = words1.intersection(words2).length;
    final union = words1.union(words2).length;
    if (union == 0) return 0.0;
    return intersection / union;
  }

  /// Cosine similarity calculation between two float embedding vectors.
  static double cosineSimilarity(List<double> v1, List<double> v2) {
    if (v1.length != v2.length || v1.isEmpty) return 0.0;
    double dot = 0.0;
    double norm1 = 0.0;
    double norm2 = 0.0;
    for (int i = 0; i < v1.length; i++) {
      dot += v1[i] * v2[i];
      norm1 += v1[i] * v1[i];
      norm2 += v2[i] * v2[i];
    }
    if (norm1 <= 0.0 || norm2 <= 0.0) return 0.0;
    return dot / (math.sqrt(norm1) * math.sqrt(norm2));
  }

  // ── Model → Question ───────────────────────────────────────────────────────

  Question _mapToQuestion(dynamic item, String testId) {
    Map<String, dynamic>? options;
    if (item['options'] is Map) {
      options = Map<String, dynamic>.from(item['options']);
    }
    final qText = (item['question'] ?? item['questionText'] ?? '').toString();
    final optA = (options?['A'] ?? options?['a'] ?? item['a'] ?? item['optionA'] ?? '').toString();
    final optB = (options?['B'] ?? options?['b'] ?? item['b'] ?? item['optionB'] ?? '').toString();
    final optC = (options?['C'] ?? options?['c'] ?? item['c'] ?? item['optionC'] ?? '').toString();
    final optD = (options?['D'] ?? options?['d'] ?? item['d'] ?? item['optionD'] ?? '').toString();
    var ans = (item['answer'] ?? item['correctAnswer'] ?? 'A').toString().toUpperCase().trim();
    if (ans.isNotEmpty && (ans.startsWith('(') || ans.endsWith(')'))) {
      ans = ans.replaceAll(RegExp(r'[\(\)]'), '').trim();
    }
    final correctAnswer = (ans.isNotEmpty && 'ABCD'.contains(ans[0])) ? ans[0] : 'A';
    final expl = (item['explanation'] ?? '').toString();

    return Question(
      id: '',
      testId: testId,
      questionText: ScientificFormatter.format(qText),
      imageUrl: item['image_url'] ?? item['image'],
      optionA: ScientificFormatter.format(optA),
      optionB: ScientificFormatter.format(optB),
      optionC: ScientificFormatter.format(optC),
      optionD: ScientificFormatter.format(optD),
      correctAnswer: correctAnswer,
      explanation: ScientificFormatter.format(expl),
    );
  }

  // ── LAYER 1: Concept Outline Generator (Always in English) ──────────────────

  Future<List<ConceptItem>> generateConceptOutline({
    required String topic,
    required String level,
    required String difficulty,
    required int count,
    required String apiKey,
    required String modelName,
    List<String> excludedConcepts = const [],
  }) async {
    final cleanKey = apiKey.trim();
    final useOpenAi = shouldUseOpenAi(apiKey: cleanKey, modelName: modelName);

    final excludeClause = excludedConcepts.isEmpty
        ? ''
        : '\nDo NOT include or overlap with any of these already used concepts:\n${excludedConcepts.map((c) => '- $c').join('\n')}';

    final prompt =
        'You are an expert exam setter. Topic: $topic. Level: $level. Difficulty: $difficulty. '
        'Create exactly $count DISTINCT, narrow concepts for an MCQ test. '
        'No two concepts may overlap, be sub-parts of each other, or be rephrasings of each other. '
        'Spread them across the entire syllabus. Write concepts in English.$excludeClause '
        'Return ONLY JSON: {"concepts":[{"id":1,"concept":"..."}]}';

    dynamic rawJson;
    if (useOpenAi) {
      final url = Uri.parse('https://api.openai.com/v1/chat/completions');
      final res = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Bearer $cleanKey',
        },
        body: jsonEncode({
          'model': modelName.startsWith('gpt') ? modelName : 'gpt-4o-mini',
          'temperature': 0.8,
          'frequency_penalty': 0.5,
          'presence_penalty': 0.5,
          'response_format': {'type': 'json_object'},
          'messages': [
            {
              'role': 'system',
              'content': 'You are an expert exam setter. Return valid JSON only, no extra text, no markdown.',
            },
            {
              'role': 'user',
              'content': prompt,
            },
          ],
        }),
      ).timeout(const Duration(seconds: 45));

      if (res.statusCode != 200) {
        throw Exception('Concept outline failed (${res.statusCode}): ${utf8.decode(res.bodyBytes)}');
      }

      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded['usage'] != null && decoded['usage']['total_tokens'] != null) {
        _estimatedTokensUsed += (decoded['usage']['total_tokens'] as num).toInt();
      }
      final content = decoded['choices']?[0]?['message']?['content'] ?? '{}';
      rawJson = decodeJsonObjectOrArray(content);
    } else {
      // Gemini
      final geminiModel = modelName.toLowerCase().contains('gemini') ? modelName : 'gemini-2.5-flash';
      final model = GenerativeModel(
        model: geminiModel,
        apiKey: cleanKey,
        systemInstruction: Content.system(
          'You are an expert exam setter. Return valid JSON only, no extra text, no markdown.',
        ),
        generationConfig: GenerationConfig(responseMimeType: 'application/json', temperature: 0.8),
      );
      final response = await model.generateContent([Content.text(prompt)]).timeout(const Duration(seconds: 45));
      rawJson = decodeJsonObjectOrArray(response.text ?? '{}');
    }

    final conceptsList = <ConceptItem>[];
    if (rawJson is Map && rawJson['concepts'] is List) {
      for (final item in rawJson['concepts']) {
        if (item is Map) {
          final c = ConceptItem.fromMap(Map<String, dynamic>.from(item));
          if (c.concept.isNotEmpty) conceptsList.add(c);
        }
      }
    }
    return conceptsList;
  }

  // ── LAYER 3(c): Batch Semantic Embeddings (text-embedding-3-small) ──────────

  Future<List<List<double>>> _getOpenAiEmbeddings({
    required List<String> inputs,
    required String apiKey,
  }) async {
    if (inputs.isEmpty) return [];
    try {
      final url = Uri.parse('https://api.openai.com/v1/embeddings');
      final res = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'text-embedding-3-small',
          'input': inputs,
        }),
      ).timeout(const Duration(seconds: 30));

      if (res.statusCode != 200) {
        debugPrint('⚠️ OpenAI Embeddings error (${res.statusCode}): ${res.body}');
        return [];
      }

      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      final data = decoded['data'] as List?;
      if (data == null) return [];

      final results = <List<double>>[];
      for (final item in data) {
        final emb = (item['embedding'] as List).map((n) => (n as num).toDouble()).toList();
        results.add(emb);
      }
      return results;
    } catch (e) {
      debugPrint('⚠️ Embeddings API call failed, skipping semantic layer: $e');
      return [];
    }
  }

  // ── API Invocation: OpenAI Chat ─────────────────────────────────────────────

  Future<List<dynamic>> _callOpenAi({
    required String prompt,
    required String apiKey,
    required String modelName,
  }) async {
    final url = Uri.parse('https://api.openai.com/v1/chat/completions');
    final response = await http
        .post(
          url,
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'model': modelName,
            'temperature': 0.8,
            'frequency_penalty': 0.5,
            'presence_penalty': 0.5,
            'response_format': {'type': 'json_object'},
            'messages': [
              {
                'role': 'system',
                'content':
                    'You are an expert exam setter and MCQ writer. Return valid JSON only, no extra text, no markdown.',
              },
              {
                'role': 'user',
                'content': prompt,
              },
            ],
          }),
        )
        .timeout(const Duration(seconds: 50));

    if (response.statusCode != 200) {
      final errBody = utf8.decode(response.bodyBytes);
      throw Exception('OpenAI API error (${response.statusCode}): $errBody');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final choices = decoded['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw Exception('No choices returned by OpenAI API.');
    }
    final content = choices[0]['message']?['content'] as String?;
    if (content == null || content.trim().isEmpty) {
      throw Exception('Empty content returned by OpenAI API.');
    }

    if (decoded['usage'] != null && decoded['usage']['total_tokens'] != null) {
      _estimatedTokensUsed += (decoded['usage']['total_tokens'] as num).toInt();
    }

    return _decodeQuestionsJson(content);
  }

  // ── API Invocation: Gemini ──────────────────────────────────────────────────

  Future<List<dynamic>> _callGemini({
    required String prompt,
    required String apiKey,
    required String modelName,
    List<int>? pdfBytes,
  }) async {
    final fallbacks = _modelFallbackChain(modelName);
    Object? lastError;

    for (final candidateModel in fallbacks) {
      try {
        final model = GenerativeModel(
          model: candidateModel,
          apiKey: apiKey,
          systemInstruction: Content.system(
            'You are an expert exam setter and MCQ writer. Return valid JSON only, no extra text, no markdown.',
          ),
          generationConfig: GenerationConfig(
            responseMimeType: 'application/json',
            temperature: 0.8,
          ),
        );

        final List<Part> parts = [];
        if (pdfBytes != null && pdfBytes.isNotEmpty) {
          parts.add(DataPart('application/pdf', Uint8List.fromList(pdfBytes)));
        }
        parts.add(TextPart(prompt));

        final response = await model.generateContent([Content.multi(parts)]).timeout(
          const Duration(seconds: 50),
        );
        final text = response.text;
        if (text == null || text.trim().isEmpty) {
          throw Exception('Empty response from AI model');
        }

        if (response.usageMetadata != null && response.usageMetadata!.totalTokenCount != null) {
          _estimatedTokensUsed += (response.usageMetadata!.totalTokenCount!).toInt();
        }

        return _decodeQuestionsJson(text);
      } catch (e) {
        lastError = e;
        if (_shouldTryNextModel(e) && candidateModel != fallbacks.last) {
          debugPrint('🔁 Switching from $candidateModel to next fallback...');
          continue;
        }
        rethrow;
      }
    }
    throw lastError ?? Exception('Gemini generation failed');
  }

  // ── PUBLIC: Generate from Topic (4-Layer Deduplication Engine) ──────────────

  Future<List<Question>> generateQuestions({
    required String subject,
    required String topic,
    required String level,
    required int count,
    required String testId,
    required String medium,
    required String apiKey,
    String? difficulty,
    String modelName = 'gpt-4o',
    void Function(int generatedSoFar)? onProgress,
  }) async {
    const int maxBatchSize = _batchSize; // 5 questions per call
    const int maxAttempts = 20;

    final cleanKey = apiKey.trim();
    final useOpenAi = shouldUseOpenAi(apiKey: cleanKey, modelName: modelName);

    // LAYER 4: Model Selection
    final isGujarati = medium.trim().toLowerCase() == 'gujarati';
    final activeModel = useOpenAi
        ? (isGujarati ? 'gpt-4o' : (modelName.startsWith('gpt') ? modelName : 'gpt-4o-mini'))
        : (modelName.toLowerCase().contains('gemini') ? modelName : 'gemini-2.5-flash');

    // Difficulty mapping
    final String diffStr;
    if (difficulty != null && difficulty.trim().isNotEmpty) {
      diffStr = difficulty.trim();
    } else {
      final lvl = level.toLowerCase();
      if (lvl.contains('jee') || lvl.contains('hard') || lvl.contains('advance')) {
        diffStr = 'Hard';
      } else if (lvl.contains('neet') || lvl.contains('medium')) {
        diffStr = 'Medium';
      } else {
        diffStr = 'Easy';
      }
    }

    // Counters for debug logging per run
    int totalApiCalls = 0;
    int dupExactCount = 0;
    int dupConceptCount = 0;
    int dupSemanticCount = 0;
    int dupJaccardCount = 0;

    // Tracking structures
    final acceptedQuestions = <Question>[];
    final acceptedNormalizedQuestions = <String>[];
    final acceptedNormalizedConceptKeys = <String>{};
    final usedConceptIds = <int>{};
    final acceptedEmbeddings = <List<double>>[];

    // ──────────────────────────────────────────────────────────────────────────
    // LAYER 1: Concept Outline (always in English, for both languages)
    // N + 20% spare concepts
    // ──────────────────────────────────────────────────────────────────────────
    final int initialConceptTarget = count + math.max(5, (count * 0.20).ceil());
    debugPrint('📋 [LAYER 1] Generating $initialConceptTarget distinct concepts in English for topic "$topic"...');

    List<ConceptItem> availableConcepts = [];
    try {
      totalApiCalls++;
      availableConcepts = await generateConceptOutline(
        topic: topic,
        level: level,
        difficulty: diffStr,
        count: initialConceptTarget,
        apiKey: cleanKey,
        modelName: activeModel,
      );
      debugPrint('✅ [LAYER 1] Received ${availableConcepts.length} distinct concepts.');
    } catch (e) {
      debugPrint('⚠️ [LAYER 1] Concept outline call failed: $e. Proceeding with adaptive generation.');
    }

    // Queue of concepts to consume
    final List<ConceptItem> unusedConcepts = List.from(availableConcepts);
    int nextConceptId = availableConcepts.isNotEmpty ? availableConcepts.last.id + 1 : 1;
    int attempt = 0;

    debugPrint('🚀 [LAYER 2] Beginning batch generation | Target: $count | Language: $medium | Model: $activeModel');

    while (acceptedQuestions.length < count && attempt < maxAttempts) {
      attempt++;
      final remaining = count - acceptedQuestions.length;
      final currentBatchSize = math.min(maxBatchSize, remaining);

      // Replenish concepts if spares ran out
      if (unusedConcepts.length < currentBatchSize) {
        debugPrint('🔄 Concepts depleted. Generating spare concepts...');
        try {
          totalApiCalls++;
          final moreConcepts = await generateConceptOutline(
            topic: topic,
            level: level,
            difficulty: diffStr,
            count: math.max(currentBatchSize + 5, 10),
            apiKey: cleanKey,
            modelName: activeModel,
            excludedConcepts: acceptedNormalizedConceptKeys.toList(),
          );
          unusedConcepts.addAll(moreConcepts);
        } catch (_) {}

        // Graceful stop if topic is too narrow
        if (unusedConcepts.isEmpty && acceptedQuestions.isNotEmpty) {
          debugPrint('⚠️ Topic cannot yield more unique concepts. Stopping gracefully.');
          break;
        }
      }

      // Assign exactly 1 unused concept to each question in this batch
      final batchAssignedConcepts = <ConceptItem>[];
      for (int i = 0; i < currentBatchSize; i++) {
        if (unusedConcepts.isNotEmpty) {
          batchAssignedConcepts.add(unusedConcepts.removeAt(0));
        } else {
          batchAssignedConcepts.add(ConceptItem(id: nextConceptId++, concept: 'Concept on $topic - aspect $attempt.$i'));
        }
      }

      final assignedConceptsStr = batchAssignedConcepts
          .map((c) => 'Concept ${c.id}: ${c.concept}')
          .join('\n');

      final previousQuestionsStr = acceptedQuestions.isEmpty
          ? '(If the list is empty, ignore this rule.)'
          : acceptedQuestions
              .asMap()
              .entries
              .map((e) => '${e.key + 1}. ${e.value.questionText}')
              .join('\n');

      final previousConceptKeysStr = acceptedNormalizedConceptKeys.isEmpty
          ? 'None'
          : acceptedNormalizedConceptKeys.join(', ');

      // ────────────────────────────────────────────────────────────────────────
      // LAYER 2: Question prompt template per batch
      // ────────────────────────────────────────────────────────────────────────
      final prompt = '''
You are an expert exam setter and MCQ writer. Return valid JSON only.

Topic: $topic
Class/Level: $level
Difficulty: $diffStr
Question language: $medium

LANGUAGE RULES:
- If language is "Gujarati": write the question, all 4 options and the explanation in correct, natural, textbook-quality Gujarati (Gujarati script). Use standard terminology used in Gujarat board textbooks. Do not mix in Hindi or English words unless it is a standard technical term or a formula/symbol.
- If language is "English": write everything in clear, simple, grammatically correct English.
- Never mix languages inside one question, except standard technical terms.

Write exactly $currentBatchSize MCQs. Write ONE question for EACH of these assigned concepts, and ONLY about that concept:
$assignedConceptsStr

STRICT RULES:
1. Each question tests ONLY its assigned concept. Never combine concepts.
2. NEVER repeat, rephrase or indirectly ask the same fact as any question in this ALREADY USED list (even in a different style, or in the other language):
$previousQuestionsStr
Concept keys already used: $previousConceptKeysStr
3. Within this batch, no two questions may test the same fact. The correct answer of one question must not appear as the answer or main clue of another question.
4. Exactly 4 options (A, B, C, D), exactly ONE correct. Wrong options must be plausible and similar in length. No "All of the above" or "None of the above".
5. Vary the style: definition, application, scenario, "which is NOT correct", calculation, comparison.
6. Distribute correct answers evenly across A, B, C, D.
7. Match difficulty: Easy = recall, Medium = understanding/application, Hard = analysis/multi-step.
8. Facts must be accurate and unambiguous. Add a one-line explanation in the question language.
9. For every question return "concept_key": a short ENGLISH phrase (3 to 8 words) naming the exact fact tested (even for Gujarati questions).

OUTPUT (ONLY this JSON):
{"questions":[{"concept_id":1,"concept_key":"string","question":"string","options":{"A":"string","B":"string","C":"string","D":"string"},"answer":"A","explanation":"string"}]}
The "questions" array must contain exactly $currentBatchSize items.
''';

      List<dynamic>? rawBatchItems;
      int retryCount = 0;
      while (retryCount <= _maxRetries && rawBatchItems == null) {
        try {
          totalApiCalls++;
          if (useOpenAi) {
            rawBatchItems = await _callOpenAi(
              prompt: prompt,
              apiKey: cleanKey,
              modelName: activeModel,
            );
          } else {
            rawBatchItems = await _callGemini(
              prompt: prompt,
              apiKey: cleanKey,
              modelName: activeModel,
            );
          }
        } catch (e) {
          retryCount++;
          debugPrint('⚠️ Batch attempt $attempt (retry $retryCount/$_maxRetries) failed: $e');
          if (retryCount > _maxRetries) {
            if (acceptedQuestions.isEmpty) {
              throw 'AI question generation failed after retries: $e';
            } else {
              break;
            }
          }
          await Future.delayed(Duration(milliseconds: 600 * retryCount));
        }
      }

      if (rawBatchItems == null || rawBatchItems.isEmpty) continue;

      // ────────────────────────────────────────────────────────────────────────
      // LAYER 3: Duplicate detection in code
      // ────────────────────────────────────────────────────────────────────────

      // Step A: Parse candidate questions and collect texts for semantic embeddings
      final candidateQuestions = <Question>[];
      final candidateConceptIds = <int>[];
      final candidateConceptKeys = <String>[];
      final candidateEmbedTexts = <String>[];
      final candidateRawItems = <dynamic>[];

      for (final item in rawBatchItems) {
        if (acceptedQuestions.length + candidateQuestions.length >= count) break;
        final q = _mapToQuestion(item, testId);
        if (q.questionText.trim().isEmpty) continue;

        final rawConceptId = item['concept_id'];
        final conceptId = (rawConceptId is num) ? rawConceptId.toInt() : int.tryParse(rawConceptId?.toString() ?? '0') ?? 0;
        final rawConceptKey = (item['concept_key'] ?? '').toString().trim();
        final normConceptKey = normalizeText(rawConceptKey);
        final normQText = normalizeText(q.questionText);

        // Check 3(a): Exact match
        if (normQText.isEmpty || acceptedNormalizedQuestions.contains(normQText)) {
          dupExactCount++;
          debugPrint('🧹 [LAYER 3a - Exact Match Discarded] "${q.questionText}"');
          continue;
        }

        // Check 3(b): Same concept_id or concept_key
        if ((conceptId > 0 && usedConceptIds.contains(conceptId)) ||
            (normConceptKey.isNotEmpty && acceptedNormalizedConceptKeys.contains(normConceptKey))) {
          dupConceptCount++;
          debugPrint('🧹 [LAYER 3b - Duplicate Concept Discarded] Key: "$rawConceptKey"');
          continue;
        }

        // Check 3(d): Word-overlap (Jaccard) above 0.8
        bool jaccardDup = false;
        for (final existingNorm in acceptedNormalizedQuestions) {
          if (calculateJaccardSimilarity(normQText, existingNorm) >= 0.80) {
            jaccardDup = true;
            break;
          }
        }
        if (jaccardDup) {
          dupJaccardCount++;
          debugPrint('🧹 [LAYER 3d - Jaccard Overlap Discarded] "${q.questionText}"');
          continue;
        }

        // Passed preliminary filters -> eligible for semantic embedding check
        candidateQuestions.add(q);
        candidateConceptIds.add(conceptId);
        candidateConceptKeys.add(normConceptKey);
        candidateRawItems.add(item);

        // Input for embedding: "question + correct answer text"
        final correctAnsText = q.correctAnswer == 'A'
            ? q.optionA
            : (q.correctAnswer == 'B' ? q.optionB : (q.correctAnswer == 'C' ? q.optionC : q.optionD));
        candidateEmbedTexts.add('${q.questionText} $correctAnsText');
      }

      // Step B: LAYER 3(c) Semantic Similarity via text-embedding-3-small
      List<List<double>> newEmbeddings = [];
      if (useOpenAi && candidateEmbedTexts.isNotEmpty && acceptedEmbeddings.isNotEmpty) {
        totalApiCalls++;
        newEmbeddings = await _getOpenAiEmbeddings(
          inputs: candidateEmbedTexts,
          apiKey: cleanKey,
        );
      }

      // Step C: Filter candidates by semantic similarity and accept
      for (int i = 0; i < candidateQuestions.length; i++) {
        if (acceptedQuestions.length >= count) break;
        final q = candidateQuestions[i];
        final normQText = normalizeText(q.questionText);
        final normCKey = candidateConceptKeys[i];
        final cId = candidateConceptIds[i];

        bool semanticDup = false;
        if (i < newEmbeddings.length && newEmbeddings[i].isNotEmpty) {
          final candEmb = newEmbeddings[i];
          for (final existingEmb in acceptedEmbeddings) {
            final sim = cosineSimilarity(candEmb, existingEmb);
            if (sim >= 0.85) {
              semanticDup = true;
              dupSemanticCount++;
              debugPrint('🧹 [LAYER 3c - Semantic Duplicate Discarded (Cosine: ${sim.toStringAsFixed(2)})] "${q.questionText}"');
              break;
            }
          }
        }

        if (semanticDup) continue;

        // Auto-generate chemical diagram if applicable
        Question finalQ = q;
        if (finalQ.imageUrl == null || finalQ.imageUrl!.isEmpty) {
          try {
            final rawItem = candidateRawItems[i];
            final reactionScheme = rawItem['reaction_scheme']?.toString() ??
                rawItem['diagram_scheme']?.toString() ??
                rawItem['reaction']?.toString();
            final textToParse = (reactionScheme != null && reactionScheme.trim().isNotEmpty)
                ? '$reactionScheme\n${finalQ.questionText}'
                : finalQ.questionText;
            final autoDiagram = await ReactionDiagramService.autoGenerateDiagramForQuestion(
              textToParse,
              finalQ.explanation,
            );
            if (autoDiagram != null) {
              finalQ = finalQ.copyWith(imageUrl: autoDiagram);
            }
          } catch (_) {}
        }

        acceptedQuestions.add(finalQ);
        acceptedNormalizedQuestions.add(normQText);
        if (normCKey.isNotEmpty) acceptedNormalizedConceptKeys.add(normCKey);
        if (cId > 0) usedConceptIds.add(cId);
        if (i < newEmbeddings.length && newEmbeddings[i].isNotEmpty) {
          acceptedEmbeddings.add(newEmbeddings[i]);
        }

        onProgress?.call(acceptedQuestions.length);
      }
    }

    // Comprehensive debug log per run
    debugPrint('═══════════════════════════════════════════════════════════════');
    debugPrint('📊 [MCQ Generation Report]');
    debugPrint('   Language: $medium (${isGujarati ? "Gujarati" : "English"})');
    debugPrint('   Model: $activeModel');
    debugPrint('   Target Requested: $count | Final Accepted: ${acceptedQuestions.length}');
    debugPrint('   Total API Calls: $totalApiCalls (Attempts: $attempt)');
    debugPrint('   Duplicates Removed by Layer:');
    debugPrint('     • Layer 3(a) Exact match: $dupExactCount');
    debugPrint('     • Layer 3(b) Duplicate concept: $dupConceptCount');
    debugPrint('     • Layer 3(c) Semantic similarity (>0.85): $dupSemanticCount');
    debugPrint('     • Layer 3(d) Jaccard token overlap (>0.80): $dupJaccardCount');
    debugPrint('     • Total Discarded: ${dupExactCount + dupConceptCount + dupSemanticCount + dupJaccardCount}');
    debugPrint('═══════════════════════════════════════════════════════════════');

    if (acceptedQuestions.length < count && acceptedQuestions.isNotEmpty) {
      debugPrint('ℹ️ Topic yield: generated ${acceptedQuestions.length} unique questions.');
    }

    return acceptedQuestions;
  }

  // ── PUBLIC: Generate from PDF ──────────────────────────────────────────────

  Future<List<Question>> generateQuestionsFromPdf({
    required String subject,
    required String topic,
    required String level,
    required int count,
    required String testId,
    required String medium,
    required List<int> pdfBytes,
    required String apiKey,
    String? difficulty,
    String modelName = 'gpt-4o',
    void Function(int generatedSoFar)? onProgress,
  }) async {
    const int maxBatchSize = _batchSize;
    final int maxAttempts = math.max((count / maxBatchSize).ceil() * 3 + 5, 25);

    String extractedText = '';
    try {
      final PdfDocument document = PdfDocument(inputBytes: pdfBytes);
      extractedText = PdfTextExtractor(document).extractText();
      document.dispose();
    } catch (e) {
      debugPrint('PDF text extractor note: $e');
    }

    final isTextEmpty = extractedText.trim().isEmpty;
    final compactedText = _compactText(extractedText);
    final textChunks = isTextEmpty ? [''] : _splitTextIntoChunks(compactedText, (count / maxBatchSize).ceil());
    final hintLine = topic.trim().isEmpty ? '' : '\nTopic hint: "$topic"';

    final cleanKey = apiKey.trim();
    final useOpenAi = shouldUseOpenAi(apiKey: cleanKey, modelName: modelName);
    final isGujarati = medium.trim().toLowerCase() == 'gujarati';
    final activeModel = useOpenAi
        ? (isGujarati ? 'gpt-4o' : (modelName.startsWith('gpt') ? modelName : 'gpt-4o-mini'))
        : (modelName.toLowerCase().contains('gemini') ? modelName : 'gemini-2.5-flash');

    final acceptedQuestions = <Question>[];
    final seenNormalizedSet = <String>{};
    final seenNormalizedList = <String>[];
    int duplicatesRemovedCount = 0;
    int attempt = 0;

    debugPrint('📄 [PDF MCQ Generation Started] Target: $count | Chars: ${compactedText.length} | Model: $activeModel');

    while (acceptedQuestions.length < count && attempt < maxAttempts) {
      attempt++;
      final remaining = count - acceptedQuestions.length;
      final currentBatchSize = remaining > maxBatchSize ? maxBatchSize : remaining;
      final pdfChunk = textChunks[(attempt - 1) % textChunks.length];

      final String previousQuestionsStr;
      if (acceptedQuestions.isEmpty) {
        previousQuestionsStr = '(If the list is empty, ignore this rule.)';
      } else {
        previousQuestionsStr = acceptedQuestions
            .asMap()
            .entries
            .map((e) => '${e.key + 1}. ${e.value.questionText}')
            .join('\n');
      }

      final prompt = '''
Create a multiple-choice test based strictly on the provided content:

Topic: $topic $hintLine
Subject: $subject
Class/Level: $level
Language: $medium
Number of questions to generate now: $currentBatchSize

LANGUAGE RULES:
- If language is "Gujarati": write in correct, standard Gujarati textbook terminology.
- If language is "English": write in clear, simple English.

PDF Content Chunk:
$pdfChunk

STEP 1 (do silently, do not output):
Plan $currentBatchSize completely different subtopics/concepts from the provided content.

STEP 2: Write the questions using these STRICT RULES:
1. UNIQUENESS: Every question must test a different concept. Never repeat or rephrase facts.
2. ALREADY USED: Do NOT repeat or paraphrase any question from this list:
$previousQuestionsStr
(If the list is empty, ignore this rule.)
3. Each question has exactly 4 options labeled A, B, C, D, with exactly ONE correct answer.
4. Wrong options must be plausible and similar in length and style to the correct one.
5. Distribute correct answers evenly across A, B, C, D.
6. Add a short one-line explanation for the correct answer.

OUTPUT FORMAT (return ONLY this JSON object):
{"questions":[{"subtopic":"string","question":"string","options":{"A":"string","B":"string","C":"string","D":"string"},"answer":"A","explanation":"string"}]}

The "questions" array must contain exactly $currentBatchSize items.
''';

      List<dynamic>? batchData;
      int retryCount = 0;
      while (retryCount <= _maxRetries && batchData == null) {
        try {
          if (useOpenAi) {
            batchData = await _callOpenAi(
              prompt: prompt,
              apiKey: cleanKey,
              modelName: activeModel,
            );
          } else {
            batchData = await _callGemini(
              prompt: prompt,
              apiKey: cleanKey,
              modelName: activeModel,
              pdfBytes: pdfBytes.length <= 15 * 1024 * 1024 ? pdfBytes : null,
            );
          }
        } catch (e) {
          retryCount++;
          debugPrint('⚠️ PDF batch attempt $attempt (retry $retryCount/$_maxRetries) failed: $e');
          if (retryCount > _maxRetries) {
            if (acceptedQuestions.isEmpty) {
              throw 'AI generation from PDF failed after retries: $e';
            } else {
              break;
            }
          }
          await Future.delayed(Duration(milliseconds: 500 * retryCount));
        }
      }

      if (batchData == null || batchData.isEmpty) continue;

      for (final item in batchData) {
        if (acceptedQuestions.length >= count) break;
        final q = _mapToQuestion(item, testId);
        if (q.questionText.trim().isEmpty) continue;

        final normalized = normalizeText(q.questionText);
        if (normalized.isEmpty || seenNormalizedSet.contains(normalized)) {
          duplicatesRemovedCount++;
          debugPrint('🧹 [PDF MCQ Duplicate Check] Removed duplicate: "${q.questionText}"');
          continue;
        }

        bool jaccardDup = false;
        for (final existing in seenNormalizedList) {
          if (calculateJaccardSimilarity(normalized, existing) >= 0.80) {
            jaccardDup = true;
            break;
          }
        }
        if (jaccardDup) {
          duplicatesRemovedCount++;
          continue;
        }

        Question finalQ = q;
        if (finalQ.imageUrl == null || finalQ.imageUrl!.isEmpty) {
          try {
            final reactionScheme = item['reaction_scheme']?.toString() ??
                item['diagram_scheme']?.toString() ??
                item['reaction']?.toString();
            final textToParse = (reactionScheme != null && reactionScheme.trim().isNotEmpty)
                ? '$reactionScheme\n${finalQ.questionText}'
                : finalQ.questionText;
            final autoDiagram = await ReactionDiagramService.autoGenerateDiagramForQuestion(
              textToParse,
              finalQ.explanation,
            );
            if (autoDiagram != null) {
              finalQ = finalQ.copyWith(imageUrl: autoDiagram);
            }
          } catch (_) {}
        }

        acceptedQuestions.add(finalQ);
        seenNormalizedSet.add(normalized);
        seenNormalizedList.add(normalized);
        onProgress?.call(acceptedQuestions.length);
      }
    }

    debugPrint(
      '📊 [PDF Generation Summary] Requested: $count | Accepted: ${acceptedQuestions.length} | Duplicates removed: $duplicatesRemovedCount | Total attempts: $attempt',
    );

    return acceptedQuestions;
  }
}
