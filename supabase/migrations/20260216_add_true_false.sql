-- Add true_false_questions table with history tracking
-- Following the same pattern as trivia_questions, riddles, jokes

-- ============================================================
-- TRUE/FALSE QUESTIONS TABLE
-- ============================================================
CREATE TABLE true_false_questions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  statement TEXT NOT NULL,
  answer BOOLEAN NOT NULL,
  difficulty TEXT DEFAULT 'medium' CHECK (difficulty IN ('easy', 'medium', 'hard')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_true_false_questions_difficulty ON true_false_questions(difficulty);

ALTER TABLE true_false_questions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read true false questions" ON true_false_questions
  FOR SELECT USING (true);

-- User history for true/false
CREATE TABLE user_true_false_history (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  question_id UUID NOT NULL REFERENCES true_false_questions(id) ON DELETE CASCADE,
  last_used_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  PRIMARY KEY (user_id, question_id)
);

ALTER TABLE user_true_false_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own true false history" ON user_true_false_history
  FOR ALL USING (auth.uid() = user_id);
