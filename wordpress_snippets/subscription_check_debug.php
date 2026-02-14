<?php
/**
 * Debug helper for subscription checking
 * Add this temporarily to see what subscriptions are found
 * 
 * Test URL: https://your-site.com/?debug_subscription=USER_EMAIL
 */

add_action('init', 'debug_subscription_check');
function debug_subscription_check() {
    if (!isset($_GET['debug_subscription']) || !current_user_can('manage_options')) {
        return;
    }
    
    $email = sanitize_email($_GET['debug_subscription']);
    $user = get_user_by('email', $email);
    
    if (!$user) {
        echo "User not found for email: $email";
        exit;
    }
    
    echo "<h2>Debug Subscription Check for: $email (User ID: {$user->ID})</h2>";
    echo "<pre>";
    
    // Check user roles
    echo "User Roles: " . implode(', ', $user->roles) . "\n\n";
    
    // Check for SUMO subscriptions
    $subscription_post_types = array('sumomemberships', 'sumosubscriptions', 'sumosubscription');
    
    foreach ($subscription_post_types as $post_type) {
        echo "=== Checking post type: $post_type ===\n";
        
        // Try by user ID
        $subscriptions = get_posts(array(
            'post_type' => $post_type,
            'posts_per_page' => -1,
            'post_status' => 'any',
            'meta_query' => array(
                array(
                    'key' => '_customer_user',
                    'value' => $user->ID,
                    'compare' => '='
                )
            )
        ));
        
        echo "Found " . count($subscriptions) . " subscriptions by user ID\n";
        
        foreach ($subscriptions as $sub) {
            echo "  Subscription ID: {$sub->ID}\n";
            echo "  Post Status: {$sub->post_status}\n";
            
            // Get all meta
            $all_meta = get_post_meta($sub->ID);
            echo "  Meta Keys:\n";
            foreach (array_keys($all_meta) as $key) {
                $value = get_post_meta($sub->ID, $key, true);
                echo "    $key: $value\n";
            }
            echo "\n";
        }
        
        // Try by email
        $subscriptions_email = get_posts(array(
            'post_type' => $post_type,
            'posts_per_page' => -1,
            'post_status' => 'any',
            'meta_query' => array(
                array(
                    'key' => '_billing_email',
                    'value' => $email,
                    'compare' => '='
                )
            )
        ));
        
        echo "Found " . count($subscriptions_email) . " subscriptions by email\n";
    }
    
    // Check WooCommerce orders
    if (function_exists('wc_get_orders')) {
        echo "\n=== Checking WooCommerce Orders ===\n";
        $orders = wc_get_orders(array(
            'customer' => $email,
            'limit' => 10,
        ));
        
        echo "Found " . count($orders) . " orders\n";
        foreach ($orders as $order) {
            echo "Order ID: {$order->get_id()}\n";
            echo "Status: {$order->get_status()}\n";
            echo "Items:\n";
            foreach ($order->get_items() as $item) {
                echo "  - Product ID: {$item->get_product_id()}, Variation: {$item->get_variation_id()}\n";
            }
            echo "Subscription Status: " . $order->get_meta('_subscription_status') . "\n";
            echo "\n";
        }
    }
    
    echo "</pre>";
    exit;
}

