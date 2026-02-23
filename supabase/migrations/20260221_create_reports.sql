-- ============================================================
-- REPORTS TABLE (Published Articles)
-- Global reports - tablets filter by category
-- ============================================================

-- Drop old reports table if exists (backup data first if needed!)
-- DROP TABLE IF EXISTS reports CASCADE;

CREATE TABLE IF NOT EXISTS reports (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,

    -- Content
    title TEXT NOT NULL,
    summary TEXT NOT NULL,                 -- 1-2 sentences for TTS
    content TEXT NOT NULL,                 -- Full report

    -- Classification
    category TEXT NOT NULL,
    subcategory TEXT,
    topics TEXT[] DEFAULT '{}',            -- Keywords: ["nvidia", "gpu"]

    -- Source tracking
    source_article_ids UUID[] DEFAULT '{}',

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '48 hours')
);

-- Indexes
CREATE INDEX idx_reports_category ON reports(category);
CREATE INDEX idx_reports_subcategory ON reports(subcategory);
CREATE INDEX idx_reports_created ON reports(created_at DESC);
CREATE INDEX idx_reports_expires ON reports(expires_at);
CREATE INDEX idx_reports_topics ON reports USING GIN(topics);

-- RLS
ALTER TABLE reports ENABLE ROW LEVEL SECURITY;

-- Anyone authenticated can read
CREATE POLICY "Authenticated read" ON reports FOR SELECT TO authenticated USING (true);

-- Service role can manage (n8n)
CREATE POLICY "Service role full access" ON reports FOR ALL TO service_role
    USING (true) WITH CHECK (true);

-- ============================================================
-- AUTO-CLEANUP: Two-tier retention
-- Unsaved: 48 hours | Saved: 30 days
-- ============================================================

CREATE OR REPLACE FUNCTION cleanup_expired_reports()
RETURNS INTEGER AS $$
DECLARE
    unsaved_deleted INTEGER;
    old_deleted INTEGER;
BEGIN
    -- 1. Delete unsaved reports past 48 hours
    DELETE FROM reports
    WHERE expires_at < NOW()
    AND id NOT IN (SELECT report_id FROM saved_reports);
    GET DIAGNOSTICS unsaved_deleted = ROW_COUNT;

    -- 2. Delete ALL reports older than 30 days (even saved)
    DELETE FROM reports
    WHERE created_at < NOW() - INTERVAL '30 days';
    GET DIAGNOSTICS old_deleted = ROW_COUNT;

    RETURN unsaved_deleted + old_deleted;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON TABLE reports IS 'Published AI news reports - global, tablets filter by preference';
COMMENT ON COLUMN reports.summary IS 'Short summary for TTS announcement';
COMMENT ON COLUMN reports.content IS 'Full report content for reading';
COMMENT ON COLUMN reports.topics IS 'Keyword tags for filtering (e.g., nvidia, tesla)';
