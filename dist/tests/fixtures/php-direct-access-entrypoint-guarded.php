<?php
/**
 * Test Fixture: Properly guarded entrypoint — must NOT be flagged
 *
 * NEGATIVE fixture: this file must NOT be flagged by php-direct-access-entrypoint.
 * It has a correct ABSPATH guard at the top, preventing direct HTTP access.
 *
 * @package Neochrome\WPPerformanceTests
 */

defined( 'ABSPATH' ) || exit;

global $wpdb;

$results = $wpdb->get_results( "SELECT * FROM {$wpdb->prefix}options LIMIT 10" );

foreach ( $results as $row ) {
	echo esc_html( $row->option_name ) . "\n";
}
