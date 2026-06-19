<?php
/**
 * Test Fixture: Class-only include — must NOT be flagged
 *
 * NEGATIVE fixture: this file must NOT be flagged by php-direct-access-entrypoint.
 * It is a pure class definition (autoloaded include) with no top-level executable
 * statements — no ABSPATH guard is required for files like this.
 *
 * @package Neochrome\WPPerformanceTests
 */

namespace MyPlugin\Includes;

use WP_Post;

/**
 * A plain class definition file. No side effects at the top level.
 */
class My_Class_Only {

	/** @var int */
	private $id;

	public function __construct( int $id ) {
		$this->id = $id;
	}

	public function get_id(): int {
		return $this->id;
	}

	public static function from_post( WP_Post $post ): self {
		return new self( (int) $post->ID );
	}
}
