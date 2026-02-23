-- ============================================================
-- REPORT SETTINGS TABLES
-- User-specific state for global reports system
-- ============================================================

-- ============================================================
-- SAVED_REPORTS: Track which reports each user has saved
-- ============================================================

CREATE TABLE IF NOT EXISTS saved_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    report_id UUID NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
    saved_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, report_id)
);

-- Indexes
CREATE INDEX idx_saved_reports_user ON saved_reports(user_id);
CREATE INDEX idx_saved_reports_report ON saved_reports(report_id);
CREATE INDEX idx_saved_reports_saved_at ON saved_reports(saved_at DESC);

-- RLS
ALTER TABLE saved_reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own saved reports" ON saved_reports
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own saved reports" ON saved_reports
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own saved reports" ON saved_reports
    FOR DELETE TO authenticated
    USING (auth.uid() = user_id);

-- ============================================================
-- ANNOUNCED_REPORTS: Track which reports have been announced to each user
-- ============================================================

CREATE TABLE IF NOT EXISTS announced_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    report_id UUID NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
    announced_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, report_id)
);

-- Indexes
CREATE INDEX idx_announced_reports_user ON announced_reports(user_id);
CREATE INDEX idx_announced_reports_report ON announced_reports(report_id);
CREATE INDEX idx_announced_reports_announced_at ON announced_reports(announced_at DESC);

-- RLS
ALTER TABLE announced_reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own announced reports" ON announced_reports
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own announced reports" ON announced_reports
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);

-- ============================================================
-- REPORT_SETTINGS: User's announcement preferences
-- ============================================================

CREATE TABLE IF NOT EXISTS report_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
    enabled BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index
CREATE INDEX idx_report_settings_user ON report_settings(user_id);

-- RLS
ALTER TABLE report_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own settings" ON report_settings
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own settings" ON report_settings
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own settings" ON report_settings
    FOR UPDATE TO authenticated
    USING (auth.uid() = user_id);

-- ============================================================
-- CATEGORY_SCHEDULES: Time-based announcement rules
-- ============================================================

CREATE TABLE IF NOT EXISTS category_schedules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    category VARCHAR(100) NOT NULL,        -- "all" for all categories, or specific like "technology"
    subcategory VARCHAR(100),              -- null for all subcategories
    start_time INT NOT NULL,               -- minutes from midnight (540 = 9:00 AM)
    end_time INT NOT NULL,                 -- minutes from midnight (840 = 2:00 PM)
    days_of_week JSONB DEFAULT '[1,2,3,4,5]', -- Mon-Fri by default
    frequency INT NOT NULL DEFAULT 30,     -- announcement interval in minutes
    enabled BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, category, subcategory, start_time, end_time)
);

-- Indexes
CREATE INDEX idx_category_schedules_user ON category_schedules(user_id);
CREATE INDEX idx_category_schedules_enabled ON category_schedules(enabled) WHERE enabled = true;
CREATE INDEX idx_category_schedules_category ON category_schedules(category);

-- RLS
ALTER TABLE category_schedules ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own schedules" ON category_schedules
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own schedules" ON category_schedules
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own schedules" ON category_schedules
    FOR UPDATE TO authenticated
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own schedules" ON category_schedules
    FOR DELETE TO authenticated
    USING (auth.uid() = user_id);

-- ============================================================
-- COMMENTS
-- ============================================================

COMMENT ON TABLE saved_reports IS 'Junction table tracking which reports each user has saved';
COMMENT ON TABLE announced_reports IS 'Junction table tracking which reports have been announced to each user';
COMMENT ON TABLE report_settings IS 'User preferences for report announcements';
COMMENT ON TABLE category_schedules IS 'Time-based rules for when to announce reports by category';

COMMENT ON COLUMN category_schedules.start_time IS 'Minutes from midnight (e.g., 540 = 9:00 AM)';
COMMENT ON COLUMN category_schedules.end_time IS 'Minutes from midnight (e.g., 840 = 2:00 PM)';
COMMENT ON COLUMN category_schedules.days_of_week IS 'JSON array of days [1-7], where 1=Monday, 7=Sunday';
COMMENT ON COLUMN category_schedules.frequency IS 'Interval in minutes between announcements during active window';
