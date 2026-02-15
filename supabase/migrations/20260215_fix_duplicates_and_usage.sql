-- =============================================
-- FIX: Duplicate User Profiles & Usage Reset
-- =============================================
-- This migration fixes two issues:
-- 1. Duplicate user_profiles rows being created
-- 2. Race conditions in usage tracking functions

-- =============================================
-- PART 1: Fix user_profiles duplicates
-- =============================================

-- First, ensure the user_profiles table has proper constraints
-- Add unique constraint on email if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'user_profiles_email_key'
    ) THEN
        -- Before adding constraint, remove any duplicates (keep the oldest)
        DELETE FROM public.user_profiles a
        USING public.user_profiles b
        WHERE a.email = b.email
          AND a.created_at > b.created_at;

        ALTER TABLE public.user_profiles
        ADD CONSTRAINT user_profiles_email_key UNIQUE (email);
    END IF;
END $$;

-- Update the handle_new_user trigger to handle conflicts gracefully
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  -- Check if profile already exists for this email (from a different auth attempt)
  IF EXISTS (SELECT 1 FROM public.user_profiles WHERE email = NEW.email) THEN
    -- Update existing profile to link to new auth user id
    UPDATE public.user_profiles
    SET id = NEW.id, updated_at = NOW()
    WHERE email = NEW.email;
  ELSE
    -- Insert new profile
    INSERT INTO public.user_profiles (id, email, username)
    VALUES (
      NEW.id,
      NEW.email,
      COALESCE(SPLIT_PART(NEW.email, '@', 1), 'User')
    )
    ON CONFLICT (id) DO UPDATE SET
      email = EXCLUDED.email,
      updated_at = NOW();
  END IF;

  RETURN NEW;
EXCEPTION
  WHEN unique_violation THEN
    -- Profile already exists, that's fine
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update the handle_new_profile trigger to prevent duplicate agents
CREATE OR REPLACE FUNCTION public.handle_new_profile()
RETURNS TRIGGER AS $$
BEGIN
  -- Only create default agent if user doesn't already have one
  IF NOT EXISTS (
    SELECT 1 FROM public.agents WHERE user_id = NEW.id
  ) THEN
    INSERT INTO public.agents (user_id, name, face_color, eye_shape, is_active)
    VALUES (NEW.id, 'Millie', 0, 2, true);
  END IF;
  RETURN NEW;
EXCEPTION
  WHEN unique_violation THEN
    -- Agent already exists, that's fine
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- =============================================
-- PART 2: Fix usage_tracking race conditions
-- =============================================

-- Ensure usage_tracking table has the unique constraint
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

-- Fix get_or_create_usage to use proper upsert pattern (prevents race conditions)
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
        WHEN 'holder' THEN v_token_limit := 500000;
        WHEN 'basic' THEN v_token_limit := 500000;
        WHEN 'pro' THEN v_token_limit := 1000000;
        WHEN 'trial' THEN v_token_limit := 500000;
        ELSE v_token_limit := 0;
    END CASE;

    -- Use INSERT ... ON CONFLICT to handle race conditions
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
    ON CONFLICT (user_id, year_month) DO UPDATE SET
        subscription_status = EXCLUDED.subscription_status,
        token_limit = EXCLUDED.token_limit,
        user_email = EXCLUDED.user_email,
        updated_at = NOW()
    RETURNING * INTO v_record;

    RETURN v_record;
END;
$$ LANGUAGE plpgsql;

-- Fix record_usage to use proper upsert pattern
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
    -- Get current year-month
    v_year_month := TO_CHAR(NOW(), 'YYYY-MM');

    -- Determine token limit based on subscription status
    CASE p_subscription_status
        WHEN 'holder' THEN v_token_limit := 500000;
        WHEN 'basic' THEN v_token_limit := 500000;
        WHEN 'pro' THEN v_token_limit := 1000000;
        WHEN 'trial' THEN v_token_limit := 500000;
        ELSE v_token_limit := 0;
    END CASE;

    -- Use INSERT ... ON CONFLICT for atomic upsert with increment
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

-- check_usage_limit remains the same (it just calls get_or_create_usage)
-- get_current_usage remains the same (it just queries)

-- =============================================
-- CLEANUP: Remove any existing duplicates
-- =============================================

-- Remove duplicate user_profiles (keep the one linked to auth.users)
DELETE FROM public.user_profiles p1
WHERE EXISTS (
    SELECT 1 FROM public.user_profiles p2
    WHERE p1.email = p2.email
    AND p1.id != p2.id
    AND NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p1.id)
);

-- For any remaining duplicates, keep the oldest
DELETE FROM public.user_profiles a
USING public.user_profiles b
WHERE a.email = b.email
  AND a.id != b.id
  AND a.created_at > b.created_at;
