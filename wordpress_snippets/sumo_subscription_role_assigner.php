<?php
/**
 * SUMO Subscriptions - Auto Assign User Roles
 * Assigns millie_mini_basic or millie_mini_pro role based on subscription product ID
 * 
 * Product IDs:
 * - 8206 = Millie Mini Basic (8M tokens/month)
 * - 8209 = Millie Mini Pro (16M tokens/month)
 * 
 * Install via Code Snippets plugin or functions.php
 */

// Primary hook: SUMO subscription status changed to active
add_action('sumosubscriptions_order_status_active', 'sumo_assign_subscription_role_on_active', 10, 1);
add_action('sumosubscriptions_subscription_status_active', 'sumo_assign_subscription_role_on_active', 10, 1);

// Handle subscription status changes (pause, resume, active) - PRIMARY for manual status changes
add_action('sumosubscriptions_order_status_changed', 'sumo_handle_status_change', 10, 3);
add_action('sumosubscriptions_subscription_status_changed', 'sumo_handle_status_change', 10, 3);

// Secondary hooks: Order completion and payment
add_action('woocommerce_order_status_completed', 'sumo_assign_subscription_role', 10, 1);
add_action('woocommerce_payment_complete', 'sumo_assign_subscription_role', 10, 1);

// SUMO specific hooks (try multiple variations)
add_action('sumosubscriptions_subscription_activated', 'sumo_assign_subscription_role_from_subscription', 10, 2);

// Hook into subscription creation
add_action('sumosubscriptions_subscription_created', 'sumo_assign_subscription_role_from_subscription', 10, 2);

/**
 * Assign user role when SUMO subscription becomes active
 */
function sumo_assign_subscription_role_on_active($order_id) {
    error_log("SUMO HOOK FIRED: sumosubscriptions_order_status_active - Order ID: $order_id");
    sumo_assign_subscription_role($order_id);
}

/**
 * Handle subscription status changes (pause, resume, active)
 * This handles manual status changes in SUMO admin
 * Works with both order IDs and subscription IDs
 */
function sumo_handle_status_change($order_or_subscription_id, $old_status, $new_status) {
    error_log("SUMO HOOK FIRED: Status Change - ID: $order_or_subscription_id, Old: '$old_status', New: '$new_status'");
    
    try {
        // When status becomes active/resume - assign role
        if ($new_status === 'active' || $new_status === 'resume' || $new_status === 'completed' || $new_status === 'Active') {
            error_log("SUMO: Status is active/resume - assigning role");
            // Try as order ID first
            $order = wc_get_order($order_or_subscription_id);
            if ($order) {
                sumo_assign_subscription_role($order_or_subscription_id);
            } else {
                // Might be subscription ID, try getting order from subscription
                sumo_assign_subscription_role_from_subscription($order_or_subscription_id, null);
            }
        }
        // When status becomes pause/cancelled/expired - remove role (don't break on pause)
        elseif ($new_status === 'pause' || $new_status === 'paused' || $new_status === 'Pause' || 
                $new_status === 'cancelled' || $new_status === 'expired') {
            error_log("SUMO: Status is paused/cancelled - removing role");
            // Try as order ID first
            $order = wc_get_order($order_or_subscription_id);
            if ($order) {
                sumo_remove_role_from_order($order_or_subscription_id);
            } else {
                // Might be subscription ID, remove role
                sumo_remove_subscription_role($order_or_subscription_id, null);
            }
        }
    } catch (Exception $e) {
        error_log("SUMO ERROR in status change handler: " . $e->getMessage());
        // Don't break - just log the error
    } catch (Error $e) {
        error_log("SUMO FATAL ERROR in status change handler: " . $e->getMessage());
        // Don't break - just log the error
    }
}


/**
 * Assign user role based on subscription product ID
 * Called when WooCommerce order is completed or subscription activated
 */
