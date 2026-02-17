-- Create face_images table for custom animal face images
CREATE TABLE IF NOT EXISTS face_images (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  image_url TEXT NOT NULL,
  display_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS policies
ALTER TABLE face_images ENABLE ROW LEVEL SECURITY;

-- Face images are viewable by authenticated users
CREATE POLICY "Face images are viewable by authenticated users"
  ON face_images FOR SELECT TO authenticated USING (true);
