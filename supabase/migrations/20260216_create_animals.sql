-- Animals table for animal lessons/quizzes
CREATE TABLE IF NOT EXISTS animals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type TEXT NOT NULL,              -- 'mammal', 'bird', 'fish', 'reptile', 'amphibian', 'insect', 'crustacean'
  name TEXT NOT NULL,              -- 'Lion', 'Eagle', etc.
  image_url TEXT,                  -- URL to image in storage bucket
  narration_text TEXT NOT NULL,    -- Full narration script
  lesson_order INT NOT NULL,       -- Sequence within type
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for efficient querying
CREATE INDEX idx_animals_type ON animals(type);

-- Enable RLS
ALTER TABLE animals ENABLE ROW LEVEL SECURITY;

-- Anyone can read
CREATE POLICY "Anyone can read animals" ON animals
  FOR SELECT USING (true);
