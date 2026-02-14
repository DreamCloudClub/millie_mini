# Subscription Strategy - Direct Subscription Checking

## New Approach ✅

Instead of assigning WordPress roles, we now **check SUMO subscriptions directly** by querying the database for active subscriptions and their product IDs.

## Why This Is Better

1. **No role conflicts** - Don't fight with SUMO's role assignment
2. **More reliable** - Checks actual subscription data from SUMO
3. **Easier to debug** - Can see subscription status directly
4. **Automatic updates** - When SUMO changes subscription status, our check automatically reflects it

## How It Works

### API Endpoint (`dreamcloud_subscription_api.php`)
1. User email provided → Find WordPress user
2. **Priority 1**: Check for `holder` role (still uses roles)
3. **Priority 2**: Query SUMO subscriptions directly:
   - Looks for subscription posts (post types: `sumomemberships`, `sumosubscriptions`, `sumosubscription`)
   - Checks if status is `active`
   - Gets product ID from subscription
   - Returns `basic` if product ID = 8206
   - Returns `pro` if product ID = 8209

### Methods Used
- **Method 1**: Query SUMO subscription custom post types
- **Method 2**: Query through WooCommerce orders (fallback)
- Tries multiple meta keys to find product ID
- Falls back to parent order if product ID not in subscription meta

## Role Assignment Snippet (Optional)

The `sumo_subscription_role_assigner.php` snippet is now **optional**. It can still be useful for:
- Displaying roles in WordPress admin
- Other plugins that check roles
- Backup method (if subscription checking fails)

But it's **not required** for the app to work - the API endpoint checks subscriptions directly.

## Testing

### Step 1: Test the API directly
```bash
curl -X POST "https://your-site.com/wp-json/dreamcloud/v1/check-subscription" \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com"}'
```

### Step 2: Use debug helper
1. Install `subscription_check_debug.php` as a snippet
2. Visit: `https://your-site.com/?debug_subscription=USER_EMAIL`
3. See all subscriptions and meta data found

### Step 3: Test in app
1. Log in with test user
2. Go to AI Account Settings
3. Should show "Basic" or "Pro" status based on active subscription

## Troubleshooting

### If status shows "inactive":
1. Check if subscription exists in SUMO
2. Verify subscription status is "Active" (not "Pause" or "Cancelled")
3. Use debug helper to see what's found
4. Check if product ID matches 8206 or 8209

### If wrong status (basic vs pro):
1. Use debug helper to see detected product ID
2. Verify product ID in SUMO subscription matches expected (8206/8209)
3. Check if variation ID is being used instead of product ID

### To find SUMO subscription post type:
Check what custom post types SUMO creates:
- Go to WordPress admin → Plugins → SUMO Subscriptions
- Or check database `wp_posts` table for SUMO-related post types
- Update `$subscription_post_types` array in the API endpoint if needed

