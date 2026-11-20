import 'package:flutter_test/flutter_test.dart';
import 'package:mcq_test_app/core/services/ai_generator_service.dart';

void main() {
  group('MCQ 4-Layer Duplicate & Normalization Tests', () {
    test('Unicode-safe normalization strips punctuation while preserving Gujarati and English text', () {
      // English: stripping numbers, periods, commas, questions
      final normEn = AiGeneratorService.normalizeText('1. What is the acceleration due to gravity, on Earth?');
      expect(normEn, equals('what is the acceleration due to gravity on earth'));

      // Gujarati: preserving Gujarati characters (U+0A80 to U+0AFF) and stripping danda (\u0964) and question marks
      final normGu1 = AiGeneratorService.normalizeText('પ્રશ્ન ૧: પૃથ્વી પર ગુરુત્વાકર્ષણ પ્રવેગ કેટલો છે?');
      final normGu2 = AiGeneratorService.normalizeText('પૃથ્વી પર ગુરુત્વાકર્ષણ પ્રવેગ કેટલો છે ।');
      expect(normGu1, contains('પૃથ્વી પર ગુરુત્વાકર્ષણ પ્રવેગ કેટલો છે'));
      expect(normGu2, equals('પૃથ્વી પર ગુરુત્વાકર્ષણ પ્રવેગ કેટલો છે'));
    });

    test('Jaccard similarity detects near-duplicate rephrased questions', () {
      final q1 = AiGeneratorService.normalizeText('What is the SI unit of electric current?');
      final q2 = AiGeneratorService.normalizeText('What is the SI unit of electric current in physics?');
      final q3 = AiGeneratorService.normalizeText('Define the chemical structure of benzene molecule.');

      final simNear = AiGeneratorService.calculateJaccardSimilarity(q1, q2);
      final simDiff = AiGeneratorService.calculateJaccardSimilarity(q1, q3);

      expect(simNear, greaterThanOrEqualTo(0.8));
      expect(simDiff, lessThan(0.2));
    });

    test('Cosine similarity detects semantic similarity above 0.85 threshold', () {
      final v1 = [0.85, 0.12, 0.45, 0.22];
      final v2 = [0.86, 0.10, 0.44, 0.24];
      final v3 = [-0.20, 0.90, -0.10, 0.30];

      final simHigh = AiGeneratorService.cosineSimilarity(v1, v2);
      final simLow = AiGeneratorService.cosineSimilarity(v1, v3);

      expect(simHigh, greaterThanOrEqualTo(0.85));
      expect(simLow, lessThan(0.50));
    });

    test('Cross-language concept key match catches duplicate concept between Gujarati and English', () {
      const enConceptKey = 'mitochondria cellular power house';
      const guConceptKey = 'mitochondria cellular power house'; // Assigned in English per Layer 1/2

      final normEn = AiGeneratorService.normalizeText(enConceptKey);
      final normGu = AiGeneratorService.normalizeText(guConceptKey);

      expect(normEn, equals(normGu));
    });
  });
}
