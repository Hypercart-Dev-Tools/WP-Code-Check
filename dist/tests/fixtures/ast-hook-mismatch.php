<?php
/**
 * Test fixture for hook-arg-mismatch AST rule.
 *
 * Contains intentional hook registration issues for testing.
 *
 * @package WPCC
 */

// --- CHECK 1: Arg count mismatches ---

// GOOD: callback accepts 3 params, registered with accepted_args=3.
add_filter( 'woocommerce_cart_item_price', 'my_custom_price', 10, 3 );
function my_custom_price( $price, $cart_item, $cart_item_key ) {
    return '$' . number_format( (float) $price, 2 );
}

// BAD: callback requires 3 params but only receives 1 (default accepted_args).
add_filter( 'woocommerce_cart_item_name', 'my_custom_name' );
function my_custom_name( $name, $cart_item, $cart_item_key ) {
    return '<strong>' . $name . '</strong>';
}

// INFO: callback defines 3 params but only 1 is required, registered with accepted_args=1.
add_filter( 'woocommerce_cart_item_class', 'my_item_class', 10, 1 );
function my_item_class( $class, $cart_item = null, $cart_item_key = '' ) {
    return $class . ' custom-item';
}

// --- CHECK 2: Priority conflicts ---

// Two different callbacks on the same hook at the same priority.
add_action( 'woocommerce_checkout_process', 'validate_custom_field', 10 );
function validate_custom_field() {
    // Validate a custom checkout field.
}

add_action( 'woocommerce_checkout_process', 'validate_shipping_method', 10 );
function validate_shipping_method() {
    // Validate shipping method selection.
}

// --- CHECK 3: Fire point arg shortage ---

// This do_action only passes 1 arg, but the registered callback expects 2.
add_action( 'my_custom_action', 'handle_custom_action', 10, 2 );
function handle_custom_action( $order_id, $order_data ) {
    // Process the order.
}

do_action( 'my_custom_action', 42 );

// --- Class-based hooks ---

class My_Checkout_Handler {
    public function __construct() {
        add_filter( 'woocommerce_package_rates', [ $this, 'filter_shipping_rates' ], 10, 2 );
        add_action( 'woocommerce_after_checkout_form', [ $this, 'add_custom_script' ] );
    }

    /**
     * Filter shipping rates — requires both $rates and $package.
     */
    public function filter_shipping_rates( $rates, $package ) {
        foreach ( $rates as $rate_id => $rate ) {
            if ( 'free_shipping' === $rate->method_id ) {
                unset( $rates[ $rate_id ] );
            }
        }
        return $rates;
    }

    public function add_custom_script() {
        echo '<script>console.log("checkout loaded");</script>';
    }
}

// --- apply_filters usage ---

// Fire point: passes 2 args to callbacks.
$shipping_label = apply_filters( 'woocommerce_cart_shipping_method_label', $label, $method );

// But this callback only accepts 1 (default) — won't cause an error but drops $method.
add_filter( 'woocommerce_cart_shipping_method_label', 'my_shipping_label' );
function my_shipping_label( $label ) {
    return 'Shipping: ' . $label;
}
