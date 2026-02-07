<?php
/**
 * Test Fixture: False Positive - Coupon in Checkout Hook
 * 
 * Expected: PASS (validator should return exit code 1)
 * Reason: Coupon operations in woocommerce_checkout_order_processed are valid
 */

// This is a SAFE hook - checkout context, not thank-you page
add_action('woocommerce_checkout_order_processed', 'safe_coupon_handler', 10, 3);

function safe_coupon_handler($order_id, $posted_data, $order) {
    // Line 13: This should NOT be flagged - it's in checkout context
    $coupons = $order->get_coupon_codes();
    
    if (!empty($coupons)) {
        foreach ($coupons as $coupon_code) {
            // Line 18: This should NOT be flagged - it's in checkout context
            $coupon = new WC_Coupon($coupon_code);
            $coupon_amount = $coupon->get_amount();
            
            if ($coupon_amount == 0) {
                error_log('Zero-value coupon used: ' . $coupon_code);
            }
        }
    }
}

