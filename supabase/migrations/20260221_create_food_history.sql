-- User history for foods
CREATE TABLE user_food_history (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  food_id UUID NOT NULL REFERENCES foods(id) ON DELETE CASCADE,
  last_used_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  PRIMARY KEY (user_id, food_id)
);

ALTER TABLE user_food_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own food history" ON user_food_history
  FOR ALL USING (auth.uid() = user_id);
