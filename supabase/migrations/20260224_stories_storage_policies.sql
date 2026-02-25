-- Storage policies for stories bucket
-- Run this in the Supabase SQL editor

-- Allow public read access to all files in stories bucket
CREATE POLICY "Public read access for stories"
ON storage.objects FOR SELECT
USING (bucket_id = 'stories');

-- Allow authenticated users to upload audio files to stories bucket
CREATE POLICY "Authenticated users can upload audio to stories"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'stories'
  AND auth.role() = 'authenticated'
);

-- Allow authenticated users to update their uploaded files
CREATE POLICY "Authenticated users can update stories files"
ON storage.objects FOR UPDATE
USING (
  bucket_id = 'stories'
  AND auth.role() = 'authenticated'
);
