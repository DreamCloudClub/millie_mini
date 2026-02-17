-- Split game_questions into separate tables: trivia_questions, riddles, jokes
-- Each with its own history tracking table following the spelling_words pattern

-- ============================================================
-- TRIVIA QUESTIONS TABLE
-- ============================================================
CREATE TABLE trivia_questions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  question TEXT NOT NULL,
  answer TEXT NOT NULL,
  difficulty TEXT DEFAULT 'medium' CHECK (difficulty IN ('easy', 'medium', 'hard')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_trivia_questions_difficulty ON trivia_questions(difficulty);

ALTER TABLE trivia_questions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read trivia questions" ON trivia_questions
  FOR SELECT USING (true);

-- User history for trivia
CREATE TABLE user_trivia_history (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  question_id UUID NOT NULL REFERENCES trivia_questions(id) ON DELETE CASCADE,
  last_used_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  PRIMARY KEY (user_id, question_id)
);

ALTER TABLE user_trivia_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own trivia history" ON user_trivia_history
  FOR ALL USING (auth.uid() = user_id);

-- ============================================================
-- RIDDLES TABLE
-- ============================================================
CREATE TABLE riddles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  question TEXT NOT NULL,
  answer TEXT NOT NULL,
  difficulty TEXT DEFAULT 'medium' CHECK (difficulty IN ('easy', 'medium', 'hard')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_riddles_difficulty ON riddles(difficulty);

ALTER TABLE riddles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read riddles" ON riddles
  FOR SELECT USING (true);

-- User history for riddles
CREATE TABLE user_riddles_history (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  question_id UUID NOT NULL REFERENCES riddles(id) ON DELETE CASCADE,
  last_used_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  PRIMARY KEY (user_id, question_id)
);

ALTER TABLE user_riddles_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own riddles history" ON user_riddles_history
  FOR ALL USING (auth.uid() = user_id);

-- ============================================================
-- JOKES TABLE
-- ============================================================
CREATE TABLE jokes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  question TEXT NOT NULL,
  answer TEXT NOT NULL,
  difficulty TEXT DEFAULT 'medium' CHECK (difficulty IN ('easy', 'medium', 'hard')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_jokes_difficulty ON jokes(difficulty);

ALTER TABLE jokes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read jokes" ON jokes
  FOR SELECT USING (true);

-- User history for jokes
CREATE TABLE user_jokes_history (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  question_id UUID NOT NULL REFERENCES jokes(id) ON DELETE CASCADE,
  last_used_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  PRIMARY KEY (user_id, question_id)
);

ALTER TABLE user_jokes_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own jokes history" ON user_jokes_history
  FOR ALL USING (auth.uid() = user_id);

-- ============================================================
-- MIGRATE DATA FROM game_questions
-- ============================================================
INSERT INTO trivia_questions (question, answer, difficulty, created_at)
SELECT question, answer, COALESCE(difficulty, 'medium'), created_at
FROM game_questions WHERE category = 'trivia';

INSERT INTO riddles (question, answer, difficulty, created_at)
SELECT question, answer, COALESCE(difficulty, 'medium'), created_at
FROM game_questions WHERE category = 'riddle';

INSERT INTO jokes (question, answer, difficulty, created_at)
SELECT question, answer, COALESCE(difficulty, 'medium'), created_at
FROM game_questions WHERE category = 'joke';

-- ============================================================
-- DROP OLD TABLE AND RELATED OBJECTS
-- ============================================================
-- Drop the old user_question_history table if it exists (was referenced but never created)
DROP TABLE IF EXISTS user_question_history;

-- Drop the old game_questions table
DROP TABLE IF EXISTS game_questions;
