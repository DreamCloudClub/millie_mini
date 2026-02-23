-- Add image_url column to original_articles table
ALTER TABLE original_articles
ADD COLUMN IF NOT EXISTS image_url TEXT;

COMMENT ON COLUMN original_articles.image_url IS 'Featured image URL extracted from og:image meta tag';

-- Add image_url column to reports table
ALTER TABLE reports
ADD COLUMN IF NOT EXISTS image_url TEXT;

COMMENT ON COLUMN reports.image_url IS 'Featured image URL from source article';
