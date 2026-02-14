-- =============================================
-- MILLIE MINI - SUPABASE DATABASE SCHEMA
-- =============================================
-- Run this in Supabase SQL Editor

-- =============================================
-- 1. USER PROFILES TABLE
-- =============================================
-- Extends Supabase auth.users with app-specific profile data

CREATE TABLE IF NOT EXISTS public.user_profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  username TEXT NOT NULL,
  first_name TEXT DEFAULT '',
  last_name TEXT DEFAULT '',
  pronouns TEXT,
  bio TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

-- Users can only see/edit their own profile
CREATE POLICY "Users can view own profile" ON public.user_profiles
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile" ON public.user_profiles
  FOR INSERT WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON public.user_profiles
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Users can delete own profile" ON public.user_profiles
  FOR DELETE USING (auth.uid() = id);

-- =============================================
-- 2. AGENTS TABLE
-- =============================================
-- AI agent configurations per user

CREATE TABLE IF NOT EXISTS public.agents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL DEFAULT 'Millie',
  face_color INTEGER NOT NULL DEFAULT 0, -- 0=white, 1=blue, 2=green, etc.
  eye_shape INTEGER NOT NULL DEFAULT 2,  -- 0=circles, 1=squares, 2=rounded
  ai_service_id TEXT NOT NULL DEFAULT 'dream_cloud_default',
  voice TEXT NOT NULL DEFAULT 'Alloy',
  personality_id TEXT NOT NULL DEFAULT 'default_home',
  is_active BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.agents ENABLE ROW LEVEL SECURITY;

-- Users can only access their own agents
CREATE POLICY "Users can view own agents" ON public.agents
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own agents" ON public.agents
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own agents" ON public.agents
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own agents" ON public.agents
  FOR DELETE USING (auth.uid() = user_id);

-- Index for faster lookups
CREATE INDEX idx_agents_user_id ON public.agents(user_id);

-- =============================================
-- 3. PERSONALITIES TABLE
-- =============================================
-- Custom personalities per user (defaults are in app code)

CREATE TABLE IF NOT EXISTS public.personalities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  behavior_prompt TEXT NOT NULL,
  is_default BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.personalities ENABLE ROW LEVEL SECURITY;

-- Users can only access their own personalities
CREATE POLICY "Users can view own personalities" ON public.personalities
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own personalities" ON public.personalities
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own personalities" ON public.personalities
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own personalities" ON public.personalities
  FOR DELETE USING (auth.uid() = user_id);

-- Index for faster lookups
CREATE INDEX idx_personalities_user_id ON public.personalities(user_id);

-- =============================================
-- 4. AI SERVICES TABLE
-- =============================================
-- Custom AI service configurations per user

CREATE TABLE IF NOT EXISTS public.ai_services (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  service_type INTEGER NOT NULL, -- 0=dreamCloud, 1=openai, 2=gemini, 3=anthropic
  display_name TEXT NOT NULL,
  api_key_encrypted TEXT, -- Store encrypted, or use Supabase Vault
  subscription_email TEXT,
  status INTEGER NOT NULL DEFAULT 3, -- 0=active, 1=inactive, 2=notFound, 3=unknown
  is_dream_cloud BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.ai_services ENABLE ROW LEVEL SECURITY;

-- Users can only access their own AI services
CREATE POLICY "Users can view own ai_services" ON public.ai_services
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own ai_services" ON public.ai_services
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own ai_services" ON public.ai_services
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own ai_services" ON public.ai_services
  FOR DELETE USING (auth.uid() = user_id);

-- Index for faster lookups
CREATE INDEX idx_ai_services_user_id ON public.ai_services(user_id);

-- =============================================
-- 5. CONVERSATIONS TABLE (Optional - for history)
-- =============================================
-- Store conversation history if needed

CREATE TABLE IF NOT EXISTS public.conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  agent_id UUID REFERENCES public.agents(id) ON DELETE SET NULL,
  started_at TIMESTAMPTZ DEFAULT NOW(),
  ended_at TIMESTAMPTZ
);

-- Enable RLS
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own conversations" ON public.conversations
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own conversations" ON public.conversations
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own conversations" ON public.conversations
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own conversations" ON public.conversations
  FOR DELETE USING (auth.uid() = user_id);

CREATE INDEX idx_conversations_user_id ON public.conversations(user_id);

-- =============================================
-- 6. MESSAGES TABLE (Optional - for history)
-- =============================================
-- Store individual messages if needed

CREATE TABLE IF NOT EXISTS public.messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  role TEXT NOT NULL, -- 'user', 'assistant', 'system'
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- Users can access messages through conversation ownership
CREATE POLICY "Users can view own messages" ON public.messages
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.conversations 
      WHERE conversations.id = messages.conversation_id 
      AND conversations.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can insert own messages" ON public.messages
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.conversations 
      WHERE conversations.id = messages.conversation_id 
      AND conversations.user_id = auth.uid()
    )
  );

CREATE INDEX idx_messages_conversation_id ON public.messages(conversation_id);

-- =============================================
-- 7. HELPER FUNCTION: Auto-create profile on signup
-- =============================================
-- Automatically creates a user_profile when a new user signs up

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.user_profiles (id, email, username)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(SPLIT_PART(NEW.email, '@', 1), 'User')
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to call the function on new user signup
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- =============================================
-- 8. HELPER FUNCTION: Auto-create default agent
-- =============================================
-- Automatically creates a default agent when profile is created

CREATE OR REPLACE FUNCTION public.handle_new_profile()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.agents (user_id, name, face_color, eye_shape, is_active)
  VALUES (NEW.id, 'Millie', 0, 2, true); -- White face, Rounded Squares
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to call the function on new profile
DROP TRIGGER IF EXISTS on_profile_created ON public.user_profiles;
CREATE TRIGGER on_profile_created
  AFTER INSERT ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_profile();

-- =============================================
-- DONE! Your database is ready.
-- =============================================

