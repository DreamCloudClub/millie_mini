-- =============================================
-- ADD OPENAI API KEY CONFIGURATION
-- =============================================
-- This table stores the master OpenAI API key
-- Only accessible to authenticated users with active subscriptions

CREATE TABLE IF NOT EXISTS public.service_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_name TEXT NOT NULL UNIQUE, -- e.g., 'openai', 'dream_cloud'
  api_key_encrypted TEXT, -- Store encrypted API key (recommended)
  api_key TEXT, -- Plain text (for MVP - migrate to encrypted later)
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.service_config ENABLE ROW LEVEL SECURITY;

-- Only authenticated users can view config
-- NOTE: For production, add additional checks for subscription status
CREATE POLICY "Authenticated users can view service config" ON public.service_config
  FOR SELECT USING (auth.role() = 'authenticated');

-- Only service accounts/admins can update (you'll need to set this up)
-- For now, you can manually insert via Supabase dashboard

-- Insert placeholder for OpenAI key (replace with your actual key)
-- You can do this via Supabase dashboard or uncomment and update:
/*
INSERT INTO public.service_config (service_name, api_key, is_active)
VALUES ('openai', 'sk-your-openai-api-key-here', true)
ON CONFLICT (service_name) 
DO UPDATE SET api_key = EXCLUDED.api_key, updated_at = NOW();
*/

-- =============================================
-- HELPER FUNCTION: Get OpenAI API Key
-- =============================================
-- This function can be called from the app to get the API key
-- It only returns the key if user is authenticated

CREATE OR REPLACE FUNCTION public.get_openai_key()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  key_value TEXT;
BEGIN
  -- Check if user is authenticated
  IF auth.role() != 'authenticated' THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;
  
  -- Get active OpenAI key
  SELECT api_key INTO key_value
  FROM public.service_config
  WHERE service_name = 'openai' AND is_active = true
  LIMIT 1;
  
  RETURN key_value;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.get_openai_key() TO authenticated;

