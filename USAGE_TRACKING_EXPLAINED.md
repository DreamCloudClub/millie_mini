# Usage Tracking System - How It Works

## Overview

The usage tracking system automatically tracks token usage per user per month and resets at the start of each calendar month.

## Table Structure

The `usage_tracking` table stores one record per user per month:

```sql
- user_id: UUID (links to auth.users)
- user_email: TEXT
- year_month: TEXT (format: "YYYY-MM", e.g., "2024-01")
- tokens_used: BIGINT (running total for the month)
- token_limit: BIGINT (8M or 16M based on subscription)
- subscription_status: TEXT (holder/basic/pro)
- created_at: TIMESTAMP
- updated_at: TIMESTAMP

UNIQUE constraint on (user_id, year_month)
```

## How Usage is Recorded

### After Each API Call

1. **LLM API call completes** → Returns token usage (prompt + completion tokens)
2. **`UsageTrackingService.recordUsage()` is called** in `voice_pipeline_service.dart`
3. **Calls Supabase `record_usage()` function** which:
   - Calls `get_or_create_usage()` to get/create the current month's record
   - **Adds** the new tokens to the existing `tokens_used` value:
     ```sql
     UPDATE usage_tracking
     SET tokens_used = tokens_used + p_tokens_used
     WHERE id = v_record.id
     ```

### Example Flow:

**January 15th - First call:**
- User makes API call → Uses 500 tokens
- Record created: `year_month = "2024-01"`, `tokens_used = 500`

**January 20th - Second call:**
- User makes API call → Uses 1200 tokens
- Record updated: `year_month = "2024-01"`, `tokens_used = 1700` (500 + 1200)

**January 25th - Third call:**
- User makes API call → Uses 800 tokens
- Record updated: `year_month = "2024-01"`, `tokens_used = 2500` (1700 + 800)

## Monthly Reset - How It Works

### Automatic Reset Logic

The reset happens **automatically** based on the `year_month` field:

1. **`year_month` is calculated from current date:**
   ```sql
   v_year_month := TO_CHAR(NOW(), 'YYYY-MM');
   ```
   - This gives: "2024-01" in January, "2024-02" in February, etc.

2. **When a new month starts:**
   - `TO_CHAR(NOW(), 'YYYY-MM')` returns a different value
   - Example: On February 1st, it returns "2024-02" instead of "2024-01"

3. **New record is created automatically:**
   - When `recordUsage()` is called in the new month
   - `get_or_create_usage()` looks for a record with `year_month = "2024-02"`
   - No record exists → Creates new one with `tokens_used = 0`
   - Old January record remains in database (historical data)

### Example: Month Transition

**January 31st - Last call:**
- Record: `year_month = "2024-01"`, `tokens_used = 7500000`

**February 1st - First call of new month:**
- System calculates: `year_month = "2024-02"`
- Looks for record with `year_month = "2024-02"` → **Not found**
- Creates new record: `year_month = "2024-02"`, `tokens_used = 0`, `token_limit = 8000000`
- User starts fresh with full limit!

**Old January record:**
- Still exists in database: `year_month = "2024-01"`, `tokens_used = 7500000`
- Can be used for historical reporting/analytics

## Key Functions

### 1. `get_or_create_usage()`
- Gets current month's record OR creates new one if it doesn't exist
- Calculates `year_month` from current date
- Sets `token_limit` based on subscription status
- **This is called by both `check_usage_limit()` and `record_usage()`**

### 2. `record_usage()`
- Gets/creates current month's record
- **Adds** tokens to existing `tokens_used` (incremental update)
- Updates `updated_at` timestamp

### 3. `get_current_usage()`
- Gets current month's usage stats
- Returns: `tokens_used`, `token_limit`, `tokens_remaining`

## Important Points

### ✅ Automatic Reset
- **No manual intervention needed** - reset happens automatically
- Based on calendar month (server timezone)
- New month = new record with `tokens_used = 0`

### ✅ Running Total
- `tokens_used` is a **running total** for the month
- Each API call **adds** to the existing value
- Example: 1000 + 500 + 300 = 1800 tokens used

### ✅ Persistent History
- Old month records are kept in database
- Can query historical usage if needed
- Example: See how much was used in January vs February

### ✅ Timezone Consideration
- Uses server time (Supabase server timezone)
- Reset happens at midnight server time on the 1st of each month
- If your server is in UTC, reset happens at UTC midnight

## Query Examples

### Get current month's usage:
```sql
SELECT * FROM usage_tracking
WHERE user_id = 'user-uuid-here'
AND year_month = TO_CHAR(NOW(), 'YYYY-MM');
```

### Get all historical usage:
```sql
SELECT year_month, tokens_used, token_limit
FROM usage_tracking
WHERE user_id = 'user-uuid-here'
ORDER BY year_month DESC;
```

### Check if user exceeded limit this month:
```sql
SELECT 
  tokens_used >= token_limit as is_exceeded,
  tokens_used,
  token_limit,
  tokens_used - token_limit as overage
FROM usage_tracking
WHERE user_id = 'user-uuid-here'
AND year_month = TO_CHAR(NOW(), 'YYYY-MM');
```

## In Your App

### When Usage is Recorded:
- ✅ After every successful LLM API call
- ✅ Automatic (no user action needed)
- ✅ Non-blocking (errors don't stop the app)

### When Usage is Checked:
- ✅ Before launch (dashboard)
- ✅ Before refresh (face page)
- ❌ **NOT** during conversations (after removal)

### Reset Timing:
- ✅ Automatic at start of each calendar month
- ✅ Based on Supabase server timezone
- ✅ New record created with `tokens_used = 0`

