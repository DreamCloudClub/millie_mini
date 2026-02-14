-- =============================================
-- ADD INTRO MESSAGE COLUMN TO AGENTS TABLE
-- =============================================
-- Run this in Supabase SQL Editor

-- Add intro_message column to agents table
ALTER TABLE agents 
ADD COLUMN IF NOT EXISTS intro_message TEXT DEFAULT 'Hello {username}, it''s me Millie your personal AI Agent. How can I help you?';

-- Update existing agents with default intro message if they don't have one
UPDATE agents 
SET intro_message = 'Hello {username}, it''s me Millie your personal AI Agent. How can I help you?'
WHERE intro_message IS NULL;

