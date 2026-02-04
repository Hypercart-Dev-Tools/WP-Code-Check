#!/usr/bin/env php
<?php
/**
 * WPCC AST Check - CLI entry point for AST-based code analysis.
 *
 * Usage:
 *   php wpcc-ast-check.php --paths <path1,path2,...> [--rule <rule-name>] [--config <config.json>]
 *
 * Options:
 *   --paths     Comma-separated list of files or directories to scan (required)
 *   --rule      Rule to apply (default: return-array-shape)
 *   --config    Path to JSON config file for the rule (optional)
 *   --output    Output format: json or text (default: json)
 *   --help      Show this help message
 *
 * @package WPCC
 * @since 1.0.0
 */

// Suppress deprecation warnings from bundled PHP-Parser (PHP 8.5 compatibility).
error_reporting( E_ALL & ~E_DEPRECATED );

// Load the autoloader.
require_once __DIR__ . '/autoload.php';
require_once __DIR__ . '/ReturnArrayShapeVisitor.php';

use PhpParser\ParserFactory;
use PhpParser\NodeTraverser;
use PhpParser\NodeVisitor\ParentConnectingVisitor;
use WPCC\AST\ReturnArrayShapeVisitor;

// Parse command line arguments.
$options = getopt( '', [ 'paths:', 'rule:', 'config:', 'output:', 'help' ] );

if ( isset( $options['help'] ) || ! isset( $options['paths'] ) ) {
    echo <<<HELP
WPCC AST Check - Static analysis for PHP code using AST inspection

Usage:
  php wpcc-ast-check.php --paths <path1,path2,...> [options]

Options:
  --paths     Comma-separated list of files or directories to scan (required)
  --rule      Rule to apply (default: return-array-shape)
  --config    Path to JSON config file with rule settings (optional)
  --output    Output format: json or text (default: json)
  --help      Show this help message

Example:
  php wpcc-ast-check.php --paths ./includes --rule return-array-shape

HELP;
    exit( isset( $options['help'] ) ? 0 : 1 );
}

// Configuration.
$paths = explode( ',', $options['paths'] );
$rule = $options['rule'] ?? 'return-array-shape';
$config_file = $options['config'] ?? null;
$output_format = $options['output'] ?? 'json';

// Load config if provided.
$config = [];
if ( $config_file && file_exists( $config_file ) ) {
    $config = json_decode( file_get_contents( $config_file ), true ) ?? [];
}

// Collect files to scan.
$files_to_scan = [];
foreach ( $paths as $path ) {
    $path = trim( $path );
    if ( ! file_exists( $path ) ) {
        fwrite( STDERR, "Warning: Path not found: {$path}\n" );
        continue;
    }

    if ( is_file( $path ) && pathinfo( $path, PATHINFO_EXTENSION ) === 'php' ) {
        $files_to_scan[] = realpath( $path );
    } elseif ( is_dir( $path ) ) {
        $iterator = new RecursiveIteratorIterator(
            new RecursiveDirectoryIterator( $path, RecursiveDirectoryIterator::SKIP_DOTS )
        );
        foreach ( $iterator as $file ) {
            if ( $file->isFile() && $file->getExtension() === 'php' ) {
                $files_to_scan[] = $file->getRealPath();
            }
        }
    }
}

if ( empty( $files_to_scan ) ) {
    fwrite( STDERR, "Error: No PHP files found to scan.\n" );
    exit( 1 );
}

// Create parser.
$parser_factory = new ParserFactory();
$parser = $parser_factory->createForNewestSupportedVersion();

// Create traverser and visitors.
$traverser = new NodeTraverser();
$traverser->addVisitor( new ParentConnectingVisitor() );
$shape_visitor = new ReturnArrayShapeVisitor();
$traverser->addVisitor( $shape_visitor );

// Scan files.
$all_shapes = [];
$errors = [];

foreach ( $files_to_scan as $file ) {
    try {
        $code = file_get_contents( $file );
        $ast = $parser->parse( $code );

        if ( $ast === null ) {
            $errors[] = [ 'file' => $file, 'error' => 'Failed to parse file' ];
            continue;
        }

        $shape_visitor->setCurrentFile( $file );
        $traverser->traverse( $ast );
    } catch ( \PhpParser\Error $e ) {
        $errors[] = [ 'file' => $file, 'error' => $e->getMessage() ];
    }
}

