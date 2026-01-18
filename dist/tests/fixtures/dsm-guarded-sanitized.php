<?php
/**
 * Test Fixture: DSM Guarded + Sanitized (should not fail)
 */

function hcc_fixture_dsm_guarded_sanitized() {
	check_admin_referer( 'hcc_dsm_guarded' );
	if ( ! current_user_can( 'manage_options' ) ) {
		return;
	}

	$_POST['hcc_dsm_guarded'] = sanitize_text_field( wp_unslash( $_POST['hcc_dsm_guarded'] ) );
}
