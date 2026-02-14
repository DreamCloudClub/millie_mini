-- Monthly Usage Tracking for Millie Mini AI
-- Tracks token usage per user per month with subscription-based limits
-- This file can be run safely on existing tables (uses CREATE OR REPLACE)

-- Update existing rows to new token limits (run this first if you have existing data)
UPDATE usage_tracking
SET 
    token_limit = CASE subscription_status
        WHEN 'holder' THEN 500000   -- 500K tokens
        WHEN 'basic' THEN 500000    -- 500K tokens
        WHEN 'pro' THEN 1000000     -- 1M tokens
        WHEN 'trial' THEN 500000    -- 500K tokens (trial gets basic limit)
        ELSE token_limit            -- Keep existing for other statuses
    END,
    updated_at = NOW()
WHERE token_limit IN (8000000, 16000000); -- Only update old limits

-- Function to get or create current month's usage record
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
    -- Get current year-month
    v_year_month := TO_CHAR(NOW(), 'YYYY-MM');
    
    -- Determine token limit based on subscription status
    CASE p_subscription_status
        WHEN 'holder' THEN v_token_limit := 500000; -- 500K tokens
        WHEN 'basic' THEN v_token_limit := 500000;  -- 500K tokens
        WHEN 'pro' THEN v_token_limit := 1000000;   -- 1M tokens
        WHEN 'trial' THEN v_token_limit := 500000;  -- 500K tokens (trial gets basic limit)
        ELSE v_token_limit := 0; -- No access
    END CASE;
    
    -- Try to get existing record
    SELECT * INTO v_record
    FROM usage_tracking
    WHERE user_id = p_user_id AND year_month = v_year_month;
    
    -- If no record exists, create one
    IF v_record IS NULL THEN
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
            0,
            v_token_limit,
            p_subscription_status
        )
        RETURNING * INTO v_record;
    ELSE
        -- Update subscription status and limit if changed
        IF v_record.subscription_status != p_subscription_status OR v_record.token_limit != v_token_limit THEN
            UPDATE usage_tracking
            SET 
                subscription_status = p_subscription_status,
                token_limit = v_token_limit,
                updated_at = NOW()
            WHERE id = v_record.id
            RETURNING * INTO v_record;
        END IF;
    END IF;
    
    RETURN v_record;
END;
$$ LANGUAGE plpgsql;

-- Function to check if user can make API call (has tokens remaining)
CREATE OR REPLACE FUNCTION check_usage_limit(
    p_user_id UUID,
    p_user_email TEXT,
    p_subscription_status TEXT,
    p_tokens_needed BIGINT DEFAULT 0
)
RETURNS JSON AS $$
DECLARE
    v_record usage_tracking;
    v_can_proceed BOOLEAN;
    v_tokens_remaining BIGINT;
BEGIN
    -- Get or create current month's usage record
    v_record := get_or_create_usage(p_user_id, p_user_email, p_subscription_status);
    
    -- Calculate remaining tokens
    v_tokens_remaining := GREATEST(0, v_record.token_limit - v_record.tokens_used);
    v_can_proceed := (v_record.tokens_used + p_tokens_needed) <= v_record.token_limit;
    
    RETURN json_build_object(
        'can_proceed', v_can_proceed,
        'tokens_used', v_record.tokens_used,
        'token_limit', v_record.token_limit,
        'tokens_remaining', v_tokens_remaining,
        'subscription_status', v_record.subscription_status
    );
END;
$$ LANGUAGE plpgsql;

-- Function to record token usage
CREATE OR REPLACE FUNCTION record_usage(
    p_user_id UUID,
    p_user_email TEXT,
    p_subscription_status TEXT,
    p_tokens_used BIGINT
)
RETURNS usage_tracking AS $$
DECLARE
    v_record usage_tracking;
BEGIN
    -- Get or create current month's usage record
    v_record := get_or_create_usage(p_user_id, p_user_email, p_subscription_status);
    
    -- Update tokens used
    UPDATE usage_tracking
    SET 
        tokens_used = tokens_used + p_tokens_used,
        updated_at = NOW()
    WHERE id = v_record.id
    RETURNING * INTO v_record;
    
    RETURN v_record;
END;
$$ LANGUAGE plpgsql;

-- Function to get current month usage (for display)
CREATE OR REPLACE FUNCTION get_current_usage(
    p_user_id UUID,
    p_user_email TEXT DEFAULT NULL,
    p_subscription_status TEXT DEFAULT 'inactive'
)
RETURNS JSON AS $$
DECLARE
    v_record usage_tracking;
    v_year_month TEXT;
    v_token_limit BIGINT;
BEGIN
    v_year_month := TO_CHAR(NOW(), 'YYYY-MM');
    
    SELECT * INTO v_record
    FROM usage_tracking
    WHERE user_id = p_user_id AND year_month = v_year_month;
    
    -- If no record exists, create one using get_or_create_usage
    IF v_record IS NULL AND p_user_email IS NOT NULL THEN
        v_record := get_or_create_usage(p_user_id, p_user_email, p_subscription_status);
    END IF;
    
    -- If still no record (no email provided), return zeros with correct limit
    IF v_record IS NULL THEN
        -- Determine token limit based on subscription status
        CASE p_subscription_status
            WHEN 'holder' THEN v_token_limit := 500000; -- 500K tokens
            WHEN 'basic' THEN v_token_limit := 500000;  -- 500K tokens
            WHEN 'pro' THEN v_token_limit := 1000000;   -- 1M tokens
            WHEN 'trial' THEN v_token_limit := 500000;  -- 500K tokens
            ELSE v_token_limit := 0; -- No access
        END CASE;
        
        RETURN json_build_object(
            'tokens_used', 0,
            'token_limit', v_token_limit,
            'tokens_remaining', v_token_limit,
            'subscription_status', p_subscription_status,
            'year_month', v_year_month
        );
    END IF;
    
    RETURN json_build_object(
        'tokens_used', v_record.tokens_used,
        'token_limit', v_record.token_limit,
        'tokens_remaining', GREATEST(0, v_record.token_limit - v_record.tokens_used),
        'subscription_status', v_record.subscription_status,
        'year_month', v_record.year_month
    );
END;
$$ LANGUAGE plpgsql;
