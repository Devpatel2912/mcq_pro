-- ============================================================================
-- Migration: Prevent Duplicate Questions Per Test
-- Ensures that identical or trimmed/lowercase questions cannot be accidentally
-- inserted multiple times for the same test_id.
-- ============================================================================

CREATE UNIQUE INDEX IF NOT EXISTS idx_questions_test_id_question_text_unique
ON public.questions (test_id, md5(lower(trim(question_text))));
