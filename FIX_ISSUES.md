# Fixing App Issues

## Issues Found & Fixed:

### 1. ✅ Default Face Showing Blue Round Eyes
**Fixed:** Updated fallback values in `agent_provider.dart` to use white (0) and rounded squares (2) instead of blue (1) and circles (0).

### 2. ✅ Splash Screen Background
**Fixed:** Updated Android native splash screen background to match Flutter splash (dreamCloudBlue #30C1FF).

### 3. ⚠️ Icon Not Updating
**Issue:** Android caches app icons aggressively. Need to fully uninstall the app first.

## Steps to Fix Everything:

### Step 1: Uninstall the app completely
On your Samsung A7:
1. Long press the app icon
2. Tap "Uninstall" or drag to uninstall
3. Confirm uninstall

### Step 2: Rebuild and reinstall
```bash
flutter clean
flutter pub get
dart run flutter_launcher_icons
flutter run -d R9ZX80AFYBF
```

### Step 3: Verify fixes
- ✅ Icon should show full face (no cropping)
- ✅ Native splash screen should be blue (not black/white)
- ✅ Flutter splash screen shows correctly
- ✅ Default agent has white rounded square eyes

## If Default Agent Still Shows Blue Round Eyes:

The agent might be stored in Supabase with wrong values. Check and update:

```sql
-- Check your agent in Supabase
SELECT * FROM agents WHERE user_id = 'YOUR_USER_ID';

-- If face_color is 1 (blue) or eye_shape is 0 (circles), update it:
UPDATE agents 
SET face_color = 0,  -- white
    eye_shape = 2    -- rounded squares
WHERE user_id = 'YOUR_USER_ID' AND is_active = true;
```

Or just edit the agent in the app - it should now default to white/rounded squares for new agents.

