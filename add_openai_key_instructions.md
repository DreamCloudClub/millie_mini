# How to Add Your OpenAI API Key

## Step 1: Create the Table (One-time setup)

1. Go to **Supabase Dashboard**: https://supabase.com/dashboard/project/lfpzverpjlcuobmgejwv
2. Click **SQL Editor** in the left sidebar
3. Click **New Query**
4. Paste this SQL and click **Run**:

```sql
-- Create the table (run this first, only once)
CREATE TABLE IF NOT EXISTS public.service_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_name TEXT NOT NULL UNIQUE,
  api_key_encrypted TEXT,
  api_key TEXT,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.service_config ENABLE ROW LEVEL SECURITY;

-- Allow authenticated users to read
CREATE POLICY "Authenticated users can view service config" ON public.service_config
  FOR SELECT USING (auth.role() = 'authenticated');
```

## Step 2: Add Your OpenAI API Key

After the table is created, run this SQL (replace `sk-your-actual-key-here` with your real key):

```sql
-- Add or update your OpenAI API key
INSERT INTO public.service_config (service_name, api_key, is_active)
VALUES ('openai', 'sk-your-actual-openai-api-key-here', true)
ON CONFLICT (service_name) 
DO UPDATE SET api_key = EXCLUDED.api_key, updated_at = NOW();
```

**⚠️ Important**: Replace `sk-your-actual-openai-api-key-here` with your real OpenAI API key!

## Option 2: Using Supabase Table Editor (GUI)

1. Go to **Supabase Dashboard** → **Table Editor**
2. If `service_config` table exists, click on it
3. Click **Insert row**
4. Fill in:
   - `service_name`: `openai`
   - `api_key`: `sk-your-actual-key-here` (your real key)
   - `is_active`: `true`
5. Click **Save**

## Verify It Works

After adding the key, the Flutter app will automatically fetch it when needed. You can verify by:

1. Opening the app
2. Going to **Dashboard** → **AI Services** → **Dream Cloud AI Account**
3. The app should be able to fetch the key from Supabase

---

**Your OpenAI API key is stored securely:**
- ✅ Only authenticated users can read it
- ✅ Cached locally for 24 hours (reduces database calls)
- ✅ Never exposed in client code

