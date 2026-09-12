<?php
/**
 * Dream Cloud Subscription API Endpoint
 * Simple endpoint: email → subscription status
 * 
 * Priority order:
 * 1. Checks for "holder" role (crypto holder access)
 * 2. Checks for active SUMO subscriptions by product ID (9243 = lite, 8206 = basic, 8209 = pro)
 * 3. Falls back to inactive if no active subscription found
 * 
 * Install via Code Snippets plugin or functions.php
 * 
 * Endpoint: POST /wp-json/dreamcloud/v1/check-subscription
 * Body: { "email": "user@example.com" }
 * Response: { "active": true/false, "status": "holder|lite|basic|pro|inactive|notFound", "message": "..." }
 */

add_action('rest_api_init', function() {
    register_rest_route('dreamcloud/v1', '/check-subscription', array(
        'methods'  => 'POST',
        'callback' => 'dreamcloud_check_subscription',
        'permission_callback' => '__return_true',
        'args' => array(
            'email' => array(
                'required' => true,
                'type' => 'string',
                'sanitize_callback' => 'sanitize_email',
            ),
        ),
    ));
});

function dreamcloud_check_subscription($request) {
    $email = sanitize_email($request->get_param('email'));
    
    if (!is_email($email)) {
        return new WP_REST_Response(array(
            'active' => false,
            'status' => 'unknown',
            'message' => 'Invalid email address',
        ), 400);
    }
    
    $user = get_user_by('email', $email);
    
    if (!$user) {
        return new WP_REST_Response(array(
            'active' => false,
            'status' => 'notFound',
            'message' => 'Email not found. Please sign up at dreamcloudclub.org',
        ), 404);
    }
    
    $user_roles = $user->roles;
    
    // Priority 1: Check Holder role (crypto holder access - highest priority)
    if (in_array('holder', $user_roles, true)) {
        return new WP_REST_Response(array(
            'active' => true,
            'status' => 'holder',
            'message' => 'Crypto Holder access active. Thank you for holding!',
            'role' => 'holder',
            'user_id' => $user->ID,
        ), 200);
    }
    
    // Priority 2: Check for active SUMO subscriptions by product ID
    $subscription_status = check_sumo_subscription_by_user($user->ID);
    
    if ($subscription_status) {
        return $subscription_status;
    }
    
    // No active subscription found
    return new WP_REST_Response(array(
        'active' => false,
        'status' => 'inactive',
        'message' => 'No active subscription. Subscribe at dreamcloudclub.org',
        'role' => implode(', ', $user_roles),
        'user_id' => $user->ID,
    ), 200);
}

/**
 * Check for active SUMO subscription by user ID
 * Returns subscription status based on product ID (9243 = lite, 8206 = basic, 8209 = pro)
 *
 * This function queries the SUMO subscriptions database table directly,
 * which is more reliable than querying WordPress posts/meta.
 */