function sumo_assign_subscription_role($order_id) {
    if (!$order_id) {
        error_log("SUMO: No order ID provided");
        return;
    }
    
    error_log("SUMO: Processing order ID: $order_id");
    
    $order = wc_get_order($order_id);
    
    if (!$order) {
        error_log("SUMO: Order not found: $order_id");
        return;
    }
    
    $user_id = $order->get_user_id();
    
    if (!$user_id) {
        // Try to get user from billing email if no user ID
        $billing_email = $order->get_billing_email();
        error_log("SUMO: No user ID, trying email: $billing_email");
        if ($billing_email) {
            $user = get_user_by('email', $billing_email);
            if ($user) {
                $user_id = $user->ID;
                error_log("SUMO: Found user by email, ID: $user_id");
            } else {
                error_log("SUMO: No user found for email: $billing_email");
                return; // No user found
            }
        } else {
            error_log("SUMO: No user ID or email found");
            return; // No user ID or email
        }
    }
    
    $user = get_user_by('id', $user_id);
    if (!$user) {
        error_log("SUMO: User not found for ID: $user_id");
        return;
    }
    
    error_log("SUMO: Processing user ID: $user_id, Current roles: " . implode(', ', $user->roles));
    
    // Get all items in the order
    $items = $order->get_items();
    
    if (empty($items)) {
        error_log("SUMO: No items found in order: $order_id");
        return;
    }
    
    $role_assigned = false;
    
    foreach ($items as $item) {
        $product_id = $item->get_product_id();
        $variation_id = $item->get_variation_id();
        $item_name = $item->get_name();
        
        error_log("SUMO: Item - Name: $item_name, Product ID: $product_id, Variation ID: $variation_id");
        
        // Check product ID or variation ID
        $check_id = $variation_id && $variation_id > 0 ? $variation_id : $product_id;
        
        error_log("SUMO: Checking ID: $check_id (Product: $product_id, Variation: $variation_id)");
        
        // Remove existing Millie Mini roles first (only once)
        if (!$role_assigned) {
            $user->remove_role('millie_mini_basic');
            $user->remove_role('millie_mini_pro');
            // Also remove subscriber role if SUMO added it
            $user->remove_role('subscriber');
        }
        
        // Assign new role based on product ID
        if ($check_id == 8206 || $product_id == 8206) {
            // Millie Mini Basic
            $user->add_role('millie_mini_basic');
            // Make sure subscriber role is removed
            $user->remove_role('subscriber');
            error_log("SUMO: ✓ Assigned millie_mini_basic role to user ID: $user_id (Order: $order_id, Product: $check_id)");
            $role_assigned = true;
        } elseif ($check_id == 8209 || $product_id == 8209) {
            // Millie Mini Pro
            $user->add_role('millie_mini_pro');
            // Make sure subscriber role is removed
            $user->remove_role('subscriber');
            error_log("SUMO: ✓ Assigned millie_mini_pro role to user ID: $user_id (Order: $order_id, Product: $check_id)");
            $role_assigned = true;
        } else {
            error_log("SUMO: Product ID $check_id doesn't match 8206 or 8209 - skipping");
        }
    }
    
    if (!$role_assigned) {
        error_log("SUMO: WARNING - No role assigned for order $order_id. No matching product IDs found.");
    }
}

/**
 * Assign user role from SUMO subscription object
 * Called when SUMO subscription is specifically activated
 */
function sumo_assign_subscription_role_from_subscription($subscription_id, $subscription = null) {
    error_log("SUMO HOOK FIRED: sumosubscriptions_subscription_activated/created - Subscription ID: $subscription_id");
    
    if (!$subscription_id) {
        error_log("SUMO: No subscription ID provided");
        return;
    }
    
    // Get subscription post meta if subscription object not provided
    if (!$subscription) {
        $subscription_post = get_post($subscription_id);
        if (!$subscription_post) {
            error_log("SUMO: Subscription post not found: $subscription_id");
            return;
        }
    }
    
    // Get user ID from subscription
    $user_id = 0;
    
    if (is_object($subscription)) {
        $user_id = isset($subscription->user_id) ? $subscription->user_id : 0;
    }
    
    // Try to get from post meta if not found
    if (!$user_id) {
        $user_id = get_post_meta($subscription_id, 'sumo_get_user_id', true);
        if (!$user_id) {
            $user_id = get_post_meta($subscription_id, '_customer_user', true);
        }
    }
    
    if (!$user_id) {
        error_log("SUMO: Could not find user ID for subscription: $subscription_id");
        return;
    }
    
    error_log("SUMO: Found user ID: $user_id for subscription: $subscription_id");
    
    $user = get_user_by('id', $user_id);
    if (!$user) {
        error_log("SUMO: User not found: $user_id");
        return;
    }
    
    // Get product ID from subscription meta
    $product_id = 0;
    
    // Try multiple meta keys that SUMO might use
    $product_id = get_post_meta($subscription_id, 'sumo_get_product_id', true);
    if (!$product_id) {
        $product_id = get_post_meta($subscription_id, '_product_id', true);
    }
    if (!$product_id) {
        $product_id = get_post_meta($subscription_id, '_variation_id', true);
    }
    
    // Also try from order if subscription has parent order
    if (!$product_id) {
        $parent_order_id = get_post_meta($subscription_id, 'sumo_get_parent_order_id', true);
        if (!$parent_order_id) {
            $parent_order_id = get_post_meta($subscription_id, '_parent_order_id', true);
        }
        
        if ($parent_order_id) {
            error_log("SUMO: Getting product ID from parent order: $parent_order_id");
            $order = wc_get_order($parent_order_id);
            if ($order) {
                $items = $order->get_items();
                foreach ($items as $item) {
                    $product_id = $item->get_variation_id() ? $item->get_variation_id() : $item->get_product_id();
                    error_log("SUMO: Found product ID from order: $product_id");
                    break;
                }
            }
        }
    }
    
    if (!$product_id) {
        error_log("SUMO: Could not determine product ID for subscription: $subscription_id");
        return;
    }
    
    error_log("SUMO: Processing subscription $subscription_id, User: $user_id, Product: $product_id");
    
    // Remove existing Millie Mini roles first
    $user->remove_role('millie_mini_basic');
    $user->remove_role('millie_mini_pro');
    // Also remove subscriber role if SUMO added it
    $user->remove_role('subscriber');
    
    // Assign new role based on product ID
    if ($product_id == 8206) {
        // Millie Mini Basic
        $user->add_role('millie_mini_basic');
        // Make sure subscriber role is removed
        $user->remove_role('subscriber');
        error_log("SUMO: ✓ Assigned millie_mini_basic role to user ID: $user_id (Subscription: $subscription_id, Product: $product_id)");
    } elseif ($product_id == 8209) {
        // Millie Mini Pro
        $user->add_role('millie_mini_pro');
        // Make sure subscriber role is removed
        $user->remove_role('subscriber');
        error_log("SUMO: ✓ Assigned millie_mini_pro role to user ID: $user_id (Subscription: $subscription_id, Product: $product_id)");
    } else {
        error_log("SUMO: Product ID $product_id doesn't match 8206 or 8209");
    }
}