$all_shapes = $shape_visitor->getReturnShapes();

// Generate findings based on rule.
$findings = [];

if ( $rule === 'return-array-shape' ) {
    // Group shapes by scope to detect inconsistencies.
    $by_scope = [];
    foreach ( $all_shapes as $shape ) {
        $scope_key = $shape['file'] . '::' . $shape['scope'];
        $by_scope[ $scope_key ][] = $shape;
    }

    // Check for scope consistency and required keys.
    $expected_keys = $config['expected_keys'] ?? [];
    $target_scopes = $config['target_scopes'] ?? [];

    foreach ( $by_scope as $scope_key => $shapes ) {
        // Check if this scope matches any target pattern.
        $matches_target = empty( $target_scopes );
        foreach ( $target_scopes as $pattern ) {
            if ( fnmatch( $pattern, $scope_key ) || strpos( $scope_key, $pattern ) !== false ) {
                $matches_target = true;
                break;
            }
        }

        if ( ! $matches_target ) {
            continue;
        }

        // For each return in scope, check for expected keys.
        foreach ( $shapes as $shape ) {
            if ( ! empty( $expected_keys ) ) {
                $missing = array_diff( $expected_keys, $shape['keys'] );
                if ( ! empty( $missing ) ) {
                    $findings[] = generate_finding(
                        'ast-001-missing-keys',
                        'warning',
                        'MEDIUM',
                        $shape['file'],
                        $shape['line'],
                        sprintf(
                            'Return array in %s is missing expected keys: %s',
                            $shape['scope'],
                            implode( ', ', $missing )
                        ),
                        $shape['keys']
                    );
                }
            }
        }
    }
}

/**
 * Generate a finding in WPCC-compatible format.
 *
 * @param string $id       Finding ID.
 * @param string $severity Severity level (error, warning, info).
 * @param string $impact   Impact level (HIGH, MEDIUM, LOW).
 * @param string $file     File path.
 * @param int    $line     Line number.
 * @param string $message  Finding message.
 * @param array  $context  Additional context data.
 * @return array Finding object.
 */
function generate_finding(
    string $id,
    string $severity,
    string $impact,
    string $file,
    int $line,
    string $message,
    array $context = []
): array {
    return [
        'id'         => $id,
        'severity'   => $severity,
        'impact'     => $impact,
        'file'       => $file,
        'line'       => $line,
        'message'    => $message,
        'code'       => '',
        'context'    => $context,
        'guards'     => [],
        'sanitizers' => [],
    ];
}

// Output results.
$output = [
    'scan_type'    => 'ast-check',
    'rule'         => $rule,
    'files_scanned' => count( $files_to_scan ),
    'findings'     => $findings,
    'shapes'       => $all_shapes,
    'errors'       => $errors,
];

if ( $output_format === 'json' ) {
    echo json_encode( $output, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES ) . "\n";
} else {
    // Text output.
    echo "WPCC AST Check Results\n";
    echo "======================\n\n";
    echo "Rule: {$rule}\n";
    echo "Files scanned: " . count( $files_to_scan ) . "\n";
    echo "Findings: " . count( $findings ) . "\n";
    echo "Parse errors: " . count( $errors ) . "\n\n";

    if ( ! empty( $findings ) ) {
        echo "Findings:\n";
        foreach ( $findings as $finding ) {
            echo "  [{$finding['severity']}] {$finding['file']}:{$finding['line']}\n";
            echo "    {$finding['message']}\n\n";
        }
    }

    if ( ! empty( $errors ) ) {
        echo "Parse Errors:\n";
        foreach ( $errors as $error ) {
            echo "  {$error['file']}: {$error['error']}\n";
        }
    }

    if ( ! empty( $all_shapes ) ) {
        echo "\nDetected Return Array Shapes:\n";
        foreach ( $all_shapes as $shape ) {
            $basename = basename( $shape['file'] );
            echo "  {$basename}:{$shape['line']} - {$shape['scope']}\n";
            echo "    Keys: [" . implode( ', ', $shape['keys'] ) . "]\n";
        }
    }
}

// Exit code: 0 if no findings, 1 if findings exist.
exit( empty( $findings ) ? 0 : 1 );
