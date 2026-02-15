-- Create spelling_words table (separate from game_questions)
CREATE TABLE IF NOT EXISTS spelling_words (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  word TEXT NOT NULL,
  difficulty TEXT NOT NULL CHECK (difficulty IN ('easy', 'medium', 'hard')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create index for efficient querying by difficulty
CREATE INDEX IF NOT EXISTS idx_spelling_words_difficulty
ON spelling_words(difficulty);

-- Enable RLS
ALTER TABLE spelling_words ENABLE ROW LEVEL SECURITY;

-- Everyone can read spelling words (shared content)
CREATE POLICY "Anyone can read spelling words" ON spelling_words
  FOR SELECT USING (true);

-- Create user history table for spelling words
CREATE TABLE IF NOT EXISTS user_spelling_history (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  word_id UUID NOT NULL REFERENCES spelling_words(id) ON DELETE CASCADE,
  last_used_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  PRIMARY KEY (user_id, word_id)
);

-- Enable RLS on history
ALTER TABLE user_spelling_history ENABLE ROW LEVEL SECURITY;

-- Users can only access their own history
CREATE POLICY "Users can manage own spelling history" ON user_spelling_history
  FOR ALL USING (auth.uid() = user_id);

-- Revert category constraint back to original (remove 'spelling')
ALTER TABLE game_questions
DROP CONSTRAINT IF EXISTS game_questions_category_check;

ALTER TABLE game_questions
ADD CONSTRAINT game_questions_category_check
CHECK (category IN ('riddle', 'joke', 'trivia'));
