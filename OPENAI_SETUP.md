# OpenAI API Key Setup Guide

## Overview
The app uses a **centralized OpenAI API key** stored in Supabase. Users don't need their own API keys - they just need an active subscription (Holder or Subscriber role).

## Setup Steps

### 1. Run SQL in Supabase

Run the SQL file in Supabase SQL Editor:
```
supabase_add_openai_key.sql
```

This creates:
- `service_config` table to store API keys
- `get_openai_key()` function to retrieve the key securely

### 2. Add Your OpenAI API Key

In Supabase SQL Editor, run:

```sql
INSERT INTO public.service_config (service_name, api_key, is_active)
VALUES ('openai', 'sk-your-actual-openai-api-key-here', true)
ON CONFLICT (service_name) 
DO UPDATE SET api_key = EXCLUDED.api_key, updated_at = NOW();
```

**⚠️ SECURITY NOTE:** For production, you should:
- Use Supabase Vault to encrypt the key
- Add additional RLS policies to restrict access
- Consider using Edge Functions to proxy API calls

### 3. How It Works

1. **User logs in** → App checks subscription status via WordPress API
2. **User launches agent** → App fetches OpenAI key from Supabase
3. **Voice pipeline** → Uses OpenAI API with master key for:
   - Whisper (Speech-to-Text)
   - GPT-4 (LLM/Chat)
   - TTS (Text-to-Speech)

### 4. Files Created

- `lib/services/openai_service.dart` - Handles OpenAI API calls
- `supabase_add_openai_key.sql` - Database schema
- Updated `lib/services/storage_service.dart` - Added cache methods

### 5. Next Steps

1. ✅ Run SQL to create table
2. ✅ Add your OpenAI API key to Supabase
3. ✅ Test subscription check (already working!)
4. 🔄 Update voice pipeline to use `OpenAIService`
5. 🔄 Wire up STT/LLM/TTS in `voice_pipeline_service.dart`

## API Key Caching

The app caches the OpenAI key locally for 24 hours to reduce Supabase calls. The cache is cleared on logout.

## Subscription Requirements

Only users with:
- **Holder** role (crypto holders $50+)
- **Subscriber** role (paid subscribers)

Can use the OpenAI API. The app checks subscription status before making API calls.

