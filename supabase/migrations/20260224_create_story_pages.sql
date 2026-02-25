-- Story pages table for bedtime stories
CREATE TABLE IF NOT EXISTS story_pages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  story_id TEXT NOT NULL,             -- 'little_star', etc.
  title TEXT NOT NULL,                -- Story title (same for all pages of a story)
  page_number INT NOT NULL,           -- 1, 2, 3, etc.
  text TEXT NOT NULL,                 -- Narration text for this page
  image_url TEXT,                     -- URL to image in storage bucket
  audio_url TEXT,                     -- URL to cached TTS audio (null until first play)
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for efficient querying
CREATE INDEX idx_story_pages_story_id ON story_pages(story_id);
CREATE INDEX idx_story_pages_order ON story_pages(story_id, page_number);

-- Enable RLS
ALTER TABLE story_pages ENABLE ROW LEVEL SECURITY;

-- Anyone can read
CREATE POLICY "Anyone can read story_pages" ON story_pages
  FOR SELECT USING (true);

-- Authenticated users can update audio_url (for caching TTS)
CREATE POLICY "Authenticated users can update audio_url" ON story_pages
  FOR UPDATE USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');
