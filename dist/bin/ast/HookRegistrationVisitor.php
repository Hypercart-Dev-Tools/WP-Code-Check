<?php
/**
 * NodeVisitor to collect WordPress hook registrations and function/method definitions.
 *
 * Extracts add_action, add_filter, do_action, apply_filters, remove_action,
 * and remove_filter calls from the AST, along with function/method parameter
 * counts for cross-referencing callback arg mismatches.
 *
 * @package WPCC
 * @since 1.1.0
 */

namespace WPCC\AST;

use PhpParser\Node;
use PhpParser\NodeVisitorAbstract;
use PhpParser\Node\Expr\FuncCall;
use PhpParser\Node\Expr\StaticCall;
use PhpParser\Node\Expr\MethodCall;
use PhpParser\Node\Expr\Array_;
use PhpParser\Node\Expr\Variable;
use PhpParser\Node\Expr\ClassConstFetch;
use PhpParser\Node\Scalar\String_;
use PhpParser\Node\Scalar\Int_;
use PhpParser\Node\Name;
use PhpParser\Node\Stmt\Function_;
use PhpParser\Node\Stmt\ClassMethod;
use PhpParser\Node\Stmt\Class_;

class HookRegistrationVisitor extends NodeVisitorAbstract {

    /**
     * Hook registration/fire functions we track.
     */
    private const REGISTRATION_FUNCTIONS = [
        'add_action'    => 'action',
        'add_filter'    => 'filter',
        'remove_action' => 'remove_action',
        'remove_filter' => 'remove_filter',
    ];

    private const FIRE_FUNCTIONS = [
        'do_action'     => 'action',
        'apply_filters' => 'filter',
    ];

    /**
     * Collected hook registrations.
     *
     * @var array<int, array{type: string, hook: string, callback: string, priority: int, accepted_args: int, file: string, line: int}>
     */
    private array $registrations = [];

    /**
     * Collected hook fire points.
     *
     * @var array<int, array{type: string, hook: string, args_passed: int, file: string, line: int}>
     */
    private array $fire_points = [];

    /**
     * Collected function/method definitions with parameter counts.
     *
     * @var array<string, array{params: int, required_params: int, file: string, line: int}>
     */
    private array $callables = [];

    /**
     * Current file being analyzed.
     *
     * @var string
     */
    private string $current_file = '';

    /**
     * Current class name for resolving method scope.
     *
     * @var string|null
     */
    private ?string $current_class = null;

    /**
     * Set the current file path for context.
     *
     * @param string $file_path Path to the file being analyzed.
     */
    public function setCurrentFile( string $file_path ): void {
        $this->current_file = $file_path;
    }

    /**
     * Visit each node in the AST.
     *
     * @param Node $node The current node.
     * @return int|Node|null
     */
    public function enterNode( Node $node ) {
        // Track current class scope.
        if ( $node instanceof Class_ && $node->name !== null ) {
            $this->current_class = $node->name->toString();
        }

        // Collect function definitions.
        if ( $node instanceof Function_ ) {
            $name = $node->name->toString();
            $this->callables[ $name ] = [
                'params'          => count( $node->params ),
                'required_params' => $this->countRequiredParams( $node->params ),
                'file'            => $this->current_file,
                'line'            => $node->getLine(),
            ];
        }

        // Collect method definitions.
        if ( $node instanceof ClassMethod ) {
            $class_name = $this->current_class ?? '__anonymous';
            $key        = $class_name . '::' . $node->name->toString();
            $this->callables[ $key ] = [
                'params'          => count( $node->params ),
                'required_params' => $this->countRequiredParams( $node->params ),
                'file'            => $this->current_file,
                'line'            => $node->getLine(),
            ];
        }

        // Check for hook function calls.
        if ( $node instanceof FuncCall && $node->name instanceof Name ) {
            $func_name = $node->name->toString();

            if ( isset( self::REGISTRATION_FUNCTIONS[ $func_name ] ) ) {
                $this->collectRegistration( $node, $func_name );
            }

            if ( isset( self::FIRE_FUNCTIONS[ $func_name ] ) ) {
                $this->collectFirePoint( $node, $func_name );
            }
        }

        return null;
    }

    /**
     * Leave class scope.
     *
     * @param Node $node The current node.
     * @return int|Node|null
     */
    public function leaveNode( Node $node ) {
        if ( $node instanceof Class_ ) {
            $this->current_class = null;
        }
        return null;
    }

