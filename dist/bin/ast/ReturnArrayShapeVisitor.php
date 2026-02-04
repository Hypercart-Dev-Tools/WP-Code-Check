<?php
/**
 * NodeVisitor to collect return statements that return array literals.
 *
 * This visitor identifies functions/methods and their return array shapes
 * to enable static detection of inconsistent or missing array keys.
 *
 * @package WPCC
 * @since 1.0.0
 */

namespace WPCC\AST;

use PhpParser\Node;
use PhpParser\NodeVisitorAbstract;
use PhpParser\Node\Stmt\Return_;
use PhpParser\Node\Expr\Array_;
use PhpParser\Node\Stmt\ClassMethod;
use PhpParser\Node\Stmt\Function_;
use PhpParser\Node\Expr\Closure;
use PhpParser\Node\Stmt\Class_;
use PhpParser\Node\FunctionLike;
use PhpParser\Node\Scalar;

class ReturnArrayShapeVisitor extends NodeVisitorAbstract {

    /**
     * Collected return array shapes, keyed by scope.
     *
     * @var array<string, array{line: int, keys: array<string>, all_keys_literal: bool}>
     */
    private array $return_shapes = [];

    /**
     * Current file being analyzed.
     *
     * @var string
     */
    private string $current_file = '';

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
        // Look for return statements with array literals.
        if ( $node instanceof Return_ && $node->expr instanceof Array_ ) {
            $scope_key = $this->getCurrentScopeKey( $node );
            $keys = $this->extractArrayKeys( $node->expr );
            $all_literal = $this->areAllKeysLiteral( $node->expr );

            $this->return_shapes[] = [
                'file'            => $this->current_file,
                'scope'           => $scope_key,
                'line'            => $node->getLine(),
                'keys'            => $keys,
                'all_keys_literal' => $all_literal,
            ];
        }

        return null;
    }

    /**
     * Extract keys from an array literal.
     *
     * @param Array_ $array_node The array node.
     * @return array<string> List of key names (or indices for list-style arrays).
     */
    private function extractArrayKeys( Array_ $array_node ): array {
        $keys = [];
        $index = 0;

        foreach ( $array_node->items as $item ) {
            if ( $item === null ) {
                continue;
            }

            if ( $item->key !== null ) {
                if ( $item->key instanceof Scalar\String_ ) {
                    $keys[] = $item->key->value;
                } elseif ( $item->key instanceof Scalar\Int_ ) {
                    $keys[] = (string) $item->key->value;
                } else {
                    // Dynamic key - mark with placeholder.
                    $keys[] = '{dynamic}';
                }
            } else {
                // No key = list-style array.
                $keys[] = (string) $index;
                $index++;
            }
        }

        return $keys;
    }

    /**
     * Check if all keys in the array are literal (string or int).
     *
     * @param Array_ $array_node The array node.
     * @return bool True if all keys are literal.
     */
    private function areAllKeysLiteral( Array_ $array_node ): bool {
        foreach ( $array_node->items as $item ) {
            if ( $item === null ) {
                continue;
            }
            if ( $item->key !== null ) {
                if ( ! ( $item->key instanceof Scalar\String_ || $item->key instanceof Scalar\Int_ ) ) {
                    return false;
                }
            }
        }
        return true;
    }

    /**
     * Determine the current function/method scope.
     *
     * @param Node $node The current node.
     * @return string Scope key (e.g., 'ClassName::methodName', 'function_name', '__global__').
     */
    private function getCurrentScopeKey( Node $node ): string {
        $parent = $node->getAttribute( 'parent' );

        while ( $parent ) {
            if ( $parent instanceof FunctionLike ) {
                if ( $parent instanceof ClassMethod ) {
                    $class_name = '__anonymous';
                    $class_parent = $parent->getAttribute( 'parent' );
                    if ( $class_parent instanceof Class_ && $class_parent->name !== null ) {
                        $class_name = $class_parent->name->toString();
                    }
                    return $class_name . '::' . $parent->name->toString();
                }

                if ( $parent instanceof Function_ ) {
                    return $parent->name->toString();
                }

                if ( $parent instanceof Closure ) {
                    return 'closure@line:' . $parent->getStartLine();
                }
            }
            $parent = $parent->getAttribute( 'parent' );
        }

        return '__global__';
    }

    /**
     * Get all collected return shapes.
     *
     * @return array<int, array{file: string, scope: string, line: int, keys: array<string>, all_keys_literal: bool}>
     */
    public function getReturnShapes(): array {
        return $this->return_shapes;
    }

    /**
     * Reset the visitor state for reuse.
     */
    public function reset(): void {
        $this->return_shapes = [];
        $this->current_file = '';
    }
}

