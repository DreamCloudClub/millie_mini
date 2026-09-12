-- ============================================================
-- CLEANUP FUNCTION FOR ORIGINAL_ARTICLES
-- Deletes articles older than 48 hours
-- ============================================================

CREATE OR REPLACE FUNCTION cleanup_old_original_articles()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM original_articles
    WHERE scraped_at < NOW() - INTERVAL '48 hours';
    GET DIAGNOSTICS deleted_count = ROW_COUNT;

    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION cleanup_old_original_articles IS 'Deletes original_articles older than 48 hours';
