<?php
// Fixture: php-privilege-simulation (guarded) — not web-reachable.
defined( 'ABSPATH' ) || exit;

// (+) privilege simulation in guarded runtime code -> MEDIUM, runtime-privilege-simulation
wp_set_current_user( 1 );

// (-) read-only capability check must NOT be flagged (no privilege change)
if ( current_user_can( 'manage_options' ) ) {
	return true;
}
