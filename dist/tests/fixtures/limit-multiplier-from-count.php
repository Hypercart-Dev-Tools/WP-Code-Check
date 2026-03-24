<?php

// Fixture: candidate limit multiplier derived from count()

// ============================================================
// TRUE POSITIVE — count() multiplied into a limit value
// ============================================================

function hcc_fixture_limit_multiplier_from_count( array $user_ids ) {
	$candidate_limit = count( $user_ids ) * 10 * 5;
	return $candidate_limit;
}

// ============================================================
// FALSE POSITIVE GUARDS — count() used for display, comparison, or assignment
// These should NOT be flagged by limit-multiplier-from-count
// ============================================================

// FP: count() used in echo/display context
function display_pending_count( $pending ) {
	echo "\nPending submissions: " . count($pending) . "\n";
}

// FP: count() used as array value for logging/display
function build_summary_array( $person ) {
	return [
		'Phone_Count' => isset($person['ContactPhoneNumbers']) ? count($person['ContactPhoneNumbers']) : 0,
		'Email_Count' => isset($person['ContactEmailAddresses']) ? count($person['ContactEmailAddresses']) : 0,
	];
}

// FP: count() used in while-loop comparison (not a LIMIT multiplier)
function normalize_array( $normalized, $length ) {
	while (count($normalized) < $length) {
		$normalized[] = '';
	}
	return $normalized;
}

// FP: count() used in HTML output
function render_log_summary( $request_files, $response_files ) {
	echo '<p><strong>Request Logs:</strong> ' . count($request_files) . ' file(s)</p>';
	echo '<p><strong>Response Logs:</strong> ' . count($response_files) . ' file(s)</p>';
}

// FP: count() used in if-condition (not multiplied)
function trim_submissions( $pending_submissions ) {
	if (count($pending_submissions) > 10) {
		$pending_submissions = array_slice($pending_submissions, 0, 10);
	}
	return $pending_submissions;
}
