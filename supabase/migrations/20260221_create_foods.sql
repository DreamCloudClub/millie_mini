-- Foods table for food lessons/quizzes
CREATE TABLE IF NOT EXISTS foods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category TEXT NOT NULL,         -- 'fruit', 'veggies', 'meat', 'grains', 'dairy', 'nuts'
  name TEXT NOT NULL,             -- 'Apple', 'Carrot', etc.
  image_url TEXT,                 -- Full URL to image in storage bucket
  narration_text TEXT NOT NULL,   -- Full narration script (used for lessons + generates quiz hint)
  quiz_hint TEXT,                 -- Optional custom hint for quizzes (if NULL, uses first 2 sentences of narration)
  narration_audio_url TEXT,       -- Cached TTS audio URL (populated after first playback)
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for efficient querying
CREATE INDEX idx_foods_category ON foods(category);

-- Enable RLS
ALTER TABLE foods ENABLE ROW LEVEL SECURITY;

-- Anyone can read
CREATE POLICY "Anyone can read foods" ON foods
  FOR SELECT USING (true);
