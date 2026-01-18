<?php
/**
 * Test Fixture: DSM Unguarded Write (must fail)
 *
 * Direct superglobal write with sanitization but no guards.
 */

function hcc_fixture_dsm_unguarded_write() {
	$_POST['hcc_dsm_unguarded'] = sanitize_text_field( wp_unslash( $_POST['hcc_dsm_unguarded'] ) );
}
