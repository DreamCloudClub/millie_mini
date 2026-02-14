-- =============================================
-- QUICK: Add Your OpenAI API Key
-- =============================================
-- Run this in Supabase SQL Editor (one command!)

-- Step 1: Create table (if you haven't already)
CREATE TABLE IF NOT EXISTS public.service_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_name TEXT NOT NULL UNIQUE,
  api_key TEXT,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.service_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view service config" ON public.service_config
  FOR SELECT USING (auth.role() = 'authenticated');

-- Step 2: Add your OpenAI API key (REPLACE THE KEY BELOW!)
INSERT INTO public.service_config (service_name, api_key, is_active)
VALUES ('openai', 'sk-YOUR-ACTUAL-OPENAI-API-KEY-HERE', true)
ON CONFLICT (service_name) 
DO UPDATE SET api_key = EXCLUDED.api_key, updated_at = NOW();

-- ✅ Done! Your key is now stored in Supabase.

