-- ============================================================================
-- Migration: Add title column to public.tests
-- Allows teachers to provide an optional custom Test Title (e.g., "Weekly Test - 1")
-- to appear on generated question paper PDFs instead of the raw syllabus topic.
-- ============================================================================

ALTER TABLE public.tests ADD COLUMN IF NOT EXISTS title TEXT;
