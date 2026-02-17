-- Add face_image_id to agents table
-- When face_image_id is set, use the animal face image instead of robot face
ALTER TABLE agents
  ADD COLUMN face_image_id UUID REFERENCES face_images(id) ON DELETE SET NULL;
