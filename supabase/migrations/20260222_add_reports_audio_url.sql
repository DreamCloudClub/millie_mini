-- ============================================================
-- ADD AUDIO_URL TO REPORTS
-- Cached TTS audio generated on first play, shared by all users
-- ============================================================

ALTER TABLE reports
ADD COLUMN IF NOT EXISTS audio_url TEXT;

COMMENT ON COLUMN reports.audio_url IS 'Cached TTS audio URL - generated on first play, shared by all users';
