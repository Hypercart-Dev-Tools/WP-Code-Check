<?php
/**
 * Test Fixture: DSM Same-Line Nonce Guard (should not fail)
 */

function hcc_fixture_dsm_same_line_nonce() {
	if ( ! wp_verify_nonce( sanitize_text_field( wp_unslash( $_POST['hcc_dsm_nonce'] ) ), 'hcc_dsm_nonce' ) ) { $_POST['hcc_dsm_same_line'] = sanitize_text_field( wp_unslash( $_POST['hcc_dsm_same_line'] ) ); }
}
