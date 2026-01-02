#!/usr/bin/env bash

# Test pattern extraction
source dist/lib/pattern-loader.sh

echo "Testing pattern extraction..."
echo ""

if load_pattern "dist/patterns/duplicate-option-names.json"; then
  echo "Pattern ID: $pattern_id"
  echo "Pattern Title: $pattern_title"
  echo "Pattern Search Length: ${#pattern_search}"
  echo "Pattern Search: [$pattern_search]"
  echo ""
  
  if [ -z "$pattern_search" ]; then
    echo "❌ FAILED: pattern_search is empty"
    exit 1
  else
    echo "✓ SUCCESS: pattern_search is populated"
    
    # Test if it works with grep
    echo ""
    echo "Testing grep with extracted pattern..."
    test_result=$(echo "get_option( 'test_option' )" | grep -E "$pattern_search")
    if [ -n "$test_result" ]; then
      echo "✓ Pattern matches test string"
    else
      echo "❌ Pattern does NOT match test string"
      exit 1
    fi
  fi
else
  echo "❌ FAILED: Could not load pattern"
  exit 1
fi

