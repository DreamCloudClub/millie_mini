-- User history for animals
CREATE TABLE user_animal_history (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  animal_id UUID NOT NULL REFERENCES animals(id) ON DELETE CASCADE,
  last_used_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  PRIMARY KEY (user_id, animal_id)
);

ALTER TABLE user_animal_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own animal history" ON user_animal_history
  FOR ALL USING (auth.uid() = user_id);
