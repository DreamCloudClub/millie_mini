-- ============================================================
-- ADD published_at and source_url to reports table
-- For natural ordering and linking to original article
-- ============================================================

-- Add published_at (original article publish time)
ALTER TABLE reports ADD COLUMN IF NOT EXISTS published_at TIMESTAMPTZ;

-- Add source_url (link to original article)
ALTER TABLE reports ADD COLUMN IF NOT EXISTS source_url TEXT;

-- Add audio_url (cached TTS audio) if not exists
ALTER TABLE reports ADD COLUMN IF NOT EXISTS audio_url TEXT;

-- Create index for sorting by published_at
CREATE INDEX IF NOT EXISTS idx_reports_published ON reports(published_at DESC);

-- Update existing reports to use created_at as fallback for published_at
UPDATE reports SET published_at = created_at WHERE published_at IS NULL;

COMMENT ON COLUMN reports.published_at IS 'Original article publish time - used for sorting';
COMMENT ON COLUMN reports.source_url IS 'URL to original source article';
COMMENT ON COLUMN reports.audio_url IS 'Cached TTS audio URL';
