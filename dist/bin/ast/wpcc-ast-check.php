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
require_once __DIR__ . '/HookRegistrationVisitor.php';

use PhpParser\ParserFactory;
use PhpParser\NodeTraverser;
use PhpParser\NodeVisitor\ParentConnectingVisitor;
use WPCC\AST\ReturnArrayShapeVisitor;
use WPCC\AST\HookRegistrationVisitor;

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
              Available rules: return-array-shape, hook-arg-mismatch, hook-inventory
  --config    Path to JSON config file with rule settings (optional)
  --output    Output format: json or text (default: json)
  --help      Show this help message

Examples:
  php wpcc-ast-check.php --paths ./includes --rule return-array-shape
  php wpcc-ast-check.php --paths ./includes --rule hook-arg-mismatch
  php wpcc-ast-check.php --paths ./includes --rule hook-inventory

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
$hook_visitor = new HookRegistrationVisitor();
$traverser->addVisitor( $hook_visitor );

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
        $hook_visitor->setCurrentFile( $file );
        $traverser->traverse( $ast );
    } catch ( \PhpParser\Error $e ) {
        $errors[] = [ 'file' => $file, 'error' => $e->getMessage() ];
    }
}

$all_shapes      = $shape_visitor->getReturnShapes();
$registrations   = $hook_visitor->getRegistrations();
$fire_points     = $hook_visitor->getFirePoints();
$callables       = $hook_visitor->getCallables();

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

