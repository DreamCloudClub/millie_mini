-- Fix RLS Policy: Add INSERT permission for users
-- This allows users to create their own usage tracking records via the RPC functions

-- Policy: Users can insert their own usage records
CREATE POLICY "Users can insert own usage"
    ON usage_tracking FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Note: The other policies should already exist:
-- - "Users can view own usage" (SELECT)
-- - "Users can update own usage" (UPDATE)  
-- - "Service role can manage all usage" (ALL)

