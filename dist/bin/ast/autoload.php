<?php
/**
 * PHP-Parser autoloader for WPCC AST checks.
 *
 * This file loads the PHP-Parser library bundled in the WP-PHP-Parser-loader plugin.
 * It can be used standalone (CLI context) without requiring WordPress.
 *
 * @package WPCC
 * @since 1.0.0
 */

// Prevent double loading.
if ( defined( 'WPCC_PHP_PARSER_LOADED' ) ) {
    return;
}
define( 'WPCC_PHP_PARSER_LOADED', true );

/**
 * Resolve the PHP-Parser library path.
 *
 * Priority:
 * 1. WPCC_PHP_PARSER_PATH environment variable
 * 2. Bundled in temp/WP-PHP-Parser-loader (development)
 * 3. Bundled in dist/lib/PhpParser (production - future)
 */
function wpcc_resolve_php_parser_path(): ?string {
    // Check environment variable first.
    $env_path = getenv( 'WPCC_PHP_PARSER_PATH' );
    if ( $env_path && is_dir( $env_path ) ) {
        return rtrim( $env_path, '/' );
    }

    // Development: look for WP-PHP-Parser-loader in temp/.
    $script_dir = dirname( __FILE__ );
    $workspace_root = dirname( dirname( dirname( $script_dir ) ) );

    $dev_path = $workspace_root . '/temp/WP-PHP-Parser-loader/lib/PhpParser';
    if ( is_dir( $dev_path ) ) {
        return $dev_path;
    }

    // Future: bundled in dist/lib/PhpParser.
    $dist_path = dirname( $script_dir ) . '/lib/PhpParser';
    if ( is_dir( $dist_path ) ) {
        return $dist_path;
    }

    return null;
}

/**
 * Autoloader for the PHP-Parser library classes.
 *
 * @param string $class The fully qualified class name.
 */
function wpcc_php_parser_autoloader( string $class ): void {
    static $base_dir = null;

    if ( $base_dir === null ) {
        $base_dir = wpcc_resolve_php_parser_path();
        if ( $base_dir === null ) {
            // Can't autoload - library not found.
            return;
        }
    }

    $prefix = 'PhpParser\\';
    $len = strlen( $prefix );

    if ( strncmp( $prefix, $class, $len ) !== 0 ) {
        return;
    }

    $relative_class = substr( $class, $len );
    $file = $base_dir . '/' . str_replace( '\\', '/', $relative_class ) . '.php';

    if ( file_exists( $file ) ) {
        require $file;
    }
}

// Register the autoloader.
spl_autoload_register( 'wpcc_php_parser_autoloader' );

// Verify library is available.
$parser_path = wpcc_resolve_php_parser_path();
if ( $parser_path === null ) {
    fwrite( STDERR, "Error: PHP-Parser library not found.\n" );
    fwrite( STDERR, "Set WPCC_PHP_PARSER_PATH environment variable or ensure library is bundled.\n" );
    exit( 1 );
}

