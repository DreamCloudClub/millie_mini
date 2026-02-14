# SUMO Subscriptions - Role Assignment Setup

## Overview
This snippet automatically assigns WordPress user roles when users purchase SUMO subscriptions:
- **Product ID 8206** → `millie_mini_basic` role
- **Product ID 8209** → `millie_mini_pro` role

## Installation

### Option 1: Code Snippets Plugin (Recommended)
1. Install "Code Snippets" plugin if you don't have it
2. Go to **Snippets → Add New**
3. Copy the entire contents of `sumo_subscription_role_assigner.php`
4. Paste into the snippet code area
5. Set **Title**: "SUMO Subscriptions - Millie Mini Role Assigner"
6. Set **Run snippet**: "Everywhere" or "Only in admin"
7. Click **Save Changes and Activate**

### Option 2: functions.php
1. Go to **Appearance → Theme Editor → functions.php**
2. Add the entire contents of `sumo_subscription_role_assigner.php` at the bottom
3. Click **Update File**

## How It Works

### When Subscription is Activated:
1. **Hooks triggered**:
   - `woocommerce_order_status_completed` - When order completes
   - `woocommerce_payment_complete` - When payment is received
   - `sumosubscriptions_subscription_activated` - SUMO-specific activation (if available)

2. **Process**:
   - Gets order/subscription information
   - Checks product ID (8206 or 8209)
   - Removes any existing Millie Mini roles
   - Assigns appropriate role based on product ID

### When Subscription is Cancelled/Expired:
1. **Hooks triggered**:
   - `sumosubscriptions_subscription_cancelled`
   - `sumosubscriptions_subscription_expired`
   - `sumosubscriptions_subscription_paused`

2. **Process**:
   - Removes both `millie_mini_basic` and `millie_mini_pro` roles
   - User returns to default role

## Product IDs
- **8206** = Millie Mini Basic → `millie_mini_basic` role
- **8209** = Millie Mini Pro → `millie_mini_pro` role

## Testing

### Test Basic Subscription (8206):
1. Create a test order with product ID 8206
2. Complete the order (or mark as completed)
3. Check user roles:
   - User should have `millie_mini_basic` role
   - Can verify via **Users → Edit User**

### Test Pro Subscription (8209):
1. Create a test order with product ID 8209
2. Complete the order (or mark as completed)
3. Check user roles:
   - User should have `millie_mini_pro` role

### Verify Role Assignment:
1. Go to **Users → All Users**
2. Click on the test user
3. Check **Role** dropdown - should show assigned role

## Debugging

### Step 1: Enable WordPress Debug Logging
Add to `wp-config.php`:
```php
define('WP_DEBUG', true);
define('WP_DEBUG_LOG', true);
define('WP_DEBUG_DISPLAY', false);
```

### Step 2: Install Debug Helper (Optional but Recommended)
1. Copy `sumo_debug_helper.php` to a new snippet
2. Activate it temporarily
3. Make a test purchase
4. Check `wp-content/debug.log` to see:
   - Which hooks are firing
   - What product IDs are detected
   - What subscription meta exists

### Step 3: Check Logs
The main snippet logs everything to `wp-content/debug.log`:
- Look for lines starting with "SUMO:"
- Check which hooks are firing
- Verify product IDs match 8206 or 8209
- See if roles are being assigned

### Step 4: Manual Role Test
Test if role assignment works manually:
```
https://your-site.com/?test_sumo_role=USER_ID&product_id=8206
```
Replace `USER_ID` with actual user ID (must be admin to run this)

### Common Issues:

1. **Role not assigned**:
   - Check if product IDs match (8206/8209)
   - Verify order status is "completed"
   - Check WordPress debug log for errors

2. **Wrong role assigned**:
   - Verify product ID in order
   - Check if variation ID is used instead of product ID
   - Check debug log for which product ID was detected

3. **Hook not firing**:
   - Some SUMO versions may use different hooks
   - Check SUMO documentation for specific hooks
   - May need to adjust hook names based on your SUMO version

## Alternative Hooks (if above don't work)

If the standard hooks don't work, try these SUMO-specific hooks:

```php
// Alternative hooks to try:
add_action('sumosubscriptions_order_status_changed', 'sumo_assign_subscription_role', 10, 1);
add_action('sumo_subscription_status_activated', 'sumo_assign_subscription_role_from_subscription', 10, 2);
add_action('sumosubscriptions_order_status_active', 'sumo_assign_subscription_role', 10, 1);
```

## Notes

- **Role Cleanup**: The snippet automatically removes existing Millie Mini roles before assigning new ones
- **Multiple Products**: If order contains multiple subscription products, last one processed wins
- **User Identification**: Uses order user ID, falls back to billing email if no user ID
- **Error Logging**: All role assignments are logged to help with debugging

## Verification in App

After role is assigned:
1. User should see "Basic" or "Pro" status in the app
2. API endpoint `/wp-json/dreamcloud/v1/check-subscription` should return correct status
3. Token limits should be applied (8M for Basic, 16M for Pro)

