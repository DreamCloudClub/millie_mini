# Subscription System Update Summary

## Overview
Updated the subscription system to check for new user roles (`millie_mini_basic` and `millie_mini_pro`) and added monthly token usage tracking with limits.

## Changes Made

### 1. WordPress PHP Snippet (`wordpress_snippets/dreamcloud_subscription_api.php`)
- **Updated** to check for new roles:
  - `millie_mini_basic` → returns status `"basic"` (8M tokens/month)
  - `millie_mini_pro` → returns status `"pro"` (16M tokens/month)
  - `holder` → returns status `"holder"` (8M tokens/month, same as basic)
- **Removed** check for old `subscriber` role

### 2. Supabase Database (`supabase_usage_tracking.sql`)
Created a new `usage_tracking` table with:
- Monthly token usage tracking (resets each month)
- Token limits per subscription tier:
  - **Holder**: 8M tokens/month
  - **Basic**: 8M tokens/month
  - **Pro**: 16M tokens/month
- Helper functions:
  - `get_or_create_usage()` - Get or create current month's record
  - `check_usage_limit()` - Check if user can make API call
  - `record_usage()` - Record token usage after API call
  - `get_current_usage()` - Get current month's stats

### 3. Flutter Code Updates

#### Model (`lib/models/ai_service.dart`)
- Added `basic` and `pro` to `AIServiceStatus` enum
- Updated `isUsable` to include `basic` and `pro` statuses
- Updated `displayName` to show "Basic" and "Pro"

#### Provider (`lib/providers/ai_service_provider.dart`)
- Updated `updateDreamCloudSubscription()` to handle `basic` and `pro` status responses from API

#### UI (`lib/ai_services/edit_dream_cloud_page.dart`)
- Added status messages for `basic` and `pro` subscriptions
- Updated status colors:
  - Basic: Green (success)
  - Pro: Blue

#### Usage Tracking Service (`lib/services/usage_tracking_service.dart`)
New service for token usage tracking:
- `checkUsageLimit()` - Check if user has tokens remaining
- `recordUsage()` - Record token usage after API call
- `getCurrentUsage()` - Get current month's usage stats
- `getTokenLimit()` - Get token limit for subscription status
- `formatTokens()` - Format token count for display

## Token Limits

| Subscription Tier | Monthly Token Limit |
|-------------------|---------------------|
| Holder            | 8M tokens          |
| Basic             | 8M tokens          |
| Pro               | 16M tokens         |
| Trial             | 8M tokens          |
| Inactive/Other    | 0 tokens           |

## Setup Instructions

### 1. Update WordPress Snippet
Copy the updated PHP snippet from `wordpress_snippets/dreamcloud_subscription_api.php` to your WordPress site (via Code Snippets plugin or `functions.php`).

### 2. Run Supabase Migration
Execute the SQL file `supabase_usage_tracking.sql` in your Supabase SQL editor:
1. Go to Supabase Dashboard → SQL Editor
2. Create a new query
3. Copy/paste the contents of `supabase_usage_tracking.sql`
4. Run the query

This will create:
- `usage_tracking` table
- Helper functions for usage tracking
- Row Level Security policies

### 3. Update Flutter App
The Flutter code has been updated. You may need to:
1. Run `flutter pub get` to ensure all dependencies are up to date
2. Test the subscription status check flow
3. Integrate usage tracking into the voice pipeline (see below)

## Integration Notes

### Usage Tracking Integration
To integrate usage tracking into the voice pipeline, you'll need to:

1. **Before making API calls** - Check usage limit:
```dart
final usageCheck = await UsageTrackingService.checkUsageLimit(
  userId: userId,
  userEmail: userEmail,
  subscriptionStatus: aiService.status,
  tokensNeeded: estimatedTokens, // Estimate based on message length
);

if (!usageCheck['can_proceed']) {
  // Show error: "Monthly token limit reached"
  return;
}
```

2. **After API calls** - Record usage:
```dart
// Get actual token usage from API response
final tokensUsed = response.usage.totalTokens;

await UsageTrackingService.recordUsage(
  userId: userId,
  userEmail: userEmail,
  subscriptionStatus: aiService.status,
  tokensUsed: tokensUsed,
);
```

### Status Flow
1. User logs in → App checks subscription status via WordPress API
2. API returns `basic`, `pro`, or `holder` status
3. App stores status in `AIService` model
4. Before each API call, check usage limit
5. After each API call, record token usage
6. Monthly reset happens automatically (new `year_month` record)

## Testing Checklist

- [ ] WordPress API returns correct status for `millie_mini_basic` role
- [ ] WordPress API returns correct status for `millie_mini_pro` role
- [ ] WordPress API returns correct status for `holder` role
- [ ] Supabase `usage_tracking` table created successfully
- [ ] Supabase functions work correctly
- [ ] Flutter app displays correct status for basic/pro subscriptions
- [ ] Usage tracking service functions work
- [ ] Token limits are enforced correctly
- [ ] Monthly reset works (test by changing date)

## Next Steps

1. **Integrate usage tracking** into `voice_pipeline_service.dart`:
   - Check usage before LLM calls
   - Record usage after LLM calls
   - Show usage stats in UI

2. **Add usage display** to dashboard or account settings page:
   - Show tokens used / tokens limit
   - Show progress bar
   - Show days until reset

3. **Handle limit exceeded** gracefully:
   - Show friendly error message
   - Suggest upgrading to Pro
   - Link to subscription management

