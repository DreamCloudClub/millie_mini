-- =============================================
-- ADD OPENWEATHER API KEY CONFIGURATION
-- =============================================
-- This adds the OpenWeather API key to service_config
-- Used for weather queries via the AI assistant

-- Insert OpenWeather API key (replace with your actual key)
INSERT INTO public.service_config (service_name, api_key, is_active)
VALUES ('openweather', 'YOUR_OPENWEATHER_API_KEY_HERE', true)
ON CONFLICT (service_name)
DO UPDATE SET api_key = EXCLUDED.api_key, updated_at = NOW();

-- =============================================
-- HELPER FUNCTION: Get OpenWeather API Key
-- =============================================

CREATE OR REPLACE FUNCTION public.get_openweather_key()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  key_value TEXT;
BEGIN
  IF auth.role() != 'authenticated' THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT api_key INTO key_value
  FROM public.service_config
  WHERE service_name = 'openweather' AND is_active = true
  LIMIT 1;

  RETURN key_value;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_openweather_key() TO authenticated;
