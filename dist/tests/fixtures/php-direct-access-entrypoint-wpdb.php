<?php
/**
 * Test Fixture: Direct-Access Entrypoint — $wpdb work, no ABSPATH guard
 *
 * POSITIVE fixture: this file must be flagged by php-direct-access-entrypoint.
 * It performs real database work at the top level with NO defined('ABSPATH') guard.
 *
 * @package Neochrome\WPPerformanceTests
 */

// 🚨 NO ABSPATH/WPINC guard here — direct HTTP access is possible

global $wpdb;

$results = $wpdb->get_results( "SELECT * FROM {$wpdb->prefix}users" );

foreach ( $results as $row ) {
	echo esc_html( $row->user_email ) . "\n";
}
