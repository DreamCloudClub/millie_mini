-- ============================================================
-- ALTER REPORTS_SCHEDULES: Change from single category to array
-- ============================================================

-- Add new categories column (JSONB array)
ALTER TABLE reports_schedules
ADD COLUMN IF NOT EXISTS categories JSONB DEFAULT '[]';

-- Migrate existing data: convert category to categories array
UPDATE reports_schedules
SET categories = CASE
    WHEN category = 'all' THEN '[]'::jsonb
    ELSE jsonb_build_array(category)
END
WHERE categories = '[]'::jsonb OR categories IS NULL;

-- Drop old columns (only if migration successful)
ALTER TABLE reports_schedules DROP COLUMN IF EXISTS category;
ALTER TABLE reports_schedules DROP COLUMN IF EXISTS subcategory;

-- Drop old unique constraint if exists
ALTER TABLE reports_schedules DROP CONSTRAINT IF EXISTS reports_schedules_user_id_category_subcategory_start_time_key;

-- Update comment
COMMENT ON COLUMN reports_schedules.categories IS 'JSON array of category names (empty = all from watchlist)';
