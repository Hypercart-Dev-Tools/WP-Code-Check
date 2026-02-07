<?php
/**
 * Test Fixture: True Positive - Coupon in Thank-You Hook
 * 
 * Expected: FAIL (validator should return exit code 0)
 * Reason: Coupon operations in woocommerce_thankyou are problematic
 */

// This is a PROBLEMATIC hook - thank-you page context
add_action('woocommerce_thankyou', 'bad_coupon_handler');

function bad_coupon_handler($order_id) {
    $order = wc_get_order($order_id);
    
    // Line 14: This SHOULD be flagged - it's in thank-you context
    $coupons = $order->get_coupon_codes();
    
    if (!empty($coupons)) {
        foreach ($coupons as $coupon_code) {
            // Line 19: This SHOULD be flagged - it's in thank-you context
            $coupon = new WC_Coupon($coupon_code);
            
            // This is problematic - modifying coupon state on thank-you page
            if ($coupon->get_amount() > 100) {
                WC()->cart->apply_coupon('BONUS10');
            }
        }
    }
}

