-- ============================================================
-- NEWS SETTINGS TABLE
-- Per-user news preferences
-- ============================================================

CREATE TABLE IF NOT EXISTS news_settings (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,

    -- Poll frequency (minutes): 0=off, 15, 30, 60, 120, 180, 360, 720, 1440
    poll_frequency INTEGER DEFAULT 60,

    -- Custom keyword filters (e.g., ["nvidia", "tesla", "spacex"])
    keyword_filters TEXT[] DEFAULT '{}',

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS
ALTER TABLE news_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own settings" ON news_settings FOR ALL TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

COMMENT ON TABLE news_settings IS 'Per-user news polling and filter preferences';
COMMENT ON COLUMN news_settings.poll_frequency IS 'Minutes between checks: 0=off, 15, 30, 60, 120, 180, 360, 720, 1440';
COMMENT ON COLUMN news_settings.keyword_filters IS 'Custom keywords to watch for (e.g., nvidia, tesla)';

-- ============================================================
-- WATCHLIST TABLE (Category Subscriptions)
-- ============================================================

-- Drop old watchlist if exists
DROP TABLE IF EXISTS watchlist CASCADE;

CREATE TABLE watchlist (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    category TEXT NOT NULL,
    subcategory TEXT,                      -- NULL = all subcategories
    enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(user_id, category, subcategory)
);

-- Indexes
CREATE INDEX idx_watchlist_user ON watchlist(user_id);
CREATE INDEX idx_watchlist_enabled ON watchlist(user_id, enabled) WHERE enabled = true;

-- RLS
ALTER TABLE watchlist ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own watchlist" ON watchlist FOR ALL TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

COMMENT ON TABLE watchlist IS 'User category/subcategory subscriptions';

-- ============================================================
-- SAVED REPORTS TABLE
-- User's saved reports (prevents expiration)
-- ============================================================

CREATE TABLE IF NOT EXISTS saved_reports (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    report_id UUID NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
    saved_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(user_id, report_id)
);

-- RLS
ALTER TABLE saved_reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own saved reports" ON saved_reports FOR ALL TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

COMMENT ON TABLE saved_reports IS 'User saved reports - prevents auto-expiration';

-- ============================================================
-- ANNOUNCED REPORTS TABLE
-- Tracks which reports have been announced to each user
-- ============================================================

CREATE TABLE IF NOT EXISTS announced_reports (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    report_id UUID NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
    announced_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(user_id, report_id)
);

-- RLS
ALTER TABLE announced_reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own announced reports" ON announced_reports FOR ALL TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

COMMENT ON TABLE announced_reports IS 'Tracks which reports have been announced via TTS to each user';
