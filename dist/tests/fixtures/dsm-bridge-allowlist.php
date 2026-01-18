<?php
/**
 * Test Fixture: DSM Bridge Allowlist (should suppress)
 */

function hcc_fixture_dsm_bridge_allowlist() {
	$_REQUEST['hcc_dsm_bridge'] = sanitize_text_field( wp_unslash( $_REQUEST['hcc_dsm_bridge'] ) );
}
