-- Create game_questions table
CREATE TABLE IF NOT EXISTS game_questions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category TEXT NOT NULL CHECK (category IN ('riddle', 'joke', 'trivia')),
  question TEXT NOT NULL,
  answer TEXT NOT NULL,
  last_used_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create index for efficient querying by category and last_used_at
CREATE INDEX IF NOT EXISTS idx_game_questions_category_last_used
ON game_questions(category, last_used_at NULLS FIRST);

-- Enable RLS
ALTER TABLE game_questions ENABLE ROW LEVEL SECURITY;

-- Everyone can read game questions (they're shared content)
CREATE POLICY "Anyone can read game questions" ON game_questions
  FOR SELECT USING (true);

-- Only authenticated users can update last_used_at
CREATE POLICY "Authenticated users can update last_used_at" ON game_questions
  FOR UPDATE USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');
