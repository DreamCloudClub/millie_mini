-- Add quiz_hint column for animal quiz descriptions that don't reveal the name
ALTER TABLE animals ADD COLUMN IF NOT EXISTS quiz_hint TEXT;

-- Add comment explaining the column
COMMENT ON COLUMN animals.quiz_hint IS 'Quiz description that does not include the animal name. Format: "This is a [type], it [description]..."';
