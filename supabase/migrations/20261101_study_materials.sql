-- ============================================================================
-- Migration: Study Materials & Resource Links (Drive, YouTube, Docs)
-- Allows teachers to post and share Google Drive and YouTube learning links
-- strictly for their assigned subjects, standards, divisions, mediums, and institutions.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.study_materials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    teacher_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    teacher_name TEXT NOT NULL DEFAULT 'Teacher',
    title TEXT NOT NULL,
    description TEXT,
    material_type TEXT NOT NULL DEFAULT 'link',       -- 'youtube', 'drive', 'link'
    url TEXT NOT NULL,
    subject TEXT NOT NULL,                            -- Assigned subject e.g. 'Physics', 'Chemistry', 'Biology', 'Mathematics'
    institution TEXT NOT NULL DEFAULT 'Sharda Mandir',-- Assigned institution e.g. 'Sharda Mandir', 'Tuition ACC'
    academic_year TEXT NOT NULL DEFAULT '2026-2027',  -- e.g. '2026-2027'
    standard TEXT NOT NULL,                           -- Assigned standard e.g. '11', '12'
    division TEXT NOT NULL,                           -- Assigned division e.g. 'A', 'B', 'C', 'ACC'
    medium TEXT NOT NULL,                             -- Assigned medium e.g. 'English', 'Gujarati'
    student_group TEXT NOT NULL DEFAULT 'all',        -- Stream group e.g. 'Biology', 'Math', 'all'
    assigned_student_ids UUID[] DEFAULT NULL,         -- NULL = entire class section; Array of UUIDs = specific students only
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Add column if table already exists without it
ALTER TABLE public.study_materials 
ADD COLUMN IF NOT EXISTS assigned_student_ids UUID[] DEFAULT NULL;

-- Indexes for high-performance querying
CREATE INDEX IF NOT EXISTS idx_study_materials_teacher_id ON public.study_materials(teacher_id);
CREATE INDEX IF NOT EXISTS idx_study_materials_scope ON public.study_materials(institution, standard, division, medium, subject);
CREATE INDEX IF NOT EXISTS idx_study_materials_created ON public.study_materials(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_study_materials_assigned_students ON public.study_materials USING GIN (assigned_student_ids);

-- Enable Row Level Security (RLS)
ALTER TABLE public.study_materials ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if any to recreate cleanly
DROP POLICY IF EXISTS "Allow authenticated read on study_materials" ON public.study_materials;
DROP POLICY IF EXISTS "Allow teachers to insert study_materials" ON public.study_materials;
DROP POLICY IF EXISTS "Allow teachers to update own study_materials" ON public.study_materials;
DROP POLICY IF EXISTS "Allow teachers to delete own study_materials" ON public.study_materials;

-- 1. Students & Authenticated users can view study materials
CREATE POLICY "Allow authenticated read on study_materials"
ON public.study_materials
FOR SELECT
TO authenticated
USING (true);

-- 2. Teachers and Admins can create study materials
CREATE POLICY "Allow teachers to insert study_materials"
ON public.study_materials
FOR INSERT
TO authenticated
WITH CHECK (
    auth.uid() = teacher_id OR
    EXISTS (
        SELECT 1 FROM public.users
        WHERE id = auth.uid() AND (role = 'teacher' OR role = 'admin')
    )
);

-- 3. Teachers can update their own study materials (Admins can update any)
CREATE POLICY "Allow teachers to update own study_materials"
ON public.study_materials
FOR UPDATE
TO authenticated
USING (
    auth.uid() = teacher_id OR
    EXISTS (
        SELECT 1 FROM public.users
        WHERE id = auth.uid() AND role = 'admin'
    )
);

-- 4. Teachers can delete their own study materials (Admins can delete any)
CREATE POLICY "Allow teachers to delete own study_materials"
ON public.study_materials
FOR DELETE
TO authenticated
USING (
    auth.uid() = teacher_id OR
    EXISTS (
        SELECT 1 FROM public.users
        WHERE id = auth.uid() AND role = 'admin'
    )
);
