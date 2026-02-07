<?php
/**
 * Test Fixture: False Positive - Commented Out Hook
 * 
 * Expected: PASS (validator should return exit code 1)
 * Reason: Hook registration is commented out - this is dead code
 */

// This hook is COMMENTED OUT - dead code
// add_action('woocommerce_thankyou', 'dead_code_handler');

function dead_code_handler($order_id) {
    $order = wc_get_order($order_id);
    
    // Line 15: This should NOT be flagged - function is never called
    $coupons = $order->get_coupon_codes();
    
    if (!empty($coupons)) {
        foreach ($coupons as $coupon_code) {
            // Line 20: This should NOT be flagged - function is never called
            $coupon = new WC_Coupon($coupon_code);
            error_log('Coupon: ' . $coupon->get_code());
        }
    }
}

