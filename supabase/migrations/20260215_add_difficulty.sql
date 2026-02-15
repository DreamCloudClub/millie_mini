-- Add difficulty column to game_questions table
-- Difficulty levels:
--   'easy'   = Pre-K
--   'medium' = Elementary
--   'hard'   = High School and above

-- Add the difficulty column with default value of 'medium'
ALTER TABLE game_questions
ADD COLUMN IF NOT EXISTS difficulty TEXT DEFAULT 'medium'
CHECK (difficulty IN ('easy', 'medium', 'hard'));

-- Create index for efficient difficulty filtering
CREATE INDEX IF NOT EXISTS idx_game_questions_difficulty
ON game_questions(difficulty);

-- Create composite index for category + difficulty queries
CREATE INDEX IF NOT EXISTS idx_game_questions_category_difficulty
ON game_questions(category, difficulty);

-- Note: Existing questions default to 'medium'
-- Add age-appropriate questions manually:
--   Easy (Pre-K): Simple riddles, knock-knock jokes, basic trivia
--   Medium (Elementary): Word puzzles, puns, general knowledge
--   Hard (High School+): Logic puzzles, wordplay, advanced trivia
