-- ============================================================
-- ORIGINAL ARTICLES TABLE
-- Stores scraped articles before AI summarization
-- ============================================================

CREATE TABLE IF NOT EXISTS original_articles (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,

    -- Article content
    title TEXT NOT NULL,
    content TEXT,                          -- Full article text
    url TEXT NOT NULL UNIQUE,              -- Original URL (dedupe key)
    author TEXT,

    -- Source info
    source_id UUID REFERENCES news_sources(id) ON DELETE SET NULL,
    source_name TEXT NOT NULL,

    -- Classification
    category TEXT NOT NULL,
    subcategory TEXT,
    topics TEXT[] DEFAULT '{}',            -- AI-generated tags: ["nvidia", "gpu", "ai"]

    -- Timestamps
    published_at TIMESTAMPTZ,              -- Original publish date
    scraped_at TIMESTAMPTZ DEFAULT NOW(),

    -- Processing state
    processed BOOLEAN DEFAULT false        -- Used in a report?
);

-- Indexes
CREATE INDEX idx_original_articles_unprocessed ON original_articles(processed) WHERE processed = false;
CREATE INDEX idx_original_articles_category ON original_articles(category);
CREATE INDEX idx_original_articles_scraped ON original_articles(scraped_at DESC);
CREATE INDEX idx_original_articles_topics ON original_articles USING GIN(topics);

-- RLS
ALTER TABLE original_articles ENABLE ROW LEVEL SECURITY;

-- Service role full access (n8n)
CREATE POLICY "Service role full access" ON original_articles FOR ALL TO service_role
    USING (true) WITH CHECK (true);

-- Authenticated can read (for debugging)
CREATE POLICY "Authenticated read" ON original_articles FOR SELECT TO authenticated USING (true);

-- ============================================================
-- AUTO-CLEANUP: Delete articles older than 7 days
-- ============================================================

CREATE OR REPLACE FUNCTION cleanup_old_original_articles()
RETURNS INTEGER AS $$
DECLARE deleted_count INTEGER;
BEGIN
    DELETE FROM original_articles WHERE scraped_at < NOW() - INTERVAL '7 days';
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON TABLE original_articles IS 'Scraped news articles awaiting AI processing';