/**
 * Remove role from user based on order ID
 * Used when subscription is paused/cancelled
 */
function sumo_remove_role_from_order($order_id) {
    if (!$order_id) {
        return;
    }
    
    try {
        $order = wc_get_order($order_id);
        
        if (!$order) {
            error_log("SUMO: Order not found for removal: $order_id");
            return;
        }
        
        $user_id = $order->get_user_id();
        
        if (!$user_id) {
            $billing_email = $order->get_billing_email();
            if ($billing_email) {
                $user = get_user_by('email', $billing_email);
                if ($user) {
                    $user_id = $user->ID;
                }
            }
        }
        
        if ($user_id) {
            $user = get_user_by('id', $user_id);
            if ($user) {
                $user->remove_role('millie_mini_basic');
                $user->remove_role('millie_mini_pro');
                error_log("SUMO: ✓ Removed Millie Mini roles from user ID: $user_id (Order: $order_id)");
            }
        }
    } catch (Exception $e) {
        error_log("SUMO ERROR removing role: " . $e->getMessage());
    }
}

/**
 * Remove role when subscription is cancelled/expired
 */
add_action('sumosubscriptions_subscription_cancelled', 'sumo_remove_subscription_role', 10, 2);
add_action('sumosubscriptions_subscription_expired', 'sumo_remove_subscription_role', 10, 2);
add_action('sumosubscriptions_subscription_paused', 'sumo_remove_subscription_role', 10, 2);
add_action('sumosubscriptions_order_status_pause', 'sumo_remove_role_from_order', 10, 1);
add_action('sumosubscriptions_order_status_paused', 'sumo_remove_role_from_order', 10, 1);

function sumo_remove_subscription_role($subscription_id, $subscription = null) {
    if (!$subscription_id) {
        return;
    }
    
    try {
        $user_id = 0;
        
        if (is_object($subscription) && isset($subscription->user_id)) {
            $user_id = $subscription->user_id;
        }
        
        // Try to get from meta if not found
        if (!$user_id) {
            $user_id = get_post_meta($subscription_id, 'sumo_get_user_id', true);
            if (!$user_id) {
                $user_id = get_post_meta($subscription_id, '_customer_user', true);
            }
        }
        
        // Also try to get from parent order
        if (!$user_id) {
            $parent_order_id = get_post_meta($subscription_id, 'sumo_get_parent_order_id', true);
            if (!$parent_order_id) {
                $parent_order_id = get_post_meta($subscription_id, '_parent_order_id', true);
            }
            
            if ($parent_order_id) {
                $order = wc_get_order($parent_order_id);
                if ($order) {
                    $user_id = $order->get_user_id();
                }
            }
        }
        
        if ($user_id) {
            $user = get_user_by('id', $user_id);
            if ($user) {
                $user->remove_role('millie_mini_basic');
                $user->remove_role('millie_mini_pro');
                error_log("SUMO: ✓ Removed Millie Mini roles from user ID: $user_id (Subscription: $subscription_id)");
            }
        }
    } catch (Exception $e) {
        error_log("SUMO ERROR in remove_subscription_role: " . $e->getMessage());
    }
}