function check_sumo_subscription_by_user($user_id) {
    global $wpdb;
    
    if (!$user_id) {
        error_log("SUMO CHECK: No user ID provided");
        return null;
    }
    
    // Get user's billing email to find orders
    $user = get_user_by('id', $user_id);
    if (!$user) {
        error_log("SUMO CHECK: User not found for ID: $user_id");
        return null;
    }
    
    error_log("SUMO CHECK: Checking subscriptions for user ID: $user_id, email: {$user->user_email}");
    
    /**
     * METHOD 1: Query SUMO subscriptions table directly
     * SUMO stores subscriptions in a dedicated database table
     * Common table names: wp_sumo_subscriptions or wp_sumosubscriptions
     */
    $table_candidates = array(
        $wpdb->prefix . 'sumo_subscriptions',
        $wpdb->prefix . 'sumosubscriptions',
        $wpdb->prefix . 'sumosubscription', // Singular variant
    );
    
    $sumo_table = null;
    foreach ($table_candidates as $candidate) {
        // Check if table exists
        $exists = $wpdb->get_var($wpdb->prepare(
            "SELECT COUNT(*) FROM information_schema.tables 
             WHERE table_schema = %s AND table_name = %s",
            DB_NAME,
            $candidate
        ));
        
        if ($exists > 0) {
            $sumo_table = $candidate;
            error_log("SUMO CHECK: Found SUMO table: $sumo_table");
            break;
        }
    }
    
    if ($sumo_table) {
        // Get all active subscriptions for this user
        // Try different column name variations
        $column_variants = array(
            array('user_id', 'product_id', 'status'),
            array('customer_id', 'product_id', 'subscription_status'),
            array('user', 'product', 'status'),
        );
        
        foreach ($column_variants as $columns) {
            list($user_col, $product_col, $status_col) = $columns;
            
            // First check if these columns exist in the table
            $columns_exist = $wpdb->get_results($wpdb->prepare(
                "SELECT COLUMN_NAME 
                 FROM information_schema.COLUMNS 
                 WHERE TABLE_SCHEMA = %s 
                   AND TABLE_NAME = %s 
                   AND COLUMN_NAME IN (%s, %s, %s)",
                DB_NAME,
                $sumo_table,
                $user_col,
                $product_col,
                $status_col
            ));
            
            if (count($columns_exist) >= 2) {
                // Build query - be flexible with status values
                $product_ids = $wpdb->get_col($wpdb->prepare(
                    "SELECT DISTINCT `$product_col` 
                     FROM `$sumo_table` 
                     WHERE `$user_col` = %d
                       AND (`$status_col` = 'active' OR `$status_col` = 'Active' OR `$status_col` = 'ACTIVE' OR `$status_col` = '1')",
                    $user_id
                ));
                
                error_log("SUMO CHECK: Found product IDs: " . implode(', ', $product_ids) . " using columns: $user_col, $product_col, $status_col");
                
                if (!empty($product_ids)) {
                    $product_ids = array_map('intval', $product_ids);

                    // Pro – product ID 8209 (check first - highest tier)
                    if (in_array(8209, $product_ids, true)) {
                        error_log("SUMO CHECK: ✓ Returning PRO status for user $user_id");
                        return new WP_REST_Response(array(
                            'active' => true,
                            'status' => 'pro',
                            'message' => 'Pro subscription active',
                            'product_id' => 8209,
                            'user_id' => $user_id,
                        ), 200);
                    }

                    // Basic – product ID 8206
                    if (in_array(8206, $product_ids, true)) {
                        error_log("SUMO CHECK: ✓ Returning BASIC status for user $user_id");
                        return new WP_REST_Response(array(
                            'active' => true,
                            'status' => 'basic',
                            'message' => 'Basic subscription active',
                            'product_id' => 8206,
                            'user_id' => $user_id,
                        ), 200);
                    }

                    // Lite – product ID 9243
                    if (in_array(9243, $product_ids, true)) {
                        error_log("SUMO CHECK: ✓ Returning LITE status for user $user_id");
                        return new WP_REST_Response(array(
                            'active' => true,
                            'status' => 'lite',
                            'message' => 'Lite subscription active',
                            'product_id' => 9243,
                            'user_id' => $user_id,
                        ), 200);
                    }

                    // Some other active SUMO subscription that isn't mapped
                    error_log("SUMO CHECK: Found active subscription with product IDs: " . implode(', ', $product_ids) . " but none match 9243, 8206 or 8209");
                    return new WP_REST_Response(array(
                        'active' => true,
                        'status' => 'active_other',
                        'message' => 'Active subscription found, but not Basic or Pro (different product ID)',
                        'product_ids' => $product_ids,
                        'user_id' => $user_id,
                    ), 200);
                }
            }
        }
        
        // If we found the table but got no results, log table structure for debugging
        error_log("SUMO CHECK: Table $sumo_table exists but no matching subscriptions found");
        $table_structure = $wpdb->get_results("DESCRIBE `$sumo_table`");
        error_log("SUMO CHECK: Table structure: " . print_r($table_structure, true));
    } else {
        error_log("SUMO CHECK: No SUMO subscriptions table found. Tried: " . implode(', ', $table_candidates));
    }
    
    /**
     * METHOD 2: Fallback - Query through WooCommerce orders
     * This is a backup method if SUMO table approach doesn't work
     */
    if (function_exists('wc_get_orders')) {
        error_log("SUMO CHECK: Trying fallback Method 2 - WooCommerce orders");
        
        $user_email = $user->user_email;
        
        // Get all orders for this customer
        $orders = wc_get_orders(array(
            'customer' => $user_email,
            'limit' => 50, // Limit to recent orders
            'status' => 'any',
        ));
        
        error_log("SUMO CHECK: Found " . count($orders) . " orders for customer");
        
        foreach ($orders as $order) {
            $order_id = $order->get_id();
            $items = $order->get_items();
            
            foreach ($items as $item) {
                $product_id = $item->get_variation_id() ? $item->get_variation_id() : $item->get_product_id();

                // Check if this is product 9243, 8206 or 8209
                if ($product_id == 9243 || $product_id == 8206 || $product_id == 8209) {
                    // Check if order/subscription is active
                    $subscription_status = $order->get_meta('_subscription_status');
                    $order_status = $order->get_status();

                    error_log("SUMO CHECK: Found product $product_id in order $order_id, subscription status: $subscription_status, order status: $order_status");

                    // If subscription status is active, or order is completed/processing
                    if ($subscription_status === 'active' ||
                        in_array($order_status, array('completed', 'processing', 'wc-completed', 'wc-processing'))) {

                        if ($product_id == 8209) {
                            error_log("SUMO CHECK: ✓ Returning PRO status from order $order_id");
                            return new WP_REST_Response(array(
                                'active' => true,
                                'status' => 'pro',
                                'message' => 'Pro subscription active',
                                'product_id' => $product_id,
                                'order_id' => $order_id,
                                'user_id' => $user_id,
                            ), 200);
                        } elseif ($product_id == 8206) {
                            error_log("SUMO CHECK: ✓ Returning BASIC status from order $order_id");
                            return new WP_REST_Response(array(
                                'active' => true,
                                'status' => 'basic',
                                'message' => 'Basic subscription active',
                                'product_id' => $product_id,
                                'order_id' => $order_id,
                                'user_id' => $user_id,
                            ), 200);
                        } elseif ($product_id == 9243) {
                            error_log("SUMO CHECK: ✓ Returning LITE status from order $order_id");
                            return new WP_REST_Response(array(
                                'active' => true,
                                'status' => 'lite',
                                'message' => 'Lite subscription active',
                                'product_id' => $product_id,
                                'order_id' => $order_id,
                                'user_id' => $user_id,
                            ), 200);
                        }
                    }
                }
            }
        }
    }
    
    error_log("SUMO CHECK: ✗ No active subscription found for user $user_id");
    return null; // No active subscription found
}

// CORS headers for mobile app
add_action('rest_api_init', function() {
    remove_filter('rest_pre_serve_request', 'rest_send_cors_headers');
    add_filter('rest_pre_serve_request', function($value) {
        header('Access-Control-Allow-Origin: *');
        header('Access-Control-Allow-Methods: POST, GET, OPTIONS');
        header('Access-Control-Allow-Headers: Content-Type');
        return $value;
    });
}, 15);
