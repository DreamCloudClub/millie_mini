# Testing Checklist - Millie Mini Basic Subscription

## Pre-Test Setup ✅

- [x] WordPress snippet updated to check for `millie_mini_basic` role
- [x] Supabase SQL migration executed (`usage_tracking` table created)
- [x] Test user assigned `millie_mini_basic` role on website
- [x] Flutter app code updated with all changes

## Test Steps

### 1. **Verify Subscription Status Detection**
   - [ ] Open the app and log in with test user
   - [ ] Go to **Dashboard** → **AI Service** card
   - [ ] Should show: **"Basic"** status (green color)
   - [ ] Go to **AI Account Settings** page
   - [ ] Dream Cloud AI Account card should show:
     - Title: "Dream Cloud AI Account"
     - Status: **"Basic"** (green)
     - Usage: **"0.0M / 8.0M tokens used"** (below status)

### 2. **Test Usage Tracking**
   - [ ] Launch Millie (should work - no limit exceeded)
   - [ ] Have a conversation (make a few API calls)
   - [ ] Go back to **AI Account Settings** page
   - [ ] Usage should update: e.g., **"0.1M / 8.0M tokens used"**
   - [ ] Usage increments after each API call

### 3. **Test Usage Limit Check (Before Launch)**
   - [ ] **Note**: To test limit exceeded, you'll need to either:
     - Manually update Supabase: Set `tokens_used >= token_limit` in `usage_tracking` table
     - OR wait until you've used 8M tokens (not practical for testing)
   - [ ] If limit exceeded, pressing **"Launch Millie"** should:
     - Show modal: "Monthly Limit Exceeded"
     - Prevent launch
     - Show "Manage Subscription" button

### 4. **Test Refresh Button Check**
   - [ ] While in Face page, long-press to open control bar
   - [ ] Press **Refresh** button
   - [ ] If limit exceeded, should show same modal
   - [ ] If within limit, should refresh normally

### 5. **Verify Supabase Tracking**
   - [ ] Check Supabase `usage_tracking` table:
     ```sql
     SELECT * FROM usage_tracking 
     WHERE user_email = 'your-test-email@example.com'
     ORDER BY created_at DESC;
     ```
   - [ ] Should see one record for current month
   - [ ] `year_month` should be current month (e.g., "2024-01")
   - [ ] `tokens_used` should increment after each API call
   - [ ] `token_limit` should be `8000000` (8M)
   - [ ] `subscription_status` should be `"basic"`

### 6. **Test Monthly Reset (Optional)**
   - [ ] Can test by manually changing `year_month` in Supabase
   - [ ] Or wait until next month to verify automatic reset

## Expected Behavior

### ✅ Should Work:
- Subscription status shows as "Basic"
- Usage displays on AI Account Settings page
- Usage increments after each API call
- Can launch and use Millie normally (within limit)
- Usage limit check before launch/refresh

### ⚠️ If Issues:
- **Status not showing "Basic"**: Check WordPress API response
- **Usage not displaying**: Check Supabase connection, verify `get_current_usage` function works
- **Usage not incrementing**: Check API calls are completing, verify `record_usage` function works
- **Modal not showing**: Check usage limit check logic, verify tokens_used >= token_limit

## Quick Supabase Queries for Testing

### Check current usage:
```sql
SELECT * FROM usage_tracking 
WHERE user_email = 'your-email@example.com'
AND year_month = TO_CHAR(NOW(), 'YYYY-MM');
```

### Manually set limit exceeded (for testing):
```sql
UPDATE usage_tracking
SET tokens_used = token_limit
WHERE user_email = 'your-email@example.com'
AND year_month = TO_CHAR(NOW(), 'YYYY-MM');
```

### Reset usage (for testing):
```sql
UPDATE usage_tracking
SET tokens_used = 0
WHERE user_email = 'your-email@example.com'
AND year_month = TO_CHAR(NOW(), 'YYYY-MM');
```

## Notes

- Basic subscription = **8M tokens/month**
- Usage resets automatically at start of each month
- Usage is checked before launch and refresh, NOT during conversations
- Usage is recorded after each successful API call

