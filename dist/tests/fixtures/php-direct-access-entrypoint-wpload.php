<?php
/**
 * Test Fixture: Direct-Access Entrypoint — portable wp-load bootstrap, no guard
 *
 * POSITIVE fixture: this file must be flagged by php-direct-access-entrypoint
 * with escalated impact (live-entrypoint) because it bootstraps WordPress via a
 * portable require of wp-load.php and performs output — no ABSPATH guard present.
 *
 * @package Neochrome\WPPerformanceTests
 */

// 🚨 NO ABSPATH guard — bootstraps WP itself, so guard is responsibility of this file

require dirname( __FILE__ ) . '/../../../../wp-load.php';

echo '<pre>';
print_r( get_users( array( 'number' => 50 ) ) );
echo '</pre>';
