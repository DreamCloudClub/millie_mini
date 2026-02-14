<?php
/**
 * SUMO Subscriptions - Debug Helper
 * Use this to test and see what's happening with orders/subscriptions
 * 
 * This will help you identify:
 * - What hooks are firing
 * - What product IDs are in orders
 * - What meta data exists on subscriptions
 * 
 * Install separately, test, then remove after debugging
 */

// Enable WordPress debug logging
define('WP_DEBUG', true);
define('WP_DEBUG_LOG', true);

// Hook into ALL order status changes to see what's happening
add_action('woocommerce_order_status_changed', 'sumo_debug_order_status_change', 10, 3);
add_action('woocommerce_order_status_completed', 'sumo_debug_order_completed', 10, 1);
add_action('woocommerce_payment_complete', 'sumo_debug_payment_complete', 10, 1);

// Hook into ALL SUMO events
add_action('sumosubscriptions_order_status_active', 'sumo_debug_sumo_active', 10, 1);
add_action('sumosubscriptions_subscription_status_active', 'sumo_debug_sumo_active', 10, 1);
add_action('sumosubscriptions_subscription_activated', 'sumo_debug_sumo_activated', 10, 2);
add_action('sumosubscriptions_subscription_created', 'sumo_debug_sumo_created', 10, 2);
add_action('sumosubscriptions_order_status_changed', 'sumo_debug_sumo_status_changed', 10, 3);

function sumo_debug_order_status_change($order_id, $old_status, $new_status) {
    error_log("=== DEBUG: WooCommerce Order Status Changed ===");
    error_log("Order ID: $order_id");
    error_log("Old Status: $old_status");
    error_log("New Status: $new_status");
    sumo_debug_order_details($order_id);
    error_log("===============================================");
}

function sumo_debug_order_completed($order_id) {
    error_log("=== DEBUG: WooCommerce Order Completed ===");
    error_log("Order ID: $order_id");
    sumo_debug_order_details($order_id);
    error_log("==========================================");
}

function sumo_debug_payment_complete($order_id) {
    error_log("=== DEBUG: WooCommerce Payment Complete ===");
    error_log("Order ID: $order_id");
    sumo_debug_order_details($order_id);
    error_log("===========================================");
}

function sumo_debug_sumo_active($order_id) {
    error_log("=== DEBUG: SUMO Subscription Active ===");
    error_log("Order ID: $order_id");
    sumo_debug_order_details($order_id);
    error_log("=======================================");
}

function sumo_debug_sumo_activated($subscription_id, $subscription) {
    error_log("=== DEBUG: SUMO Subscription Activated ===");
    error_log("Subscription ID: $subscription_id");
    error_log("Subscription Object Type: " . gettype($subscription));
    
    if (is_object($subscription)) {
        error_log("Subscription Properties: " . print_r(get_object_vars($subscription), true));
    }
    
    sumo_debug_subscription_meta($subscription_id);
    error_log("==========================================");
}

function sumo_debug_sumo_created($subscription_id, $subscription) {
    error_log("=== DEBUG: SUMO Subscription Created ===");
    error_log("Subscription ID: $subscription_id");
    sumo_debug_subscription_meta($subscription_id);
    error_log("========================================");
}

function sumo_debug_sumo_status_changed($order_id, $old_status, $new_status) {
    error_log("=== DEBUG: SUMO Status Changed ===");
    error_log("Order ID: $order_id");
    error_log("Old Status: $old_status");
    error_log("New Status: $new_status");
    sumo_debug_order_details($order_id);
    error_log("=================================");
}

function sumo_debug_order_details($order_id) {
    $order = wc_get_order($order_id);
    
    if (!$order) {
        error_log("ERROR: Order not found!");
        return;
    }
    
    error_log("User ID: " . $order->get_user_id());
    error_log("Billing Email: " . $order->get_billing_email());
    error_log("Order Status: " . $order->get_status());
    
    $items = $order->get_items();
    error_log("Number of Items: " . count($items));
    
    foreach ($items as $item_id => $item) {
        error_log("--- Item $item_id ---");
        error_log("Name: " . $item->get_name());
        error_log("Product ID: " . $item->get_product_id());
        error_log("Variation ID: " . $item->get_variation_id());
        error_log("Product Type: " . $item->get_type());
        
        // Check if it's a subscription product
        $product = wc_get_product($item->get_product_id());
        if ($product) {
            error_log("Is Subscription: " . ($product->is_type('subscription') ? 'Yes' : 'No'));
        }
        
        // Get all item meta
        $meta = $item->get_meta_data();
        error_log("Item Meta: " . print_r($meta, true));
    }
    
    // Check for subscription IDs linked to this order
    $subscription_ids = get_posts(array(
        'post_type' => 'sumomemberships',
        'meta_query' => array(
            array(
                'key' => '_parent_order_id',
                'value' => $order_id,
            ),
        ),
        'fields' => 'ids',
    ));
    
    if (!empty($subscription_ids)) {
        error_log("Linked Subscription IDs: " . implode(', ', $subscription_ids));
        foreach ($subscription_ids as $sub_id) {
            sumo_debug_subscription_meta($sub_id);
        }
    }
}

function sumo_debug_subscription_meta($subscription_id) {
    error_log("--- Subscription Meta for ID: $subscription_id ---");
    
    // Get all meta for this subscription
    $all_meta = get_post_meta($subscription_id);
    error_log("All Meta Keys: " . print_r(array_keys($all_meta), true));
    
    // Check specific keys
    $keys_to_check = array(
        '_product_id',
        '_variation_id',
        'sumo_get_product_id',
        'sumo_get_user_id',
        '_customer_user',
        '_parent_order_id',
        'sumo_get_parent_order_id',
    );
    
    foreach ($keys_to_check as $key) {
        $value = get_post_meta($subscription_id, $key, true);
        if ($value) {
            error_log("$key: $value");
        }
    }
}

// Manual test function - call this via URL: ?test_sumo_role=USER_ID&product_id=8206
add_action('init', 'sumo_manual_role_test');
function sumo_manual_role_test() {
    if (isset($_GET['test_sumo_role']) && current_user_can('manage_options')) {
        $user_id = intval($_GET['test_sumo_role']);
        $product_id = isset($_GET['product_id']) ? intval($_GET['product_id']) : 8206;
        
        $user = get_user_by('id', $user_id);
        if ($user) {
            $user->remove_role('millie_mini_basic');
            $user->remove_role('millie_mini_pro');
            
            if ($product_id == 8206) {
                $user->add_role('millie_mini_basic');
                echo "Manually assigned millie_mini_basic to user $user_id";
            } elseif ($product_id == 8209) {
                $user->add_role('millie_mini_pro');
                echo "Manually assigned millie_mini_pro to user $user_id";
            }
        } else {
            echo "User not found";
        }
        exit;
    }
}

