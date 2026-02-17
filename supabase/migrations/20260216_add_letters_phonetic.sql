-- Add letters_phonetic column to spelling_words table
-- This stores the phonetic pronunciation of each letter for TTS
-- Example: "apple" -> "Ay Pee Pee El Ee"
ALTER TABLE spelling_words
ADD COLUMN IF NOT EXISTS letters_phonetic TEXT;