if ( $rule === 'hook-arg-mismatch' ) {
    $target_hooks = $config['target_hooks'] ?? [];
    $checks       = $config['checks'] ?? [ 'arg_count', 'priority_conflict', 'fire_arg_count' ];

    // Filter registrations to add_action/add_filter only (not remove_*).
    $add_registrations = array_filter( $registrations, function ( $reg ) {
        return in_array( $reg['type'], [ 'action', 'filter' ], true );
    } );

    // Filter by target hooks if configured.
    if ( ! empty( $target_hooks ) ) {
        $add_registrations = array_filter( $add_registrations, function ( $reg ) use ( $target_hooks ) {
            foreach ( $target_hooks as $pattern ) {
                if ( fnmatch( $pattern, $reg['hook'] ) ) {
                    return true;
                }
            }
            return false;
        } );
    }

    // Check 1: Callback arg count vs. accepted_args.
    if ( in_array( 'arg_count', $checks, true ) ) {
        foreach ( $add_registrations as $reg ) {
            if ( $reg['callback'] === '{dynamic}' ) {
                continue;
            }

            $callable_key = $reg['callback'];
            if ( ! isset( $callables[ $callable_key ] ) ) {
                continue;
            }

            $def           = $callables[ $callable_key ];
            $accepted_args = $reg['accepted_args'];
            $param_count   = $def['params'];
            $required      = $def['required_params'];

            // Skip if accepted_args is unknown (-1 = non-literal).
            if ( $accepted_args < 0 ) {
                continue;
            }

            // Callback has more required params than it will receive.
            if ( $required > $accepted_args ) {
                $findings[] = generate_finding(
                    'ast-010-hook-arg-undercount',
                    'warning',
                    'MEDIUM',
                    $reg['file'],
                    $reg['line'],
                    sprintf(
                        '%s() registers callback %s on hook "%s" with accepted_args=%d, but the callback requires %d parameter%s (%d total). The callback will receive fewer arguments than it requires.',
                        $reg['function'],
                        $reg['callback'],
                        $reg['hook'],
                        $accepted_args,
                        $required,
                        $required === 1 ? '' : 's',
                        $param_count
                    ),
                    [
                        'callback_file'   => $def['file'],
                        'callback_line'   => $def['line'],
                        'accepted_args'   => $accepted_args,
                        'callback_params' => $param_count,
                        'required_params' => $required,
                    ]
                );
            }

            // Callback accepts more params than it will receive (silently dropped).
            if ( $param_count > $accepted_args && $required <= $accepted_args ) {
                $findings[] = generate_finding(
                    'ast-011-hook-arg-unused',
                    'info',
                    'LOW',
                    $reg['file'],
                    $reg['line'],
                    sprintf(
                        '%s() registers callback %s on hook "%s" with accepted_args=%d, but the callback defines %d parameter%s. Extra parameters will always receive their default values.',
                        $reg['function'],
                        $reg['callback'],
                        $reg['hook'],
                        $accepted_args,
                        $param_count,
                        $param_count === 1 ? '' : 's'
                    ),
                    [
                        'callback_file'   => $def['file'],
                        'callback_line'   => $def['line'],
                        'accepted_args'   => $accepted_args,
                        'callback_params' => $param_count,
                    ]
                );
            }
        }
    }

    // Check 2: Priority conflicts (same hook, same priority, within the scanned codebase).
    if ( in_array( 'priority_conflict', $checks, true ) ) {
        $by_hook_priority = [];
        foreach ( $add_registrations as $reg ) {
            if ( $reg['priority'] < 0 ) {
                continue; // Unknown priority.
            }
            $key = $reg['hook'] . '@' . $reg['priority'];
            $by_hook_priority[ $key ][] = $reg;
        }

        foreach ( $by_hook_priority as $key => $regs ) {
            if ( count( $regs ) < 2 ) {
                continue;
            }
            // Only flag if callbacks are different (same callback registered twice is a different issue).
            $unique_callbacks = array_unique( array_column( $regs, 'callback' ) );
            if ( count( $unique_callbacks ) < 2 ) {
                continue;
            }

            $callbacks_list = implode( ', ', $unique_callbacks );
            foreach ( $regs as $reg ) {
                $findings[] = generate_finding(
                    'ast-012-hook-priority-conflict',
                    'info',
                    'LOW',
                    $reg['file'],
                    $reg['line'],
                    sprintf(
                        'Hook "%s" has %d callbacks at priority %d: %s. Execution order among same-priority callbacks is registration order, which may be fragile.',
                        $reg['hook'],
                        count( $regs ),
                        $reg['priority'],
                        $callbacks_list
                    ),
                    [
                        'hook'      => $reg['hook'],
                        'priority'  => $reg['priority'],
                        'callbacks' => $unique_callbacks,
                    ]
                );
            }
        }
    }

    // Check 3: Fire point passes fewer args than callbacks expect.
    if ( in_array( 'fire_arg_count', $checks, true ) ) {
        // Index fire points by hook name.
        $fires_by_hook = [];
        foreach ( $fire_points as $fp ) {
            $fires_by_hook[ $fp['hook'] ][] = $fp;
        }

        foreach ( $add_registrations as $reg ) {
            $accepted_args = $reg['accepted_args'];
            if ( $accepted_args < 0 || ! isset( $fires_by_hook[ $reg['hook'] ] ) ) {
                continue;
            }

            foreach ( $fires_by_hook[ $reg['hook'] ] as $fp ) {
                if ( $fp['args_passed'] < $accepted_args ) {
                    $findings[] = generate_finding(
                        'ast-013-hook-fire-arg-shortage',
                        'warning',
                        'MEDIUM',
                        $reg['file'],
                        $reg['line'],
                        sprintf(
                            'Callback %s on hook "%s" expects %d arg%s (accepted_args=%d), but %s() at %s:%d only passes %d.',
                            $reg['callback'],
                            $reg['hook'],
                            $accepted_args,
                            $accepted_args === 1 ? '' : 's',
                            $accepted_args,
                            $fp['function'],
                            basename( $fp['file'] ),
                            $fp['line'],
                            $fp['args_passed']
                        ),
                        [
                            'fire_file'      => $fp['file'],
                            'fire_line'      => $fp['line'],
                            'fire_function'  => $fp['function'],
                            'args_passed'    => $fp['args_passed'],
                            'accepted_args'  => $accepted_args,
                        ]
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

// hook-inventory rule: no findings, just outputs collected data.
if ( $rule === 'hook-inventory' ) {
    $target_hooks = $config['target_hooks'] ?? [];

    // Filter by target hooks if configured.
    $filtered_registrations = $registrations;
    $filtered_fire_points   = $fire_points;
    if ( ! empty( $target_hooks ) ) {
        $filtered_registrations = array_values( array_filter( $registrations, function ( $reg ) use ( $target_hooks ) {
            foreach ( $target_hooks as $pattern ) {
                if ( fnmatch( $pattern, $reg['hook'] ) ) {
                    return true;
                }
            }
            return false;
        } ) );
        $filtered_fire_points = array_values( array_filter( $fire_points, function ( $fp ) use ( $target_hooks ) {
            foreach ( $target_hooks as $pattern ) {
                if ( fnmatch( $pattern, $fp['hook'] ) ) {
                    return true;
                }
            }
            return false;
        } ) );
    }

    // Sort registrations by hook name then priority.
    usort( $filtered_registrations, function ( $a, $b ) {
        $cmp = strcmp( $a['hook'], $b['hook'] );
        if ( $cmp !== 0 ) {
            return $cmp;
        }
        return $a['priority'] - $b['priority'];
    } );
}

// Output results.
$output = [
    'scan_type'     => 'ast-check',
    'rule'          => $rule,
    'files_scanned' => count( $files_to_scan ),
    'findings'      => $findings,
    'errors'        => $errors,
];

// Include shapes for return-array-shape rule.
if ( $rule === 'return-array-shape' ) {
    $output['shapes'] = $all_shapes;
}

// Include hook data for hook rules.
if ( $rule === 'hook-arg-mismatch' || $rule === 'hook-inventory' ) {
    $output['registrations'] = $rule === 'hook-inventory'
        ? ( $filtered_registrations ?? $registrations )
        : $registrations;
    $output['fire_points'] = $rule === 'hook-inventory'
        ? ( $filtered_fire_points ?? $fire_points )
        : $fire_points;
    $output['callables_count'] = count( $callables );
}

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

    if ( $rule === 'return-array-shape' && ! empty( $all_shapes ) ) {
        echo "\nDetected Return Array Shapes:\n";
        foreach ( $all_shapes as $shape ) {
            $basename = basename( $shape['file'] );
            echo "  {$basename}:{$shape['line']} - {$shape['scope']}\n";
            echo "    Keys: [" . implode( ', ', $shape['keys'] ) . "]\n";
        }
    }

    if ( ( $rule === 'hook-arg-mismatch' || $rule === 'hook-inventory' ) ) {
        $display_regs = $rule === 'hook-inventory'
            ? ( $filtered_registrations ?? $registrations )
            : $registrations;
        $display_fps = $rule === 'hook-inventory'
            ? ( $filtered_fire_points ?? $fire_points )
            : $fire_points;

        if ( ! empty( $display_regs ) ) {
            echo "\nHook Registrations (" . count( $display_regs ) . "):\n";
            foreach ( $display_regs as $reg ) {
                $basename = basename( $reg['file'] );
                $priority_str = $reg['priority'] >= 0 ? (string) $reg['priority'] : '?';
                $args_str     = $reg['accepted_args'] >= 0 ? (string) $reg['accepted_args'] : '?';
                echo sprintf(
                    "  %s  %-40s → %-30s  pri=%-3s args=%s  %s:%d\n",
                    $reg['function'],
                    $reg['hook'],
                    $reg['callback'],
                    $priority_str,
                    $args_str,
                    $basename,
                    $reg['line']
                );
            }
        }

        if ( ! empty( $display_fps ) ) {
            echo "\nHook Fire Points (" . count( $display_fps ) . "):\n";
            foreach ( $display_fps as $fp ) {
                $basename = basename( $fp['file'] );
                echo sprintf(
                    "  %-15s %-40s  args_passed=%d  %s:%d\n",
                    $fp['function'],
                    $fp['hook'],
                    $fp['args_passed'],
                    $basename,
                    $fp['line']
                );
            }
        }

        echo "\nCallable definitions found: " . count( $callables ) . "\n";
    }
}

// Exit code: 0 if no findings, 1 if findings exist.
exit( empty( $findings ) ? 0 : 1 );
