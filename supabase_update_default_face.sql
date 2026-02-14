-- =============================================
-- UPDATE DEFAULT FACE COLOR AND EYE SHAPE
-- =============================================
-- Change defaults to: White face, Rounded Square eyes
-- Run this in Supabase SQL Editor

-- Update table defaults
ALTER TABLE agents 
ALTER COLUMN face_color SET DEFAULT 0; -- 0 = white (was 1 = blue)

ALTER TABLE agents 
ALTER COLUMN eye_shape SET DEFAULT 2; -- 2 = roundedSquares (was 0 = circles)

-- Update the trigger function to explicitly set new defaults for new agents
CREATE OR REPLACE FUNCTION public.handle_new_profile()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.agents (user_id, name, face_color, eye_shape, is_active)
  VALUES (NEW.id, 'Millie', 0, 2, true); -- White face, Rounded Squares
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Note: This only affects NEW agents created after running this migration
-- Existing agents keep their current face color and eye shape

