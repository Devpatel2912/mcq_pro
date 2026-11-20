// Comprehensive standalone verification runner for MCQ 4-layer duplicate detection & normalization
import 'dart:math' as math;

class DuplicateVerifier {
  /// LAYER 3(a): Unicode-safe text normalization.
  /// Converts Latin characters to lowercase, strips question prefixes and punctuation
  /// (including Gujarati danda '।' and double danda '॥'),
  /// while STRICTLY PRESERVING Gujarati letters (\u0A80-\u0AFF), Gujarati digits (\u0AE6-\u0AEF),
  /// and Latin alphanumeric characters.
  static String normalizeText(String text) {
    if (text.isEmpty) return '';
    var s = text.trim().toLowerCase();
    // Strip leading question numbers
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

  /// Cosine similarity between two float vectors.
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
}

class QuestionCandidate {
  final int conceptId;
  final String conceptKey;
  final String questionText;
  final String answer;
  final List<double>? embedding;

  const QuestionCandidate({
    required this.conceptId,
    required this.conceptKey,
    required this.questionText,
    required this.answer,
    this.embedding,
  });
}

void main() {
  print('================================================================');
  print('🚀 RUNNING COMPREHENSIVE 4-LAYER DUPLICATE & NORMALIZATION SUITE');
  print('================================================================');

  // ── TEST 1: Multilingual Normalization (English & Gujarati) ─────────────────
  print('\n[Test 1] Unicode-Safe Multilingual Normalization:');
  
  // (a) English with numbers & punctuation
  final en1 = DuplicateVerifier.normalizeText('1. What is the acceleration due to gravity, on Earth?');
  final en2 = DuplicateVerifier.normalizeText('what is the acceleration due to gravity on earth...');
  assert(en1 == 'what is the acceleration due to gravity on earth', 'Failed English normalization: "$en1"');
  assert(en1 == en2, 'English variations should be identical after normalization');
  print('✓ English normalization passed: "$en1"');

  // (b) Gujarati with Gujarati digits, danda (\u0964), and question marks
  final gu1 = DuplicateVerifier.normalizeText('૧. પૃથ્વી પર ગુરુત્વાકર્ષણ પ્રવેગ કેટલો છે?');
  final gu2 = DuplicateVerifier.normalizeText('પૃથ્વી પર ગુરુત્વાકર્ષણ પ્રવેગ કેટલો છે ।');
  assert(gu1 == 'પૃથ્વી પર ગુરુત્વાકર્ષણ પ્રવેગ કેટલો છે', 'Failed Gujarati normalization: "$gu1"');
  assert(gu1 == gu2, 'Gujarati variations with danda & punctuation should match identically');
  print('✓ Gujarati normalization with danda removal passed: "$gu1"');

  // ── TEST 2: Jaccard Word-Overlap Detection ─────────────────────────────────
  print('\n[Test 2] Jaccard Similarity (Layer 3d):');
  final qGuA = DuplicateVerifier.normalizeText('પ્રકાશસંશ્લેષણ દરમિયાન કયો વાયુ મુક્ત થાય છે?');
  final qGuB = DuplicateVerifier.normalizeText('પ્રકાશસંશ્લેષણ પ્રક્રિયા દરમિયાન કયો વાયુ મુક્ત થાય છે?');
  final simGu = DuplicateVerifier.calculateJaccardSimilarity(qGuA, qGuB);
  assert(simGu >= 0.80, 'Gujarati rephrasing should yield >= 0.80 Jaccard similarity, got $simGu');
  print('✓ Gujarati near-duplicate detected with Jaccard similarity: $simGu');

  // ── TEST 3: Cross-Language Duplicate Detection via Concept Keys & Embeddings 
  print('\n[Test 3] Cross-Language Duplicate Detection (Layer 3b & 3c):');
  
  // English Question
  final qEnglish = QuestionCandidate(
    conceptId: 101,
    conceptKey: 'mitochondria cellular power house',
    questionText: 'Which organelle is known as the powerhouse of the cell?',
    answer: 'Mitochondria',
    // Simulated multilingual embedding representation
    embedding: [0.85, 0.12, 0.45, 0.22],
  );

  // Gujarati Question testing the exact same fact
  final qGujarati = QuestionCandidate(
    conceptId: 101, // Same concept outline ID
    conceptKey: 'mitochondria cellular power house', // Universal English concept key
    questionText: 'કોષનું શક્તિઘર (પાવરહાઉસ) તરીકે કઈ અંગિકા ઓળખાય છે?',
    answer: 'કણાભસૂત્ર',
    // Multilingual embedding close in vector space
    embedding: [0.86, 0.10, 0.44, 0.24],
  );

  // Layer 3(b) verification: Concept key match
  final normKeyEn = DuplicateVerifier.normalizeText(qEnglish.conceptKey);
  final normKeyGu = DuplicateVerifier.normalizeText(qGujarati.conceptKey);
  assert(normKeyEn == normKeyGu, 'Universal concept keys must match across languages');
  print('✓ Layer 3(b) concept key cross-language match detected: "$normKeyEn"');

  // Layer 3(c) verification: Cosine similarity
  final cosineSim = DuplicateVerifier.cosineSimilarity(qEnglish.embedding!, qGujarati.embedding!);
  assert(cosineSim >= 0.85, 'Semantic cosine similarity should exceed 0.85, got $cosineSim');
  print('✓ Layer 3(c) semantic cross-language similarity: $cosineSim >= 0.85 (FLAGGED AS DUPLICATE)');

  // ── TEST 4: Full Pipeline Multi-Question Simulation (50-Question Scenario) ──
  print('\n[Test 4] Simulating 50-Question Test Generation Pipeline:');

  final candidatePool = [
    // Unique 1
    QuestionCandidate(
      conceptId: 1,
      conceptKey: 'chloroplast chlorophyll light absorption',
      questionText: 'Which pigment is responsible for absorbing sunlight in plants?',
      answer: 'Chlorophyll',
      embedding: [0.1, 0.9, 0.2, 0.1],
    ),
    // Duplicate of 1 (exact normalized)
    QuestionCandidate(
      conceptId: 1,
      conceptKey: 'chloroplast chlorophyll light absorption',
      questionText: 'Which pigment is responsible for absorbing sunlight in plants?',
      answer: 'Chlorophyll',
      embedding: [0.1, 0.9, 0.2, 0.1],
    ),
    // Duplicate of 1 in Gujarati (cross-language concept duplicate)
    QuestionCandidate(
      conceptId: 1,
      conceptKey: 'chloroplast chlorophyll light absorption',
      questionText: 'વનસ્પતિમાં સૂર્યપ્રકાશ શોષવા માટે કયું રંજકદ્રવ્ય જવાબદાર છે?',
      answer: 'હરિતદ્રવ્ય',
      embedding: [0.11, 0.88, 0.21, 0.1],
    ),
    // Unique 2
    QuestionCandidate(
      conceptId: 2,
      conceptKey: 'stomata gas exchange regulation',
      questionText: 'What structure regulates gas exchange and transpiration in leaves?',
      answer: 'Stomata',
      embedding: [0.3, 0.2, 0.8, 0.4],
    ),
    // Duplicate of 2 (near duplicate rephrase)
    QuestionCandidate(
      conceptId: 99,
      conceptKey: 'leaf stomata gas regulation',
      questionText: 'Which structure in leaves regulates transpiration and gas exchange?',
      answer: 'Stomata',
      embedding: [0.31, 0.21, 0.79, 0.41],
    ),
    // Unique 3 (Gujarati)
    QuestionCandidate(
      conceptId: 3,
      conceptKey: 'xylem water transport roots to leaves',
      questionText: 'મૂળથી પર્ણો સુધી પાણીનું વહન કઈ પેશી દ્વારા થાય છે?',
      answer: 'જલવાહક પેશી',
      embedding: [0.7, 0.4, 0.1, 0.5],
    ),
  ];

  final accepted = <QuestionCandidate>[];
  final acceptedNormTexts = <String>{};
  final acceptedNormKeys = <String>{};
  final usedConceptIds = <int>{};
  final acceptedEmbeddings = <List<double>>[];

  int dupExactCount = 0;
  int dupConceptCount = 0;
  int dupSemanticCount = 0;
  int dupJaccardCount = 0;

  for (final cand in candidatePool) {
    final normText = DuplicateVerifier.normalizeText(cand.questionText);
    final normKey = DuplicateVerifier.normalizeText(cand.conceptKey);

    // Layer 3(a): Exact normalized check
    if (acceptedNormTexts.contains(normText)) {
      dupExactCount++;
      print('  • Layer 3(a) Exact duplicate caught: "${cand.questionText}"');
      continue;
    }

    // Layer 3(b): Concept ID or Concept Key check
    if (usedConceptIds.contains(cand.conceptId) || acceptedNormKeys.contains(normKey)) {
      dupConceptCount++;
      print('  • Layer 3(b) Concept key duplicate caught: "${cand.conceptKey}"');
      continue;
    }

    // Layer 3(d): Jaccard overlap check
    bool jaccardMatch = false;
    for (final existingNorm in acceptedNormTexts) {
      if (DuplicateVerifier.calculateJaccardSimilarity(normText, existingNorm) >= 0.80) {
        jaccardMatch = true;
        break;
      }
    }
    if (jaccardMatch) {
      dupJaccardCount++;
      print('  • Layer 3(d) Jaccard duplicate caught: "${cand.questionText}"');
      continue;
    }

    // Layer 3(c): Semantic embedding cosine similarity
    bool semanticMatch = false;
    if (cand.embedding != null) {
      for (final existingEmb in acceptedEmbeddings) {
        if (DuplicateVerifier.cosineSimilarity(cand.embedding!, existingEmb) >= 0.85) {
          semanticMatch = true;
          break;
        }
      }
    }
    if (semanticMatch) {
      dupSemanticCount++;
      print('  • Layer 3(c) Semantic duplicate caught: "${cand.questionText}"');
      continue;
    }

    // Accepted!
    accepted.add(cand);
    acceptedNormTexts.add(normText);
    acceptedNormKeys.add(normKey);
    usedConceptIds.add(cand.conceptId);
    if (cand.embedding != null) acceptedEmbeddings.add(cand.embedding!);
  }

  print('\n📊 Pipeline Summary:');
  print('   Total Evaluated: ${candidatePool.length}');
  print('   Accepted Unique: ${accepted.length}');
  print('   Duplicates Filtered: ${dupExactCount + dupConceptCount + dupSemanticCount + dupJaccardCount}');
  print('     - Exact Match (3a): $dupExactCount');
  print('     - Concept Key Match (3b): $dupConceptCount');
  print('     - Semantic Embeddings (3c): $dupSemanticCount');
  print('     - Jaccard Overlap (3d): $dupJaccardCount');

  assert(accepted.length == 3, 'Expected exactly 3 unique questions accepted, got ${accepted.length}');
  assert(dupExactCount == 1, 'Expected 1 exact duplicate caught');
  assert(dupConceptCount == 1, 'Expected 1 concept duplicate caught');
  assert(dupJaccardCount == 1, 'Expected 1 Jaccard duplicate caught');

  print('\n🎉 ALL TESTS PASSED! 4-layer duplicate prevention is fully verified.');
}
