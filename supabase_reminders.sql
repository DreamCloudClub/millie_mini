-- Reminders Table for Millie Mini AI
-- Stores user reminders with recurrence and completion tracking

-- Create the reminders table
CREATE TABLE IF NOT EXISTS public.reminders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    scheduled_at TIMESTAMPTZ NOT NULL, -- When to trigger the reminder (may be before actual event time)
    event_time TIMESTAMPTZ, -- Optional: Actual event time (if different from scheduled_at)
    advance_notice_minutes INTEGER, -- Optional: Minutes before event to remind (e.g., 60 for 1 hour)
    recurrence TEXT NOT NULL DEFAULT 'none' CHECK (recurrence IN ('none', 'daily', 'weekly', 'monthly')),
    recurrence_end_date TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    reminder_sent BOOLEAN NOT NULL DEFAULT false,
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Create indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_reminders_user_scheduled 
    ON public.reminders(user_id, scheduled_at) 
    WHERE completed_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_reminders_scheduled_sent 
    ON public.reminders(scheduled_at, reminder_sent) 
    WHERE completed_at IS NULL AND reminder_sent = false;

CREATE INDEX IF NOT EXISTS idx_reminders_user_completed 
    ON public.reminders(user_id, completed_at) 
    WHERE completed_at IS NOT NULL;

-- Function to automatically update updated_at timestamp
CREATE OR REPLACE FUNCTION public.update_reminders_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to automatically update updated_at
CREATE TRIGGER update_reminders_updated_at
    BEFORE UPDATE ON public.reminders
    FOR EACH ROW
    EXECUTE FUNCTION public.update_reminders_updated_at();

-- Enable Row Level Security
ALTER TABLE public.reminders ENABLE ROW LEVEL SECURITY;

-- Policy: Users can view their own reminders
CREATE POLICY "Users can view own reminders"
    ON public.reminders FOR SELECT
    USING (auth.uid() = user_id);

-- Policy: Users can insert their own reminders
CREATE POLICY "Users can insert own reminders"
    ON public.reminders FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Policy: Users can update their own reminders
CREATE POLICY "Users can update own reminders"
    ON public.reminders FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Policy: Users can delete their own reminders
CREATE POLICY "Users can delete own reminders"
    ON public.reminders FOR DELETE
    USING (auth.uid() = user_id);

-- Policy: Service role can manage all reminders (for scheduler)
CREATE POLICY "Service role can manage all reminders"
    ON public.reminders FOR ALL
    USING (auth.jwt() ->> 'role' = 'service_role');

