-- ============================================================
-- NEWS SOURCES TABLE
-- Stores RSS feed configurations for the n8n scraper
-- ============================================================

CREATE TABLE IF NOT EXISTS news_sources (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name TEXT NOT NULL,                    -- e.g., "TechCrunch", "Ars Technica"
    feed_url TEXT NOT NULL UNIQUE,         -- RSS feed URL
    category TEXT NOT NULL,                -- e.g., "technology", "business"
    subcategory TEXT,                      -- e.g., "ai", "robotics", "startups" (nullable)
    active BOOLEAN DEFAULT true,           -- Enable/disable feed
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_news_sources_active ON news_sources(active) WHERE active = true;
CREATE INDEX idx_news_sources_category ON news_sources(category);

-- RLS
ALTER TABLE news_sources ENABLE ROW LEVEL SECURITY;

-- Anyone can read (public data)
CREATE POLICY "Public read access" ON news_sources FOR SELECT USING (true);

-- Service role can manage (for n8n)
CREATE POLICY "Service role full access" ON news_sources FOR ALL TO service_role
    USING (true) WITH CHECK (true);

-- ============================================================
-- SEED DATA: Example RSS feeds (modify as needed)
-- ============================================================

INSERT INTO news_sources (name, feed_url, category, subcategory) VALUES
-- Technology
('TechCrunch', 'https://techcrunch.com/feed/', 'technology', NULL),
('Ars Technica', 'https://feeds.arstechnica.com/arstechnica/index', 'technology', NULL),
('The Verge', 'https://www.theverge.com/rss/index.xml', 'technology', NULL),
('Wired', 'https://www.wired.com/feed/rss', 'technology', NULL),
('MIT Tech Review', 'https://www.technologyreview.com/feed/', 'technology', 'ai'),
('VentureBeat AI', 'https://venturebeat.com/category/ai/feed/', 'technology', 'ai'),

-- Business
('Reuters Business', 'https://www.reutersagency.com/feed/?best-topics=business-finance', 'business', NULL),
('Bloomberg Markets', 'https://feeds.bloomberg.com/markets/news.rss', 'business', 'markets'),

-- Science
('Science Daily', 'https://www.sciencedaily.com/rss/all.xml', 'science', NULL),
('NASA News', 'https://www.nasa.gov/rss/dyn/breaking_news.rss', 'science', 'space'),

-- Health
('Medical News Today', 'https://www.medicalnewstoday.com/newsfeeds/rss/all', 'health', NULL),

-- Entertainment
('Entertainment Weekly', 'https://ew.com/feed/', 'entertainment', NULL),
('Variety', 'https://variety.com/feed/', 'entertainment', 'movies'),

-- Sports
('ESPN', 'https://www.espn.com/espn/rss/news', 'sports', NULL),
('BBC Sport', 'https://feeds.bbci.co.uk/sport/rss.xml', 'sports', NULL)

ON CONFLICT (feed_url) DO NOTHING;

COMMENT ON TABLE news_sources IS 'RSS feed sources for n8n news scraper';
