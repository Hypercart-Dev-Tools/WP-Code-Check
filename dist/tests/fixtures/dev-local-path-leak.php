<?php
// Fixture: dev-local-path-leak (PHP) — hardcoded developer filesystem paths.
defined( 'ABSPATH' ) || exit;

// (+) absolute macOS dev path containing "Local Sites"
$log_dir = '/Users/dev/Local Sites/myshop/logs';

// (-) portable path — no developer-absolute path
$rel_dir = __DIR__ . '/logs';