    /**
     * Collect a hook registration call (add_action, add_filter, remove_action, remove_filter).
     *
     * @param FuncCall $node      The function call node.
     * @param string   $func_name The function name.
     */
    private function collectRegistration( FuncCall $node, string $func_name ): void {
        $args = $node->args;
        if ( count( $args ) < 2 ) {
            return;
        }

        $hook_name = $this->resolveStringValue( $args[0]->value );
        if ( $hook_name === null ) {
            return;
        }

        $callback_ref   = $this->resolveCallbackReference( $args[1]->value );
        $priority       = isset( $args[2] ) ? $this->resolveIntValue( $args[2]->value ) : 10;
        $accepted_args  = isset( $args[3] ) ? $this->resolveIntValue( $args[3]->value ) : 1;

        $this->registrations[] = [
            'type'          => self::REGISTRATION_FUNCTIONS[ $func_name ],
            'function'      => $func_name,
            'hook'          => $hook_name,
            'callback'      => $callback_ref,
            'priority'      => $priority,
            'accepted_args' => $accepted_args,
            'file'          => $this->current_file,
            'line'          => $node->getLine(),
        ];
    }

    /**
     * Collect a hook fire point (do_action, apply_filters).
     *
     * @param FuncCall $node      The function call node.
     * @param string   $func_name The function name.
     */
    private function collectFirePoint( FuncCall $node, string $func_name ): void {
        $args = $node->args;
        if ( count( $args ) < 1 ) {
            return;
        }

        $hook_name = $this->resolveStringValue( $args[0]->value );
        if ( $hook_name === null ) {
            return;
        }

        // Args passed to callbacks = total args minus the hook name itself.
        $args_passed = count( $args ) - 1;

        $this->fire_points[] = [
            'type'        => self::FIRE_FUNCTIONS[ $func_name ],
            'function'    => $func_name,
            'hook'        => $hook_name,
            'args_passed' => $args_passed,
            'file'        => $this->current_file,
            'line'        => $node->getLine(),
        ];
    }

    /**
     * Resolve a callback argument to a readable reference string.
     *
     * Handles:
     *   - String literal: 'my_function'
     *   - Array literal: [$this, 'method'] or ['ClassName', 'method']
     *   - Class constant: ClassName::class with method
     *
     * @param Node $node The callback argument node.
     * @return string Resolved reference or '{dynamic}'.
     */
    private function resolveCallbackReference( Node $node ): string {
        // String callback: 'my_function'
        if ( $node instanceof String_ ) {
            return $node->value;
        }

        // Array callback: [$this, 'method'] or ['ClassName', 'method']
        if ( $node instanceof Array_ && count( $node->items ) === 2 ) {
            $class_part  = $node->items[0]->value ?? null;
            $method_part = $node->items[1]->value ?? null;

            $class_name = null;
            if ( $class_part instanceof Variable && $class_part->name === 'this' ) {
                $class_name = $this->current_class ?? '$this';
            } elseif ( $class_part instanceof String_ ) {
                $class_name = $class_part->value;
            } elseif ( $class_part instanceof ClassConstFetch
                && $class_part->name instanceof Node\Identifier
                && $class_part->name->toString() === 'class' ) {
                if ( $class_part->class instanceof Name ) {
                    $resolved = $class_part->class->toString();
                    $class_name = ( $resolved === 'self' || $resolved === 'static' )
                        ? ( $this->current_class ?? $resolved )
                        : $resolved;
                }
            }

            $method_name = null;
            if ( $method_part instanceof String_ ) {
                $method_name = $method_part->value;
            }

            if ( $class_name && $method_name ) {
                return $class_name . '::' . $method_name;
            }
        }

        return '{dynamic}';
    }

    /**
     * Resolve a node to a string value, if it is a string literal.
     *
     * @param Node $node The node to resolve.
     * @return string|null The string value, or null if not a literal.
     */
    private function resolveStringValue( Node $node ): ?string {
        if ( $node instanceof String_ ) {
            return $node->value;
        }
        return null;
    }

    /**
     * Resolve a node to an integer value, if it is an integer literal.
     *
     * @param Node $node The node to resolve.
     * @return int The integer value, or default of 10 if not a literal.
     */
    private function resolveIntValue( Node $node ): int {
        if ( $node instanceof Int_ ) {
            return $node->value;
        }
        // Could be a constant like PHP_INT_MAX — treat as unknown, use default.
        return -1;
    }

    /**
     * Count required (non-optional) parameters in a parameter list.
     *
     * @param array $params Parameter nodes.
     * @return int Number of required parameters.
     */
    private function countRequiredParams( array $params ): int {
        $required = 0;
        foreach ( $params as $param ) {
            if ( $param->default === null && ! $param->variadic ) {
                $required++;
            }
        }
        return $required;
    }

    /**
     * Get all collected hook registrations.
     *
     * @return array
     */
    public function getRegistrations(): array {
        return $this->registrations;
    }

    /**
     * Get all collected hook fire points.
     *
     * @return array
     */
    public function getFirePoints(): array {
        return $this->fire_points;
    }

    /**
     * Get all collected callable definitions.
     *
     * @return array
     */
    public function getCallables(): array {
        return $this->callables;
    }

    /**
     * Reset the visitor state for reuse.
     */
    public function reset(): void {
        $this->registrations = [];
        $this->fire_points   = [];
        $this->callables     = [];
        $this->current_file  = '';
        $this->current_class = null;
    }
}
