<?php
/**
 * Test Fixture: DSM JS/AJAX-in-PHP Exclusion (should not detect)
 */

function hcc_fixture_dsm_js_ajax_exclusion() {
	?>
	<script>
	// JS AJAX config line should be excluded from DSM
	$.ajax({ type: 'POST', data: {} }); $_POST['hcc_dsm_js'] = '1';
	</script>
	<?php
}
