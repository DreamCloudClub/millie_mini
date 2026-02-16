-- =============================================
-- FIX: Usage Tracking Duplicate Rows
-- =============================================
-- Problem: Race condition in get_or_create_usage() causes duplicate rows
-- when user signs in on multiple devices simultaneously.
--
-- The old code did: SELECT to check → INSERT if not found
-- This allows two concurrent requests to both see "not found" and both INSERT.
--
-- Fix: Use INSERT ... ON CONFLICT (atomic upsert pattern)

-- =============================================
-- STEP 1: Clean up existing duplicate rows
-- =============================================

-- Keep only one row per (user_id, year_month) - the one with lowest tokens_used
-- (or if same, keep the oldest)
DELETE FROM public.usage_tracking a
USING public.usage_tracking b
WHERE a.user_id = b.user_id
  AND a.year_month = b.year_month
  AND a.id != b.id
  AND (
    a.tokens_used > b.tokens_used
    OR (a.tokens_used = b.tokens_used AND a.created_at > b.created_at)
  );

-- =============================================
-- STEP 2: Add unique constraint to prevent future duplicates
-- =============================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'usage_tracking_user_month_key'
    ) THEN
        ALTER TABLE public.usage_tracking
        ADD CONSTRAINT usage_tracking_user_month_key UNIQUE (user_id, year_month);
    END IF;
END $$;

-- =============================================
-- STEP 3: Fix get_or_create_usage to use atomic upsert
-- =============================================

CREATE OR REPLACE FUNCTION get_or_create_usage(
    p_user_id UUID,
    p_user_email TEXT,
    p_subscription_status TEXT DEFAULT 'inactive'
)
RETURNS usage_tracking AS $$
DECLARE
    v_year_month TEXT;
    v_token_limit BIGINT;
    v_record usage_tracking;
BEGIN
    -- Get current year-month (this is what triggers monthly reset)
    v_year_month := TO_CHAR(NOW(), 'YYYY-MM');

    -- Determine token limit based on subscription status
    CASE p_subscription_status
        WHEN 'holder' THEN v_token_limit := 500000;
        WHEN 'basic' THEN v_token_limit := 500000;
        WHEN 'pro' THEN v_token_limit := 1000000;
        WHEN 'trial' THEN v_token_limit := 500000;
        ELSE v_token_limit := 0;
    END CASE;

    -- Atomic upsert: INSERT or UPDATE in one operation
    -- This prevents race conditions from concurrent requests
    INSERT INTO usage_tracking (
        user_id,
        user_email,
        year_month,
        tokens_used,
        token_limit,
        subscription_status
    ) VALUES (
        p_user_id,
        p_user_email,
        v_year_month,
        0,  -- New month starts at 0
        v_token_limit,
        p_subscription_status
    )
    ON CONFLICT (user_id, year_month) DO UPDATE SET
        subscription_status = EXCLUDED.subscription_status,
        token_limit = EXCLUDED.token_limit,
        user_email = EXCLUDED.user_email,
        updated_at = NOW()
    RETURNING * INTO v_record;

    RETURN v_record;
END;
$$ LANGUAGE plpgsql;

-- =============================================
-- STEP 4: Fix record_usage to use atomic upsert with increment
-- =============================================

CREATE OR REPLACE FUNCTION record_usage(
    p_user_id UUID,
    p_user_email TEXT,
    p_subscription_status TEXT,
    p_tokens_used BIGINT
)
RETURNS usage_tracking AS $$
DECLARE
    v_year_month TEXT;
    v_token_limit BIGINT;
    v_record usage_tracking;
BEGIN
    v_year_month := TO_CHAR(NOW(), 'YYYY-MM');

    CASE p_subscription_status
        WHEN 'holder' THEN v_token_limit := 500000;
        WHEN 'basic' THEN v_token_limit := 500000;
        WHEN 'pro' THEN v_token_limit := 1000000;
        WHEN 'trial' THEN v_token_limit := 500000;
        ELSE v_token_limit := 0;
    END CASE;

    -- Atomic upsert with increment
    -- If row exists: adds tokens to existing count
    -- If row doesn't exist: creates with initial token count
    INSERT INTO usage_tracking (
        user_id,
        user_email,
        year_month,
        tokens_used,
        token_limit,
        subscription_status
    ) VALUES (
        p_user_id,
        p_user_email,
        v_year_month,
        p_tokens_used,
        v_token_limit,
        p_subscription_status
    )
    ON CONFLICT (user_id, year_month) DO UPDATE SET
        tokens_used = usage_tracking.tokens_used + EXCLUDED.tokens_used,
        subscription_status = EXCLUDED.subscription_status,
        token_limit = EXCLUDED.token_limit,
        updated_at = NOW()
    RETURNING * INTO v_record;

    RETURN v_record;
END;
$$ LANGUAGE plpgsql;

-- =============================================
-- DONE!
-- Monthly reset still works automatically via year_month field.
-- New month = new year_month value = new row with tokens_used = 0
-- =============================================
