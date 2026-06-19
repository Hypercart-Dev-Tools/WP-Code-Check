<?php
// Fixture: php-privilege-simulation (unguarded) — web-reachable privilege escalation.
// No ABSPATH/WPINC guard: an unauthenticated direct request can reach this file.

// (+) privilege simulation with no guard -> HIGH, unauthenticated-privilege-escalation
wp_set_current_user( 1 );
echo 'now acting as administrator';
