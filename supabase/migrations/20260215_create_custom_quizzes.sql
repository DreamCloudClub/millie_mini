-- Create custom_quizzes table for user-defined quiz mixes
CREATE TABLE IF NOT EXISTS custom_quizzes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  categories TEXT[] NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for user lookup
CREATE INDEX IF NOT EXISTS idx_custom_quizzes_user_id ON custom_quizzes(user_id);

-- Enable RLS
ALTER TABLE custom_quizzes ENABLE ROW LEVEL SECURITY;

-- Users can only access their own custom quizzes
CREATE POLICY "Users manage own custom quizzes" ON custom_quizzes
  FOR ALL USING (auth.uid() = user_id);
